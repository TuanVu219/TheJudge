import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { ForeheadPokerMatch } from "../src/poker/poker_match.js";
import { PokerBettingManager } from "../src/poker/poker_betting.js";
import { PokerShowdownManager, type RoundResult } from "../src/poker/poker_showdown.js";
import { Room } from "../src/rooms/room.js";
import { Player } from "../src/players/player.js";

class MockWebSocket {
  public sentMessages: any[] = [];
  public readyState: number = 1; // WebSocket.OPEN
  public OPEN: number = 1;

  public send(data: string): void {
    try {
      this.sentMessages.push(JSON.parse(data));
    } catch {
      this.sentMessages.push(data);
    }
  }

  public clear(): void {
    this.sentMessages = [];
  }
}

describe("FOREHEAD POKER – STAGE P6: SHOWDOWN, WINNER DETERMINATION & POT DISTRIBUTION", () => {
  // ── 1. WINNER DETERMINATION ──────────────────────────────────────────────
  describe("1. Winner Determination", () => {
    it("Test 1: One clear winner with the highest total score (Hand + Forehead)", () => {
      const match = new ForeheadPokerMatch(["pA", "pB", "pC"]);
      match.drawRound();

      // Setup specific card values
      // pA: Hand 8, Forehead 7 -> Total 15
      // pB: Hand 5, Forehead 6 -> Total 11
      // pC: Hand 3, Forehead 4 -> Total 7
      match.getPlayerState("pA")!.handDeck.currentCard = 8;
      match.getPlayerState("pA")!.foreheadDeck.currentCard = 7;

      match.getPlayerState("pB")!.handDeck.currentCard = 5;
      match.getPlayerState("pB")!.foreheadDeck.currentCard = 6;

      match.getPlayerState("pC")!.handDeck.currentCard = 3;
      match.getPlayerState("pC")!.foreheadDeck.currentCard = 4;

      const result = match.resolveShowdown();

      assert.equal(result.resultType, "SHOWDOWN");
      assert.deepEqual(result.winnerPlayerIds, ["pA"]);
      assert.equal(result.playerScores["pA"], 15);
      assert.equal(result.playerScores["pB"], 11);
      assert.equal(result.playerScores["pC"], 7);
      assert.equal(result.tiedWinnerIds.length, 0);
    });

    it("Test 2: Two tied winners with identical total scores share the pot", () => {
      const match = new ForeheadPokerMatch(["pA", "pB", "pC"]);
      match.drawRound();

      // pA: 8 + 7 = 15
      // pB: 6 + 9 = 15 (tied with pA!)
      // pC: 4 + 8 = 12
      match.getPlayerState("pA")!.handDeck.currentCard = 8;
      match.getPlayerState("pA")!.foreheadDeck.currentCard = 7;

      match.getPlayerState("pB")!.handDeck.currentCard = 6;
      match.getPlayerState("pB")!.foreheadDeck.currentCard = 9;

      match.getPlayerState("pC")!.handDeck.currentCard = 4;
      match.getPlayerState("pC")!.foreheadDeck.currentCard = 8;

      const result = match.resolveShowdown();

      assert.equal(result.resultType, "SHOWDOWN");
      assert.equal(result.playerScores["pA"], 15);
      assert.equal(result.playerScores["pB"], 15);
      assert.equal(result.tiedWinnerIds.length, 2);
      assert.ok(result.tiedWinnerIds.includes("pA"));
      assert.ok(result.tiedWinnerIds.includes("pB"));
      assert.deepEqual(result.mainPotDistribution.winningPlayerIds.sort(), ["pA", "pB"]);
    });

    it("Test 3: Three tied winners share the pot equally", () => {
      const match = new ForeheadPokerMatch(["pA", "pB", "pC"]);
      match.drawRound();

      // All score 14
      match.getPlayerState("pA")!.handDeck.currentCard = 7;
      match.getPlayerState("pA")!.foreheadDeck.currentCard = 7; // 14
      match.getPlayerState("pB")!.handDeck.currentCard = 10;
      match.getPlayerState("pB")!.foreheadDeck.currentCard = 4; // 14
      match.getPlayerState("pC")!.handDeck.currentCard = 5;
      match.getPlayerState("pC")!.foreheadDeck.currentCard = 9; // 14

      const result = match.resolveShowdown();

      assert.equal(result.resultType, "SHOWDOWN");
      assert.equal(result.tiedWinnerIds.length, 3);
      assert.equal(result.mainPotDistribution.winningPlayerIds.length, 3);
    });

    it("Test 4: Folded player with highest score is strictly excluded from winning", () => {
      const match = new ForeheadPokerMatch(["pA", "pB", "pC"]);
      match.drawRound();

      // pA has highest card 10 + 10 = 20, BUT pA FOLDED
      match.getPlayerState("pA")!.handDeck.currentCard = 10;
      match.getPlayerState("pA")!.foreheadDeck.currentCard = 10;
      match.bettingManager.players.get("pA")!.isFolded = true;

      // pB: 4 + 4 = 8
      match.getPlayerState("pB")!.handDeck.currentCard = 4;
      match.getPlayerState("pB")!.foreheadDeck.currentCard = 4;

      // pC: 2 + 3 = 5
      match.getPlayerState("pC")!.handDeck.currentCard = 2;
      match.getPlayerState("pC")!.foreheadDeck.currentCard = 3;

      const result = match.resolveShowdown();

      assert.equal(result.resultType, "SHOWDOWN");
      assert.deepEqual(result.winnerPlayerIds, ["pB"]);
      assert.equal(result.revealedCards["pA"], undefined, "Folded player cards must not be in revealedCards at showdown");
      assert.equal(result.playerScores["pA"], undefined, "Folded player must not have an eligible score");
    });

    it("Test 5: Uncontested win when everyone else folds (cards remain private)", () => {
      const match = new ForeheadPokerMatch(["pA", "pB", "pC"]);
      match.drawRound();

      // pB and pC fold
      match.bettingManager.players.get("pB")!.isFolded = true;
      match.bettingManager.players.get("pC")!.isFolded = true;

      const result = match.resolveShowdown();

      assert.equal(result.resultType, "UNCONTESTED");
      assert.deepEqual(result.winnerPlayerIds, ["pA"]);
      // Winner's cards remain private!
      assert.equal(Object.keys(result.revealedCards).length, 0, "Uncontested winner does not reveal cards");
      assert.equal(result.totalAwardedByPlayer["pA"], 3); // 3 antes collected
    });

    it("Test 6: Multiple players with varying scores rank correctly", () => {
      const match = new ForeheadPokerMatch(["p1", "p2", "p3", "p4", "p5", "p6"]);
      match.drawRound();

      const scores = [8, 12, 19, 14, 16, 11];
      for (let i = 0; i < 6; i++) {
        const pid = `p${i + 1}`;
        match.getPlayerState(pid)!.handDeck.currentCard = Math.floor(scores[i] / 2);
        match.getPlayerState(pid)!.foreheadDeck.currentCard = scores[i] - Math.floor(scores[i] / 2);
      }

      const result = match.resolveShowdown();
      assert.deepEqual(result.winnerPlayerIds, ["p3"]);
      assert.equal(result.playerScores["p3"], 19);
    });
  });

  // ── 2. POT DISTRIBUTION & INVARIANTS ──────────────────────────────────────
  describe("2. Main Pot and Side Pot Distribution", () => {
    it("Test 7: Main Pot is distributed in full to the sole winner", () => {
      const bm = new PokerBettingManager(["pA", "pB"]);
      bm.startRound(1); // 1 ante each -> pot = 2
      bm.processAction("pA", "CALL", 0);
      bm.processAction("pB", "CHECK", 0);

      const players = new Map();
      players.set("pA", { handDeck: { currentCard: 9 }, foreheadDeck: { currentCard: 8 } });
      players.set("pB", { handDeck: { currentCard: 5 }, foreheadDeck: { currentCard: 4 } });

      const seatMap = new Map([["pA", 0], ["pB", 1]]);
      const res = PokerShowdownManager.resolveRoundResult(1, bm, players as any, seatMap, 1);

      assert.equal(res.finalPot, 2);
      assert.equal(res.totalAwardedByPlayer["pA"], 2);
      assert.equal(res.totalAwardedByPlayer["pB"], 0);
      assert.equal(res.updatedBalances["pA"], 101); // 100 - 1 + 2 = 101
      assert.equal(res.updatedBalances["pB"], 99);  // 100 - 1 = 99
    });

    it("Test 8: Layered Side Pot when one player goes All-In with less chips", () => {
      const bm = new PokerBettingManager(["pA", "pB", "pC"]);
      // Setup stacks: pA has 20 chips, pB has 100, pC has 100
      bm.players.get("pA")!.balance = 20;
      bm.players.get("pA")!.startingBalance = 20;

      bm.startRound(1); // ante 1 each -> pA balance: 19, pB: 99, pC: 99. Pot: 3

      // pA goes All-In for remaining 19 chips (total contrib: 20)
      bm.processAction("pA", "ALL_IN");
      // pB raises to 50 (contrib: 50)
      bm.processAction("pB", "RAISE", 50);
      // pC calls 50 (contrib: 50)
      bm.processAction("pC", "CALL");

      // Total pot = 20 + 51 + 51 = 122
      // Main Pot = 20 * 3 = 60 (eligible: pA, pB, pC)
      // Side Pot 1 = (51 - 20) * 2 = 62 (eligible: pB, pC)
      bm.calculatePots();
      assert.equal(bm.mainPot, 60);
      assert.equal(bm.sidePots.length, 1);
      assert.equal(bm.sidePots[0].potAmount, 62);

      // Card scores:
      // pA has the BEST score: 10 + 10 = 20
      // pB has second best: 7 + 7 = 14
      // pC has worst: 2 + 2 = 4
      const players = new Map();
      players.set("pA", { handDeck: { currentCard: 10 }, foreheadDeck: { currentCard: 10 } });
      players.set("pB", { handDeck: { currentCard: 7 }, foreheadDeck: { currentCard: 7 } });
      players.set("pC", { handDeck: { currentCard: 2 }, foreheadDeck: { currentCard: 2 } });

      const seatMap = new Map([["pA", 0], ["pB", 1], ["pC", 2]]);
      const res = PokerShowdownManager.resolveRoundResult(1, bm, players as any, seatMap, 1);

      // pA wins the Main Pot (60)
      assert.equal(res.mainPotDistribution.payouts["pA"], 60);
      // pA CANNOT win the Side Pot even with highest score! pB wins Side Pot (62)
      assert.equal(res.sidePotDistributions[0].payouts["pB"], 62);
      assert.equal(res.sidePotDistributions[0].payouts["pA"], undefined);

      assert.equal(res.totalAwardedByPlayer["pA"], 60);
      assert.equal(res.totalAwardedByPlayer["pB"], 62);
      assert.equal(res.totalAwardedByPlayer["pC"], 0);

      // Chip Conservation: total before (20 + 100 + 100 = 220) === total after (60 + 111 + 49 = 220)
      const totalChipsAfter = res.updatedBalances["pA"] + res.updatedBalances["pB"] + res.updatedBalances["pC"];
      assert.equal(totalChipsAfter, 220);
    });

    it("Test 9: Folded contribution stays in pot and is awarded to showdown winner", () => {
      const bm = new PokerBettingManager(["pA", "pB", "pC"]);
      bm.startRound(1); // 1 ante each

      bm.processAction("pA", "RAISE", 10);
      bm.processAction("pB", "FOLD"); // pB forfeits ante (1)
      bm.processAction("pC", "CALL"); // pC calls 10

      // Pot = 11 + 1 + 11 = 23
      const players = new Map();
      players.set("pA", { handDeck: { currentCard: 8 }, foreheadDeck: { currentCard: 7 } }); // 15
      players.set("pB", { handDeck: { currentCard: 10 }, foreheadDeck: { currentCard: 10 } }); // Folded
      players.set("pC", { handDeck: { currentCard: 3 }, foreheadDeck: { currentCard: 4 } }); // 7

      const seatMap = new Map([["pA", 0], ["pB", 1], ["pC", 2]]);
      const res = PokerShowdownManager.resolveRoundResult(1, bm, players as any, seatMap, 1);

      assert.equal(res.finalPot, 23);
      assert.equal(res.totalAwardedByPlayer["pA"], 23);
      assert.equal(res.totalAwardedByPlayer["pB"], 0);
      assert.equal(res.totalAwardedByPlayer["pC"], 0);
      // Chip conservation: 100 * 3 = 300
      const totalChips = res.updatedBalances["pA"] + res.updatedBalances["pB"] + res.updatedBalances["pC"];
      assert.equal(totalChips, 300);
    });

    it("Test 10: Equal split among tied winners with even division", () => {
      const bm = new PokerBettingManager(["pA", "pB"]);
      bm.startRound(1);
      bm.processAction("pA", "RAISE", 10);
      bm.processAction("pB", "CALL"); // Pot = 22 (2 antes + 20 bets)

      const players = new Map();
      players.set("pA", { handDeck: { currentCard: 6 }, foreheadDeck: { currentCard: 6 } }); // 12
      players.set("pB", { handDeck: { currentCard: 8 }, foreheadDeck: { currentCard: 4 } }); // 12

      const seatMap = new Map([["pA", 0], ["pB", 1]]);
      const res = PokerShowdownManager.resolveRoundResult(1, bm, players as any, seatMap, 1);

      assert.equal(res.mainPotDistribution.payouts["pA"], 11);
      assert.equal(res.mainPotDistribution.payouts["pB"], 11);
      assert.equal(res.updatedBalances["pA"], 100);
      assert.equal(res.updatedBalances["pB"], 100);
    });

    it("Test 11: Odd-chip remainder distributed deterministically by seat order", () => {
      const bm = new PokerBettingManager(["pA", "pB", "pC"]);
      bm.startRound(1); // 1 ante each -> pot = 3
      bm.processAction("pA", "CHECK");
      bm.processAction("pB", "CHECK");
      bm.processAction("pC", "FOLD"); // pC folds, pot remains 3

      // Tie between pA (Seat 0) and pB (Seat 1)
      const players = new Map();
      players.set("pA", { handDeck: { currentCard: 5 }, foreheadDeck: { currentCard: 5 } });
      players.set("pB", { handDeck: { currentCard: 5 }, foreheadDeck: { currentCard: 5 } });
      players.set("pC", { handDeck: { currentCard: 1 }, foreheadDeck: { currentCard: 1 } });

      const seatMap = new Map([["pA", 0], ["pB", 1], ["pC", 2]]);
      const res = PokerShowdownManager.resolveRoundResult(1, bm, players as any, seatMap, 1);

      // 3 / 2 = 1 remainder 1. Seat 0 (pA) gets 1 + 1 = 2. Seat 1 (pB) gets 1.
      assert.equal(res.mainPotDistribution.payouts["pA"], 2);
      assert.equal(res.mainPotDistribution.payouts["pB"], 1);
      assert.equal(res.updatedBalances["pA"], 101);
      assert.equal(res.updatedBalances["pB"], 100);
      assert.equal(res.updatedBalances["pC"], 99);
      // Total chips strictly conserved: 101 + 100 + 99 = 300
      assert.equal(res.updatedBalances["pA"] + res.updatedBalances["pB"] + res.updatedBalances["pC"], 300);
    });

    it("Test 12: Invariant: Sum of payouts equals total pot and chips are never created or destroyed", () => {
      const bm = new PokerBettingManager(["p1", "p2", "p3", "p4", "p5", "p6"]);
      bm.startRound(1);
      // Various bets
      bm.processAction("p1", "RAISE", 15);
      bm.processAction("p2", "CALL");
      bm.processAction("p3", "FOLD");
      bm.processAction("p4", "CALL");
      bm.processAction("p5", "FOLD");
      bm.processAction("p6", "CALL");

      const potBefore = bm.totalPot;
      const initialChips = 600;

      const players = new Map();
      for (let i = 1; i <= 6; i++) {
        players.set(`p${i}`, { handDeck: { currentCard: i }, foreheadDeck: { currentCard: i } });
      }

      const seatMap = new Map([["p1", 0], ["p2", 1], ["p3", 2], ["p4", 3], ["p5", 4], ["p6", 5]]);
      const res = PokerShowdownManager.resolveRoundResult(1, bm, players as any, seatMap, 1);

      let totalAwarded = 0;
      for (const amt of Object.values(res.totalAwardedByPlayer)) {
        totalAwarded += amt;
      }
      assert.equal(totalAwarded, potBefore, "Sum of payouts must equal total pot");

      let totalEndChips = 0;
      for (const bal of Object.values(res.updatedBalances)) {
        totalEndChips += bal;
      }
      assert.equal(totalEndChips, initialChips, "Total chips before must equal total chips after");
    });
  });

  // ── 3. DECK LIFECYCLE & 10-ROUND COMPLETION ──────────────────────────────
  describe("3. Deck Lifecycle & 10-Round Match Completion", () => {
    it("Test 13: 10 successive rounds exhaust both decks without reshuffling", () => {
      const match = new ForeheadPokerMatch(["pA", "pB"]);
      const usedHandsA = new Set<number>();
      const usedForeheadsA = new Set<number>();

      for (let r = 1; r <= 10; r++) {
        const drawRes = match.drawRound();
        assert.equal(drawRes.success, true);
        assert.equal(match.round, r);

        const handCard = match.getPlayerState("pA")!.handDeck.currentCard!;
        const foreheadCard = match.getPlayerState("pA")!.foreheadDeck.currentCard!;

        assert.ok(!usedHandsA.has(handCard), `Card ${handCard} must not repeat in Hand deck`);
        assert.ok(!usedForeheadsA.has(foreheadCard), `Card ${foreheadCard} must not repeat in Forehead deck`);

        usedHandsA.add(handCard);
        usedForeheadsA.add(foreheadCard);

        const roundRes = match.resolveShowdown();
        if (r < 10) {
          assert.equal(roundRes.isMatchCompleted, false);
        } else {
          assert.equal(roundRes.isMatchCompleted, true);
        }
      }

      assert.equal(usedHandsA.size, 10, "Hand deck must have consumed all 10 distinct cards");
      assert.equal(usedForeheadsA.size, 10, "Forehead deck must have consumed all 10 distinct cards");
      assert.equal(match.isExhausted(), true);

      // Round 11 attempt must fail
      const overflowRes = match.drawRound();
      assert.equal(overflowRes.success, false);
      assert.equal(overflowRes.error, "DECKS_EXHAUSTED");
    });

    it("Test 14: Overall winners and match completion report", () => {
      const match = new ForeheadPokerMatch(["pA", "pB"]);
      match.drawRound();
      // pA wins round
      match.getPlayerState("pA")!.handDeck.currentCard = 10;
      match.getPlayerState("pA")!.foreheadDeck.currentCard = 10;
      match.getPlayerState("pB")!.handDeck.currentCard = 2;
      match.getPlayerState("pB")!.foreheadDeck.currentCard = 2;
      match.resolveShowdown();

      const overall = match.getOverallWinners();
      assert.deepEqual(overall.winners, ["pA"]);
      assert.equal(overall.finalBalances["pA"], 101);
      assert.equal(overall.finalBalances["pB"], 99);
      assert.equal(overall.chipsWon["pA"], 1);
      assert.equal(overall.chipsWon["pB"], -1);
    });

    it("Test 15: Match Reset clears round history and restores full decks and chips", () => {
      const match = new ForeheadPokerMatch(["pA", "pB"]);
      match.drawRound();
      match.resolveShowdown();
      assert.equal(match.matchHistory.length, 1);

      match.resetMatch();
      assert.equal(match.round, 0);
      assert.equal(match.matchHistory.length, 0);
      assert.equal(match.lastRoundResult, null);
      assert.equal(match.getPlayerState("pA")!.handDeck.remainingCount(), 10);
      assert.equal(match.getPlayerState("pA")!.foreheadDeck.remainingCount(), 10);
      assert.equal(match.bettingManager.players.get("pA")!.balance, 100);
      assert.equal(match.bettingManager.players.get("pB")!.balance, 100);
    });
  });

  // ── 4. MULTIPLAYER WEBSOCKET SYNCHRONIZATION ─────────────────────────────
  describe("4. Multiplayer WebSocket Showdown Synchronization", () => {
    it("Test 16: Room broadcasts POKER_ROUND_RESULT with authoritative payload to all clients", () => {
      const wsA = new MockWebSocket();
      const wsB = new MockWebSocket();
      const pA = new Player("pA", "Alice", wsA as any);
      const pB = new Player("pB", "Bob", wsB as any);

      const room = new Room("SHOW01", pA, "Showdown Room", 6, "PUBLIC", "FOREHEAD_POKER");
      room.addPlayer(pB);
      pA.isReady = true;
      pB.isReady = true;

      room.startMatch("pA");
      wsA.clear();
      wsB.clear();

      // Resolve showdown
      const result = room.resolvePokerShowdown()!;
      assert.ok(result);

      const msgA = wsA.sentMessages.find((m) => m.type === "POKER_ROUND_RESULT");
      const msgB = wsB.sentMessages.find((m) => m.type === "POKER_ROUND_RESULT");

      assert.ok(msgA, "Player A must receive POKER_ROUND_RESULT");
      assert.ok(msgB, "Player B must receive POKER_ROUND_RESULT");
      assert.deepEqual(msgA.round_result, msgB.round_result, "All clients must receive the identical authoritative result");
      assert.equal(msgA.round, 1);
    });

    it("Test 17: POKER_MATCH_COMPLETED broadcast upon round 10 completion", () => {
      const wsA = new MockWebSocket();
      const pA = new Player("pA", "Host", wsA as any);
      const room = new Room("SHOW02", pA, "Room", 2, "PUBLIC", "FOREHEAD_POKER");
      const wsB = new MockWebSocket();
      const pB = new Player("pB", "Guest", wsB as any);
      room.addPlayer(pB);

      pA.isReady = true;
      pB.isReady = true;
      room.startMatch("pA");

      // Advance match to round 10
      room.pokerMatch!.round = 10;
      wsA.clear();

      room.resolvePokerShowdown();

      const completeMsg = wsA.sentMessages.find((m) => m.type === "POKER_MATCH_COMPLETED");
      assert.ok(completeMsg, "Must broadcast POKER_MATCH_COMPLETED when round 10 finishes");
      assert.ok(Array.isArray(completeMsg.overall_winners));
      assert.ok(typeof completeMsg.final_balances === "object");
    });
  });
});
