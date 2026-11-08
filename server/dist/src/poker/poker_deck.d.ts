export declare class PokerDeck {
    cards: number[];
    usedCards: number[];
    currentCard: number | null;
    readonly deckName: string;
    readonly playerId: string;
    constructor(playerId: string, deckName: "HAND" | "FOREHEAD");
    /**
     * Restores deck to full set [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] and clears history.
     */
    reset(): void;
    /**
     * Shuffles cards using cryptographically secure Fisher-Yates algorithm.
     */
    shuffle(): void;
    /**
     * Draws the next card from the deck.
     * The card is permanently removed from this deck for the match and recorded in used history.
     * Returns null if deck is exhausted.
     */
    draw(): number | null;
    remainingCount(): number;
    isExhausted(): boolean;
    getUsedHistory(): number[];
}
