import { randomInt } from "crypto";
export class PokerDeck {
    cards = [];
    usedCards = [];
    currentCard = null;
    deckName;
    playerId;
    constructor(playerId, deckName) {
        this.playerId = playerId;
        this.deckName = deckName;
        this.reset();
    }
    /**
     * Restores deck to full set [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] and clears history.
     */
    reset() {
        this.cards = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        this.usedCards = [];
        this.currentCard = null;
    }
    /**
     * Shuffles cards using cryptographically secure Fisher-Yates algorithm.
     */
    shuffle() {
        for (let i = this.cards.length - 1; i > 0; i--) {
            const j = randomInt(0, i + 1);
            const temp = this.cards[i];
            this.cards[i] = this.cards[j];
            this.cards[j] = temp;
        }
    }
    /**
     * Draws the next card from the deck.
     * The card is permanently removed from this deck for the match and recorded in used history.
     * Returns null if deck is exhausted.
     */
    draw() {
        if (this.cards.length === 0) {
            this.currentCard = null;
            return null;
        }
        const drawn = this.cards.pop();
        this.currentCard = drawn;
        this.usedCards.push(drawn);
        return drawn;
    }
    remainingCount() {
        return this.cards.length;
    }
    isExhausted() {
        return this.cards.length === 0;
    }
    getUsedHistory() {
        return [...this.usedCards];
    }
}
