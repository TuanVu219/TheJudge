import { PokerDeck } from "./poker_deck.js";
import { PokerBettingManager, type BettingActionResult } from "./poker_betting.js";
import { PokerShowdownManager, type RoundResult } from "./poker_showdown.js";
import { POKER_CONFIG, type BettingActionType } from "./poker_config.js";
import type { ServerMessage } from "../websocket/protocol.js";

export type PokerRoundPhase = "IDLE" | "PICKING" | "BETTING" | "SHOWDOWN" | "ROUND_END";

export interface PlayerPokerState {
  playerId: string;
  handDeck: PokerDeck;
  foreheadDeck: PokerDeck;
  pickedHandSlot: number | null;
  pickedForeheadSlot: number | null;
  isPickConfirmed: boolean;
}

export class ForeheadPokerMatch {
  public static readonly TOTAL_ROUNDS = 10;
  public static readonly PICK_COUNTDOWN_SECONDS = 15;

  public round: number = 0;
  public phase: PokerRoundPhase = "IDLE";
  public isMatchStarted: boolean = false;
  public bettingManager: PokerBettingManager = new PokerBettingManager();
  public stateVersion: number = 0;
  public playerSeatMap: Map<string, number> = new Map();
  public roomCode: string = "";
  public matchHistory: RoundResult[] = [];
  public lastRoundResult: RoundResult | null = null;
  private players: Map<string, PlayerPokerState> = new Map();

  constructor(playerIds: string[] = [], seatAssignments?: Map<string, number>, roomCode: string = "") {
    if (playerIds.length > 0) {
      this.initMatch(playerIds, seatAssignments, roomCode);
    }
  }

  /**
   * Initializes a new match for the given player IDs.
   * Creates exactly 2 independent decks (Hand + Forehead) per player and shuffles each independently across 10 slots.
   */
  public initMatch(playerIds: string[], seatAssignments?: Map<string, number>, roomCode: string = ""): void {
    this.players.clear();
    this.playerSeatMap.clear();
    this.round = 0;
    this.phase = "IDLE";
    this.roomCode = roomCode;
    this.stateVersion = 1;
    this.bettingManager.initPlayers(playerIds);

    for (let i = 0; i < playerIds.length; i++) {
      const pid = playerIds[i];
      const assignedSeat = seatAssignments?.has(pid) ? seatAssignments.get(pid)! : i;
      this.playerSeatMap.set(pid, assignedSeat);

      const handDeck = new PokerDeck(pid, "HAND");
      const foreheadDeck = new PokerDeck(pid, "FOREHEAD");

      handDeck.shuffle();
      foreheadDeck.shuffle();

      this.players.set(pid, {
        playerId: pid,
        handDeck,
        foreheadDeck,
        pickedHandSlot: null,
        pickedForeheadSlot: null,
        isPickConfirmed: false,
      });
    }

    this.isMatchStarted = true;
  }

  /**
   * Starts the 15-second Card Picking Phase for a new round.
   */
  public startRoundPicking(roundNum?: number): { success: boolean; round: number; error?: string } {
    if (!this.isMatchStarted) {
      return { success: false, round: this.round, error: "MATCH_NOT_STARTED" };
    }

    if (this.round >= ForeheadPokerMatch.TOTAL_ROUNDS || this.isExhausted()) {
      return { success: false, round: this.round, error: "DECKS_EXHAUSTED" };
    }

    this.round = roundNum !== undefined ? roundNum : (this.round + 1);
    this.phase = "PICKING";
    this.stateVersion++;

    for (const [, state] of this.players) {
      state.pickedHandSlot = null;
      state.pickedForeheadSlot = null;
      state.isPickConfirmed = false;
    }

    return { success: true, round: this.round };
  }

