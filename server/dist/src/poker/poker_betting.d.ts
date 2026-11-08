import { type BettingActionType } from "./poker_config.js";
export interface PlayerBettingState {
    playerId: string;
    startingBalance: number;
    balance: number;
    anteContribution: number;
    roundBetContribution: number;
    totalHandContribution: number;
    isFolded: boolean;
    isAllIn: boolean;
    hasActedThisRound: boolean;
    isDisconnected: boolean;
}
export interface SidePot {
    potAmount: number;
    eligiblePlayerIds: string[];
}
export interface BettingActionResult {
    success: boolean;
    action: BettingActionType;
    playerId: string;
    amountAdded: number;
    targetBet: number;
    error?: string;
    isRoundComplete: boolean;
    nextTurnPlayerId: string | null;
}
export declare class PokerBettingManager {
    players: Map<string, PlayerBettingState>;
    playerOrder: string[];
    currentHighestBet: number;
    minRaiseIncrement: number;
    currentTurnPlayerId: string | null;
    bettingPhaseActive: boolean;
    roundNumber: number;
    anteDeductedThisRound: boolean;
    lastActionPlayerId: string | null;
    lastActionType: BettingActionType | null;
    lastActionAmount: number | null;
    mainPot: number;
    sidePots: SidePot[];
    totalPot: number;
    constructor(playerIds?: string[], startingChips?: number);
    initPlayers(playerIds: string[], startingChips?: number): void;
    /**
     * Starts a new round of betting:
     * 1. Collects ante exactly once per round.
     * 2. Resets round-specific bet contributions.
     * 3. Sets first active turn.
     */
    startRound(roundNum: number): {
        success: boolean;
        error?: string;
    };
    /**
     * Deducts mandatory ante from every eligible player.
     */
    collectAnte(): void;
    /**
     * Processes a player betting action (FOLD, CHECK, CALL, RAISE, ALL_IN).
     */
    processAction(playerId: string, action: BettingActionType, targetRaiseBet?: number): BettingActionResult;
    /**
     * Re-opens action for all non-folded, non-all-in players when a full raise occurs.
     */
    private reopenActionForOthers;
    /**
     * Re-opens action only for players who currently owe chips.
     */
    private reopenActionForUnderpayingOthers;
    /**
     * Finds the next player in cyclic order who is not folded, not all-in, and not disconnected.
     */
    findNextEligiblePlayer(fromIndex: number): string | null;
    /**
     * Checks whether the current betting round is complete according to poker rules:
     * 1. Only one non-folded player remains; OR
     * 2. All remaining eligible players have acted AND matched the highest bet; OR
     * 3. All non-folded players are All-In.
     */
    checkBettingComplete(): boolean;
    private finishBettingPhase;
    /**
     * Calculates main pot and layered side pots based on all players' totalHandContribution.
     * Folded contributions are kept in the pots, but folded players are strictly excluded from eligibility.
     */
    calculatePots(): void;
    /**
     * Asserts mathematical invariants:
     * 1. Total pot === sum of all players' totalHandContribution.
     * 2. Starting balance === current balance + totalHandContribution.
     */
    assertInvariants(): void;
    handleDisconnect(playerId: string): void;
    handleReconnect(playerId: string): void;
    resetAllPotState(): void;
    toPublicState(): {
        round: number;
        total_pot: number;
        main_pot: number;
        side_pots: SidePot[];
        current_highest_bet: number;
        min_raise_increment: number;
        current_turn_player_id: string | null;
        betting_active: boolean;
        last_action: {
            player_id: string;
            action: BettingActionType | null;
            amount: number | null;
        } | null;
        players: Record<string, any>;
    };
    private failResult;
}
