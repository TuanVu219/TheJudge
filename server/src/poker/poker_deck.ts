import { randomInt } from "crypto";

export class PokerDeck {
  public cards: number[] = [];
  public usedCards: number[] = [];
  public currentCard: number | null = null;
  public readonly deckName: string;
  public readonly playerId: string;

  constructor(playerId: string, deckName: "HAND" | "FOREHEAD") {
    this.playerId = playerId;
    this.deckName = deckName;
    this.reset();
  }

  /**
   * Restores deck to full set [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] and clears history.
   */
  public reset(): void {
    this.cards = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    this.usedCards = [];
    this.currentCard = null;
  }

  /**
   * Shuffles cards using cryptographically secure Fisher-Yates algorithm.
   */
  public shuffle(): void {
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
  public draw(): number | null {
    if (this.cards.length === 0) {
      this.currentCard = null;
      return null;
    }

    const drawn = this.cards.pop()!;
    this.currentCard = drawn;
    this.usedCards.push(drawn);
    return drawn;
  }

  public remainingCount(): number {
    return this.cards.length;
  }

  public isExhausted(): boolean {
    return this.cards.length === 0;
  }

  public getUsedHistory(): number[] {
    return [...this.usedCards];
  }
}