  /**
   * Records a player's choice of card slots for their Hand and Forehead decks.
   * If a slot is not specified or null, it keeps previous pick or remains pending.
   */
  public setPlayerPick(
    playerId: string,
    handSlot: number | null | undefined,
    foreheadSlot: number | null | undefined
  ): { success: boolean; allConfirmed: boolean; error?: string } {
    const state = this.players.get(playerId);
    if (!state) {
      return { success: false, allConfirmed: false, error: "PLAYER_NOT_FOUND" };
    }

    if (this.phase !== "PICKING") {
      return { success: false, allConfirmed: false, error: "NOT_IN_PICKING_PHASE" };
    }

    if (handSlot !== undefined && handSlot !== null) {
      if (!state.handDeck.isSlotAvailable(handSlot)) {
        return { success: false, allConfirmed: false, error: "HAND_SLOT_UNAVAILABLE" };
      }
      state.pickedHandSlot = handSlot;
    }

    if (foreheadSlot !== undefined && foreheadSlot !== null) {
      if (!state.foreheadDeck.isSlotAvailable(foreheadSlot)) {
        return { success: false, allConfirmed: false, error: "FOREHEAD_SLOT_UNAVAILABLE" };
      }
      state.pickedForeheadSlot = foreheadSlot;
    }

    if (state.pickedHandSlot !== null && state.pickedForeheadSlot !== null) {
      state.isPickConfirmed = true;
    }

    const allConfirmed = this.areAllActivePicksConfirmed();
    return { success: true, allConfirmed };
  }

  public areAllActivePicksConfirmed(): boolean {
    if (this.players.size === 0) return false;
    for (const [, state] of this.players) {
      if (!state.isPickConfirmed) {
        return false;
      }
    }
    return true;
  }

  /**
   * Finalizes the picking phase:
   * Any slot not explicitly chosen by a player is automatically chosen at random from remaining slots.
   * Draws the cards from the chosen slots, updates history, and transitions match into the BETTING phase.
   */
  public finalizePicking(): {
    round: number;
    playerPicks: Record<string, { handSlot: number; foreheadSlot: number; handCard: number; foreheadCard: number }>;
  } {
    const playerPicks: Record<string, { handSlot: number; foreheadSlot: number; handCard: number; foreheadCard: number }> = {};

    for (const [pid, state] of this.players) {
      const hRes = state.handDeck.drawSlot(state.pickedHandSlot);
      const fRes = state.foreheadDeck.drawSlot(state.pickedForeheadSlot);

      playerPicks[pid] = {
        handSlot: hRes.slot ?? 0,
        foreheadSlot: fRes.slot ?? 0,
        handCard: hRes.card ?? 1,
        foreheadCard: fRes.card ?? 1,
      };
    }

    this.phase = "BETTING";
    this.stateVersion++;

    // Start betting phase and collect ante
    this.bettingManager.startRound(this.round);

    return { round: this.round, playerPicks };
  }

  /**
   * Legacy drawRound: starts picking phase and immediately finalizes with random/pending slots.
   */
  public drawRound(): { success: boolean; round: number; error?: string } {
    const startRes = this.startRoundPicking();
    if (!startRes.success) return startRes;
    this.finalizePicking();
    return { success: true, round: this.round };
  }

  /**
   * Constructs the strictly private payload containing ONLY the player's own Hand card.
   * NEVER reveals their Forehead card or any opponent's Hand card.
   */
  public getPrivateHandPayload(playerId: string): {
    type: "POKER_PRIVATE_HAND";
    round: number;
    card: number | null;
    slot: number | null;
    history: number[];
  } | null {
    const state = this.players.get(playerId);
    if (!state) return null;

    return {
      type: "POKER_PRIVATE_HAND",
      round: this.round,
      card: state.handDeck.currentCard,
      slot: state.handDeck.currentSlot,
      history: state.handDeck.getUsedHistory(),
    };
  }

  /**
   * Constructs the payload containing ONLY the forehead cards of the player's OPPONENTS.
   * GUARANTEE: Never includes the player's own Forehead card, and never includes any Hand cards.
   */
  public getOpponentForeheadsPayload(playerId: string): {
    type: "POKER_OPPONENT_FOREHEADS";
    round: number;
    cards: Array<{ player_id: string; card: number | null; slot: number | null; history: number[] }>;
  } | null {
    if (!this.players.has(playerId)) return null;

    const opponentCards: Array<{ player_id: string; card: number | null; slot: number | null; history: number[] }> = [];

    for (const [otherId, otherState] of this.players) {
      if (otherId === playerId) continue;

      opponentCards.push({
        player_id: otherId,
        card: otherState.foreheadDeck.currentCard,
        slot: otherState.foreheadDeck.currentSlot,
        history: otherState.foreheadDeck.getUsedHistory(),
      });
    }

    return {
      type: "POKER_OPPONENT_FOREHEADS",
      round: this.round,
      cards: opponentCards,
    };
  }

