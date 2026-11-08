import { randomInt } from "crypto";

export class PokerDeck {
  public slots: (number | null)[] = [];
  public usedCards: number[] = [];
  public usedSlots: number[] = [];
  public currentCard: number | null = null;
  public currentSlot: number | null = null;
  public readonly deckName: string;
  public readonly playerId: string;

  constructor(playerId: string, deckName: "HAND" | "FOREHEAD") {
    this.playerId = playerId;
    this.deckName = deckName;
    this.reset();
  }

  /**
   * Restores deck to full set [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] across slots 0..9 and clears history.
   */
  public reset(): void {
    this.slots = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    this.usedCards = [];
    this.usedSlots = [];
    this.currentCard = null;
    this.currentSlot = null;
  }

  /**
   * Shuffles cards across slots 0..9 using cryptographically secure Fisher-Yates algorithm.
   */
  public shuffle(): void {
    for (let i = this.slots.length - 1; i > 0; i--) {
      const j = randomInt(0, i + 1);
      const temp = this.slots[i];
      this.slots[i] = this.slots[j];
      this.slots[j] = temp;
    }
  }

  public isSlotAvailable(slotIndex: number): boolean {
    return slotIndex >= 0 && slotIndex < 10 && this.slots[slotIndex] !== null;
  }

  public getAvailableSlots(): number[] {
    const res: number[] = [];
    for (let i = 0; i < 10; i++) {
      if (this.slots[i] !== null) {
        res.push(i);
      }
    }
    return res;
  }

  public getUsedSlots(): number[] {
    return [...this.usedSlots];
  }

  /**
   * Draws a card from a specific slot index (0..9).
   * If slotIndex is not specified or slot is already taken, picks a random available slot.
   * Permanently clears that slot (sets to null) and records it in usedSlots & usedCards.
   */
  public drawSlot(slotIndex?: number | null): { card: number | null; slot: number | null } {
    const available = this.getAvailableSlots();
    if (available.length === 0) {
      this.currentCard = null;
      this.currentSlot = null;
      return { card: null, slot: null };
    }

    let targetSlot: number;
    if (slotIndex !== undefined && slotIndex !== null && this.isSlotAvailable(slotIndex)) {
      targetSlot = slotIndex;
    } else {
      const rIdx = randomInt(0, available.length);
      targetSlot = available[rIdx];
    }

    const drawn = this.slots[targetSlot]!;
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
  public draw(): number | null {
    return this.drawSlot().card;
  }

  public remainingCount(): number {
    return this.getAvailableSlots().length;
  }

  public isExhausted(): boolean {
    return this.remainingCount() === 0;
  }

  public getUsedHistory(): number[] {
    return [...this.usedCards];
  }
}
