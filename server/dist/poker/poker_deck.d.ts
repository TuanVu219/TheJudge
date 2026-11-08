export declare class PokerDeck {
    slots: (number | null)[];
    usedCards: number[];
    usedSlots: number[];
    currentCard: number | null;
    currentSlot: number | null;
    readonly deckName: string;
    readonly playerId: string;
    get cards(): number[];
    set cards(val: number[]);
    constructor(playerId: string, deckName: "HAND" | "FOREHEAD");
    /**
     * Restores deck to full set [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] across slots 0..9 and clears history.
     */
    reset(): void;
    /**
     * Shuffles cards across slots 0..9 using cryptographically secure Fisher-Yates algorithm.
     */
    shuffle(): void;
    isSlotAvailable(slotIndex: number): boolean;
    getAvailableSlots(): number[];
    getUsedSlots(): number[];
    /**
     * Draws a card from a specific slot index (0..9).
     * If slotIndex is not specified or slot is already taken, picks a random available slot.
     * Permanently clears that slot (sets to null) and records it in usedSlots & usedCards.
     */
    drawSlot(slotIndex?: number | null): {
        card: number | null;
        slot: number | null;
    };
    /**
     * Backward-compatible draw(): draws a random available slot.
     */
    draw(): number | null;
    remainingCount(): number;
    isExhausted(): boolean;
    getUsedHistory(): number[];
}
