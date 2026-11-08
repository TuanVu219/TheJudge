import { PokerDeck } from "./poker_deck.js";
import { PokerBettingManager, type BettingActionResult } from "./poker_betting.js";
import type { BettingActionType } from "./poker_config.js";
import type { ServerMessage } from "../websocket/protocol.js";
export interface PlayerPokerState {
    playerId: string;
    handDeck: PokerDeck;
    foreheadDeck: PokerDeck;
}
export declare class ForeheadPokerMatch {
    static readonly TOTAL_ROUNDS = 10;
    round: number;
    isMatchStarted: boolean;
    bettingManager: PokerBettingManager;
    stateVersion: number;
    playerSeatMap: Map<string, number>;
    roomCode: string;
    private players;
    constructor(playerIds?: string[], seatAssignments?: Map<string, number>, roomCode?: string);
    /**
     * Initializes a new match for the given player IDs.
     * Creates exactly 2 independent decks (Hand + Forehead) per player and shuffles each independently.
     */
    initMatch(playerIds: string[], seatAssignments?: Map<string, number>, roomCode?: string): void;
    /**
     * Draws the next card from each player's independent Hand and Forehead decks.
     * Advances the round count.
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