  /**
   * Constructs public round status for the room.
   * Contains ZERO card values.
   */
  public getPublicRoundStatusPayload(): {
    type: "POKER_ROUND_STATUS";
    round: number;
    total_rounds: number;
    is_exhausted: boolean;
  } {
    return {
      type: "POKER_ROUND_STATUS",
      round: this.round,
      total_rounds: ForeheadPokerMatch.TOTAL_ROUNDS,
      is_exhausted: this.isExhausted(),
    };
  }

  /**
   * Resets all decks for all players back to full sets [1..10], reshuffles, and resets round to 0.
   */
  public resetMatch(): void {
    this.round = 0;
    this.phase = "IDLE";
    this.matchHistory = [];
    this.lastRoundResult = null;
    this.stateVersion++;
    for (const [, state] of this.players) {
      state.handDeck.reset();
      state.foreheadDeck.reset();
      state.handDeck.shuffle();
      state.foreheadDeck.shuffle();
      state.pickedHandSlot = null;
      state.pickedForeheadSlot = null;
      state.isPickConfirmed = false;
    }
    this.bettingManager.initPlayers(this.getPlayerIds());
  }

  /**
   * Resolves showdown and pot distribution authoritatively for this round.
   */
  public resolveShowdown(): RoundResult {
    const res = PokerShowdownManager.resolveRoundResult(
      this.round,
      this.bettingManager,
      this.players,
      this.playerSeatMap,
      this.stateVersion
    );
    this.lastRoundResult = res;
    this.matchHistory.push(res);
    this.phase = res.isMatchCompleted ? "ROUND_END" : "SHOWDOWN";
    this.stateVersion++;
    return res;
  }

  public getOverallWinners(): {
    winners: string[];
    finalBalances: Record<string, number>;
    chipsWon: Record<string, number>;
  } {
    const finalBalances: Record<string, number> = {};
    const chipsWon: Record<string, number> = {};
    let maxBal = -1;
    let winners: string[] = [];

    for (const [pid, pBet] of this.bettingManager.players) {
      finalBalances[pid] = pBet.balance;
      chipsWon[pid] = pBet.balance - POKER_CONFIG.STARTING_CHIPS;
      if (pBet.balance > maxBal) {
        maxBal = pBet.balance;
        winners = [pid];
      } else if (pBet.balance === maxBal) {
        winners.push(pid);
      }
    }

    return { winners, finalBalances, chipsWon };
  }

  public processBettingAction(
    playerId: string,
    action: BettingActionType,
    targetRaiseBet: number = 0
  ): BettingActionResult {
    const res = this.bettingManager.processAction(playerId, action, targetRaiseBet);
    if (res.success) {
      this.stateVersion++;
    }
    return res;
  }

  public getPublicBettingPayload(roomCodeOverride?: string): ServerMessage {
    const pub = this.bettingManager.toPublicState();
    const playersArray = Array.from(this.players.keys()).map((pid) => {
      const pState = pub.players[pid] || {};
      const seatIdx = this.playerSeatMap.get(pid) ?? 0;
      return {
        player_id: pid,
        seat_index: seatIdx,
        balance: pState.balance ?? 100,
        round_bet: pState.round_bet ?? 0,
        total_contribution: pState.total_contribution ?? 0,
        is_folded: pState.is_folded ?? false,
        is_all_in: pState.is_all_in ?? false,
        has_acted: pState.has_acted ?? false,
      };
    });

    return {
      type: "POKER_BETTING_STATE",
      version: this.stateVersion,
      room_code: roomCodeOverride || this.roomCode,
      round: pub.round,
      total_pot: pub.total_pot,
      main_pot: pub.main_pot,
      side_pots: pub.side_pots,
      current_highest_bet: pub.current_highest_bet,
      min_raise_increment: pub.min_raise_increment,
      current_turn_player_id: pub.current_turn_player_id,
      betting_active: pub.betting_active,
      betting_phase_active: pub.betting_active,
      last_action_player_id: pub.last_action?.player_id ?? null,
      last_action_type: pub.last_action?.action ?? null,
      last_action_amount: pub.last_action?.amount ?? null,
      last_action: pub.last_action,
      players: playersArray,
      players_state: pub.players,
    };
  }

  public isExhausted(): boolean {
    for (const [, state] of this.players) {
      if (state.handDeck.isExhausted() || state.foreheadDeck.isExhausted()) {
        return true;
      }
    }
    return false;
  }

  public getPlayerCount(): number {
    return this.players.size;
  }

  public getPlayerIds(): string[] {
    return Array.from(this.players.keys());
  }

  public getPlayerState(playerId: string): PlayerPokerState | undefined {
    return this.players.get(playerId);
  }
}
