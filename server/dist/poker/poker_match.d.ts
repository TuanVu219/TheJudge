import { PokerDeck } from "./poker_deck.js";
import { PokerBettingManager, type BettingActionResult } from "./poker_betting.js";
import type { BettingActionType } from "./poker_config.js";
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
export declare class ForeheadPokerMatch {
    static readonly TOTAL_ROUNDS = 10;
    static readonly PICK_COUNTDOWN_SECONDS = 15;
    round: number;
    phase: PokerRoundPhase;
    isMatchStarted: boolean;
    bettingManager: PokerBettingManager;
    stateVersion: number;
    playerSeatMap: Map<string, number>;
    roomCode: string;
    private players;
    constructor(playerIds?: string[], seatAssignments?: Map<string, number>, roomCode?: string);
    /**
     * Initializes a new match for the given player IDs.
     * Creates exactly 2 independent decks (Hand + Forehead) per player and shuffles each independently across 10 slots.
     */
    initMatch(playerIds: string[], seatAssignments?: Map<string, number>, roomCode?: string): void;
    /**
     * Starts the 15-second Card Picking Phase for a new round.
     */
    startRoundPicking(roundNum?: number): {
        success: boolean;
        round: number;
        error?: string;
    };
    /**
     * Records a player's choice of card slots for their Hand and Forehead decks.
     * If a slot is not specified or null, it keeps previous pick or remains pending.
     */
    setPlayerPick(playerId: string, handSlot: number | null | undefined, foreheadSlot: number | null | undefined): {
        success: boolean;
        allConfirmed: boolean;
        error?: string;
    };
    areAllActivePicksConfirmed(): boolean;
    /**
     * Finalizes the picking phase:
     * Any slot not explicitly chosen by a player is automatically chosen at random from remaining slots.
     * Draws the cards from the chosen slots, updates history, and transitions match into the BETTING phase.
     */
    finalizePicking(): {
        round: number;
        playerPicks: Record<string, {
            handSlot: number;
            foreheadSlot: number;
            handCard: number;
            foreheadCard: number;
        }>;
    };
    /**
     * Legacy drawRound: starts picking phase and immediately finalizes with random/pending slots.
     */
    drawRound(): {
        success: boolean;
        round: number;
        error?: string;
    };
    /**
     * Constructs the strictly private payload containing ONLY the player's own Hand card.
     * NEVER reveals their Forehead card or any opponent's Hand card.
     */
    getPrivateHandPayload(playerId: string): {
        type: "POKER_PRIVATE_HAND";
        round: number;
        card: number | null;
        slot: number | null;
        history: number[];
    } | null;
    /**
     * Constructs the payload containing ONLY the forehead cards of the player's OPPONENTS.
     * GUARANTEE: Never includes the player's own Forehead card, and never includes any Hand cards.
     */
    getOpponentForeheadsPayload(playerId: string): {
        type: "POKER_OPPONENT_FOREHEADS";
        round: number;
        cards: Array<{
            player_id: string;
            card: number | null;
            slot: number | null;
            history: number[];
        }>;
    } | null;
    /**
     * Constructs public round status for the room.
     * Contains ZERO card values.
     */
    getPublicRoundStatusPayload(): {
        type: "POKER_ROUND_STATUS";
        round: number;
        total_rounds: number;
        is_exhausted: boolean;
    };
    /**
     * Resets all decks for all players back to full sets [1..10], reshuffles, and resets round to 0.
     */
    resetMatch(): void;
    processBettingAction(playerId: string, action: BettingActionType, targetRaiseBet?: number): BettingActionResult;
    getPublicBettingPayload(roomCodeOverride?: string): ServerMessage;
    isExhausted(): boolean;
    getPlayerCount(): number;
    getPlayerIds(): string[];
    getPlayerState(playerId: string): PlayerPokerState | undefined;
}
