import type { PokerBettingManager } from "./poker_betting.js";
import type { PlayerPokerState } from "./poker_match.js";
export interface RevealedCardInfo {
    handCard: number;
    foreheadCard: number;
    totalScore: number;
}
export interface PotPayout {
    potName: string;
    potAmount: number;
    eligiblePlayerIds: string[];
    winningPlayerIds: string[];
    winningScore: number;
    payouts: Record<string, number>;
}
export interface RoundResult {
    roundNumber: number;
    resultType: "SHOWDOWN" | "UNCONTESTED";
    revealedCards: Record<string, RevealedCardInfo>;
    playerScores: Record<string, number>;
    winnerPlayerIds: string[];
    tiedWinnerIds: string[];
    mainPotDistribution: PotPayout;
    sidePotDistributions: PotPayout[];
    totalAwardedByPlayer: Record<string, number>;
    updatedBalances: Record<string, number>;
    finalPot: number;
    isMatchCompleted: boolean;
    stateVersion: number;
    timestamp: number;
}
export declare class PokerShowdownManager {
    /**
     * Evaluates the outcome of a completed betting round, reveals cards where appropriate,
     * calculates scores (Hand + Forehead), and distributes Main Pot and Side Pots authoritatively.
     */
    static resolveRoundResult(roundNumber: number, bettingManager: PokerBettingManager, matchPlayers: Map<string, PlayerPokerState>, playerSeatMap: Map<string, number>, stateVersion: number): RoundResult;
}
