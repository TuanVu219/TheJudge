import { randomInt } from "crypto";
export class PokerDeck {
    slots = [];
    usedCards = [];
    usedSlots = [];
    currentCard = null;
    currentSlot = null;
    deckName;
    playerId;
    constructor(playerId, deckName) {
        this.playerId = playerId;
        this.deckName = deckName;
        this.reset();
    }
    /**
     * Restores deck to full set [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] across slots 0..9 and clears history.
     */
    reset() {
        this.slots = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        this.usedCards = [];
        this.usedSlots = [];
        this.currentCard = null;
        this.currentSlot = null;
    }
    /**
     * Shuffles cards across slots 0..9 using cryptographically secure Fisher-Yates algorithm.
     */
    shuffle() {
        for (let i = this.slots.length - 1; i > 0; i--) {
            const j = randomInt(0, i + 1);
            const temp = this.slots[i];
            this.slots[i] = this.slots[j];
            this.slots[j] = temp;
        }
    }
    isSlotAvailable(slotIndex) {
        return slotIndex >= 0 && slotIndex < 10 && this.slots[slotIndex] !== null;
    }
    getAvailableSlots() {
        const res = [];
        for (let i = 0; i < 10; i++) {
            if (this.slots[i] !== null) {
                res.push(i);
            }
        }
        return res;
    }
    getUsedSlots() {
        return [...this.usedSlots];
    }
    /**
     * Draws a card from a specific slot index (0..9).
     * If slotIndex is not specified or slot is already taken, picks a random available slot.
     * Permanently clears that slot (sets to null) and records it in usedSlots & usedCards.
     */
    drawSlot(slotIndex) {
        const available = this.getAvailableSlots();
        if (available.length === 0) {
            this.currentCard = null;
            this.currentSlot = null;
            return { card: null, slot: null };
        }
        let targetSlot;
        if (slotIndex !== undefined && slotIndex !== null && this.isSlotAvailable(slotIndex)) {
            targetSlot = slotIndex;
        }
        else {
            const rIdx = randomInt(0, available.length);
            targetSlot = available[rIdx];
        }
        const drawn = this.slots[targetSlot];
        this.slots[targetSlot] = null;
        this.currentCard = drawn;
        this.currentSlot = targetSlot;
        this.usedCards.push(drawn);
        this.usedSlots.push(targetSlot);
        return { card: drawn, slot: targetSlot };
    }
    /**
     * Backward-compatible draw(): draws a random available slot.
     */
    draw() {
        return this.drawSlot().card;
    }
    remainingCount() {
        return this.getAvailableSlots().length;
    }
    isExhausted() {
        return this.remainingCount() === 0;
    }
    getUsedHistory() {
        return [...this.usedCards];
    }
}
