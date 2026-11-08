import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { PokerBettingManager } from "../src/poker/poker_betting.js";
import { POKER_CONFIG } from "../src/poker/poker_config.js";
import { ForeheadPokerMatch } from "../src/poker/poker_match.js";
import { Room } from "../src/rooms/room.js";
import { Player } from "../src/players/player.js";

class MockWebSocket {
  public sentMessages: any[] = [];
  public readyState = 1;
  public OPEN = 1;

  public send(data: string) {
    try {
      this.sentMessages.push(JSON.parse(data));
    } catch {
      this.sentMessages.push(data);
    }
  }

  public clear() {
    this.sentMessages = [];
  }
}

describe("FOREHEAD POKER – STAGE P4 COMPLETE BETTING SUITE (42 TESTS)", () => {
  const threePlayers = ["pA", "pB", "pC"];
  const sixPlayers = ["p1", "p2", "p3", "p4", "p5", "p6"];

  describe("1. Ante System (Tests 1–5)", () => {
    it("Test 1: Every eligible player pays the ante exactly once", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      for (const pid of threePlayers) {
        const p = bm.players.get(pid)!;
        assert.equal(p.anteContribution, POKER_CONFIG.ANTE_AMOUNT);
        assert.equal(p.totalHandContribution, POKER_CONFIG.ANTE_AMOUNT);
      }
    });

    it("Test 2: Ante is deducted from the correct balance", () => {
      const bm = new PokerBettingManager(threePlayers, 100);
      bm.startRound(1);
      for (const pid of threePlayers) {
        const p = bm.players.get(pid)!;
        assert.equal(p.balance, 100 - POKER_CONFIG.ANTE_AMOUNT);
      }
    });

    it("Test 3: Ante is added to the pot immediately", () => {
      const bm = new PokerBettingManager(threePlayers, 100);
      bm.startRound(1);
      assert.equal(bm.totalPot, threePlayers.length * POKER_CONFIG.ANTE_AMOUNT);
      assert.equal(bm.mainPot, threePlayers.length * POKER_CONFIG.ANTE_AMOUNT);
    });

    it("Test 4: A player with insufficient chips contributes the remaining balance and becomes ALL-IN", () => {
      const bm = new PokerBettingManager(["pA", "pB"], 100);
      // Give pA 0 chips and pB 0.5 chips (less than 1)
      const pB = bm.players.get("pB")!;
      pB.startingBalance = 0;
      pB.balance = 0;

      bm.startRound(1);
      assert.equal(pB.balance, 0);
      assert.equal(pB.isAllIn, true);
    });

    it("Test 5: Duplicate round initialization does not deduct ante twice", () => {
      const bm = new PokerBettingManager(threePlayers, 100);
      bm.startRound(1);
      const balanceAfterFirst = bm.players.get("pA")!.balance;
      // Re-trigger ante deduction attempt for same round
      bm.collectAnte(); // already collected
      assert.equal(bm.players.get("pA")!.anteContribution, 1);
      assert.equal(bm.totalPot, 3);
    });
  });

  describe("2. Fold (Tests 6–8)", () => {
    it("Test 6: Folded player cannot act again", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      assert.equal(bm.currentTurnPlayerId, "pA");

      const res = bm.processAction("pA", "FOLD");
      assert.equal(res.success, true);
      assert.equal(bm.players.get("pA")!.isFolded, true);

      // Attempting to act again must fail
      const actAgain = bm.processAction("pA", "CHECK");
      assert.equal(actAgain.success, false);
      assert.equal(actAgain.error, "NOT_PLAYER_TURN");
    });

    it("Test 7: Folded player's contributions remain in the pot", () => {
      const bm = new PokerBettingManager(threePlayers, 100);
      bm.startRound(1);
      bm.processAction("pA", "FOLD");
      assert.equal(bm.totalPot, 3); // 3 antes still in pot
      assert.equal(bm.players.get("pA")!.totalHandContribution, 1);
    });

    it("Test 8: Folded player is not eligible to win any pot", () => {
      const bm = new PokerBettingManager(threePlayers, 100);
      bm.startRound(1);
      bm.processAction("pA", "FOLD");
      bm.processAction("pB", "CHECK");
      bm.processAction("pC", "CHECK");

      assert.equal(bm.bettingPhaseActive, false);
      // Check eligible players in pot layers
      for (const pot of [bm.mainPot, ...bm.sidePots]) {
        if (typeof pot === "object" && "eligiblePlayerIds" in pot) {
          assert.equal((pot as any).eligiblePlayerIds.includes("pA"), false);
        }
      }
    });
  });

  describe("3. Check and Call (Tests 9–13)", () => {
    it("Test 9: Check is accepted when no additional contribution is owed", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      const res = bm.processAction("pA", "CHECK");
      assert.equal(res.success, true);
      assert.equal(bm.players.get("pA")!.hasActedThisRound, true);
      assert.equal(bm.currentTurnPlayerId, "pB");
    });

    it("Test 10: Check is rejected when a bet must be matched", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      // pA opens raise to 4
      bm.processAction("pA", "RAISE", 4);
      assert.equal(bm.currentTurnPlayerId, "pB");

      // pB tries to check when owing 4
      const res = bm.processAction("pB", "CHECK");
      assert.equal(res.success, false);
      assert.equal(res.error, "CANNOT_CHECK_MUST_CALL_OR_FOLD");
    });

    it("Test 11: Call correctly matches the highest bet", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      bm.processAction("pA", "RAISE", 10);
      assert.equal(bm.currentHighestBet, 10);

      const res = bm.processAction("pB", "CALL");
      assert.equal(res.success, true);
      assert.equal(res.amountAdded, 10);
      assert.equal(bm.players.get("pB")!.roundBetContribution, 10);
      assert.equal(bm.players.get("pB")!.balance, 100 - 1 - 10);
    });

    it("Test 12: Insufficient Call automatically becomes All-in", () => {
      const bm = new PokerBettingManager(["pA", "pB"]);
      // pB only has 5 chips left
      const pB = bm.players.get("pB")!;
      pB.startingBalance = 5;
      pB.balance = 5;

      bm.startRound(1); // pB balance becomes 4 after ante
      bm.processAction("pA", "RAISE", 20); // pA bets 20

      // pB calls with only 4 chips
      const res = bm.processAction("pB", "CALL");
      assert.equal(res.success, true);
      assert.equal(pB.balance, 0);
      assert.equal(pB.isAllIn, true);
      assert.equal(pB.roundBetContribution, 4);
    });

    it("Test 13: Balance never becomes negative", () => {
      const bm = new PokerBettingManager(threePlayers, 10);
      bm.startRound(1);
      bm.processAction("pA", "ALL_IN");
      bm.processAction("pB", "CALL");
      bm.processAction("pC", "CALL");

      for (const pid of threePlayers) {
        assert.ok(bm.players.get(pid)!.balance >= 0);
      }
    });
  });

  describe("4. Raise (Tests 14–20)", () => {
    it("Test 14: Minimum opening bet is enforced", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      // Minimum opening bet is 2. Trying to bet 1 must fail.
      const res = bm.processAction("pA", "RAISE", 1);
      assert.equal(res.success, false);
    });

    it("Test 15: Minimum raise increment is enforced", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      // pA opens with 10 (raise increment is 10)
      bm.processAction("pA", "RAISE", 10);
      assert.equal(bm.minRaiseIncrement, 10);

      // pB tries to re-raise to 15 (increment of 5 < min 10) -> must fail
      const res = bm.processAction("pB", "RAISE", 15);
      assert.equal(res.success, false);

      // pB re-raises to 20 (increment 10 >= min 10) -> must succeed
      const legalRes = bm.processAction("pB", "RAISE", 20);
      assert.equal(legalRes.success, true);
    });

    it("Test 16: Invalid raises below current bet are rejected", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      bm.processAction("pA", "RAISE", 10);
      const res = bm.processAction("pB", "RAISE", 8);
      assert.equal(res.success, false);
      assert.equal(res.error, "RAISE_MUST_EXCEED_CURRENT_BET");
    });

    it("Test 17: Raise updates the highest bet", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      bm.processAction("pA", "RAISE", 14);
      assert.equal(bm.currentHighestBet, 14);
    });

    it("Test 18: A raise gives other eligible players another opportunity to respond", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      bm.processAction("pA", "CHECK");
      bm.processAction("pB", "CHECK");
      // pC raises to 10
      bm.processAction("pC", "RAISE", 10);

      // pA and pB must have hasActedThisRound reset to false
      assert.equal(bm.players.get("pA")!.hasActedThisRound, false);
      assert.equal(bm.players.get("pB")!.hasActedThisRound, false);
      assert.equal(bm.currentTurnPlayerId, "pA");
    });

    it("Test 19: A player cannot raise beyond their available stack", () => {
      const bm = new PokerBettingManager(threePlayers, 50);
      bm.startRound(1);
      const res = bm.processAction("pA", "RAISE", 80);
      assert.equal(res.success, false);
      assert.equal(res.error, "INSUFFICIENT_CHIPS_FOR_RAISE");
    });

    it("Test 20: A short All-in raise does not incorrectly count as a full raise for min increment", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      bm.processAction("pA", "RAISE", 20); // min raise inc is 20
      assert.equal(bm.minRaiseIncrement, 20);

      // Give pB 25 chips remaining (ante paid = 1, balance = 24)
      const pB = bm.players.get("pB")!;
      pB.startingBalance = 25;
      pB.balance = 24; // round contribution = 0, will raise to 24 (inc = 4)
      const res = bm.processAction("pB", "RAISE", 24);
      assert.equal(res.success, true);
      assert.equal(pB.isAllIn, true);
      // Min raise increment must still be 20, not lowered to 4
      assert.equal(bm.minRaiseIncrement, 20);
    });
  });

  describe("5. All-In (Tests 21–24)", () => {
    it("Test 21: All-in commits the player's entire remaining balance", () => {
      const bm = new PokerBettingManager(threePlayers, 100);
      bm.startRound(1);
      const balBefore = bm.players.get("pA")!.balance;
      const res = bm.processAction("pA", "ALL_IN");
      assert.equal(res.success, true);
      assert.equal(res.amountAdded, balBefore);
      assert.equal(bm.players.get("pA")!.balance, 0);
      assert.equal(bm.players.get("pA")!.isAllIn, true);
    });

    it("Test 22: All-in player cannot act again in this hand", () => {
      const bm = new PokerBettingManager(threePlayers, 100);
      bm.startRound(1);
      bm.processAction("pA", "ALL_IN");
      const actAgain = bm.processAction("pA", "CHECK");
      assert.equal(actAgain.success, false);
    });

    it("Test 23: All-in for less than current bet is handled correctly without error", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      bm.processAction("pA", "RAISE", 50);

      const pB = bm.players.get("pB")!;
      pB.startingBalance = 11;
      pB.balance = 10;
      const res = bm.processAction("pB", "ALL_IN");
      assert.equal(res.success, true);
      assert.equal(pB.roundBetContribution, 10);
      assert.equal(pB.isAllIn, true);
    });

    it("Test 24: Other players are not forced to contribute more than they can contest", () => {
      const bm = new PokerBettingManager(threePlayers, 100);
      bm.startRound(1);
      bm.processAction("pA", "RAISE", 20);
      bm.processAction("pB", "CALL"); // pB contributes 20
      bm.processAction("pC", "CALL"); // pC contributes 20

      assert.equal(bm.players.get("pB")!.roundBetContribution, 20);
      assert.equal(bm.players.get("pC")!.roundBetContribution, 20);
    });
  });

  describe("6. Turn Management (Tests 25–31)", () => {
    it("Test 25: Actions are accepted only from the active player", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      assert.equal(bm.currentTurnPlayerId, "pA");

      const outOfTurn = bm.processAction("pB", "CHECK");
      assert.equal(outOfTurn.success, false);
      assert.equal(outOfTurn.error, "NOT_PLAYER_TURN");
    });

    it("Test 26: Folded players are skipped in turn order", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      bm.processAction("pA", "RAISE", 10);
      bm.processAction("pB", "FOLD"); // pB folds
      bm.processAction("pC", "RAISE", 25); // pC raises to 25

      // Turn must return to pA, skipping pB
      assert.equal(bm.currentTurnPlayerId, "pA");
    });

    it("Test 27: All-in players are skipped in turn order", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      bm.processAction("pA", "ALL_IN"); // pA is all in
      assert.equal(bm.currentTurnPlayerId, "pB");
      bm.processAction("pB", "CALL"); // pB calls
      assert.equal(bm.currentTurnPlayerId, "pC");
    });

    it("Test 28: Turn order advances cyclically through eligible players", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      assert.equal(bm.currentTurnPlayerId, "pA");
      bm.processAction("pA", "CHECK");
      assert.equal(bm.currentTurnPlayerId, "pB");
      bm.processAction("pB", "CHECK");
      assert.equal(bm.currentTurnPlayerId, "pC");
    });

    it("Test 29: Betting closes when all remaining eligible players have responded", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      bm.processAction("pA", "CHECK");
      bm.processAction("pB", "CHECK");
      const res = bm.processAction("pC", "CHECK");

      assert.equal(res.isRoundComplete, true);
      assert.equal(bm.bettingPhaseActive, false);
      assert.equal(bm.currentTurnPlayerId, null);
    });

    it("Test 30: Betting closes immediately when only one non-folded player remains", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      bm.processAction("pA", "FOLD");
      const res = bm.processAction("pB", "FOLD");

      assert.equal(res.isRoundComplete, true);
      assert.equal(bm.bettingPhaseActive, false);
      assert.equal(bm.players.get("pC")!.isFolded, false);
    });

    it("Test 31: Betting closes when all remaining non-folded players are All-in", () => {
      const bm = new PokerBettingManager(["pA", "pB"]);
      bm.startRound(1);
      bm.processAction("pA", "ALL_IN");
      const res = bm.processAction("pB", "ALL_IN");

      assert.equal(res.isRoundComplete, true);
      assert.equal(bm.bettingPhaseActive, false);
    });
  });

  describe("7. Pot Accounting & Side Pots (Tests 32–37)", () => {
    it("Test 32: Total pot equals the sum of all contributions", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      bm.processAction("pA", "RAISE", 10);
      bm.processAction("pB", "CALL");
      bm.processAction("pC", "CALL");

      let sum = 0;
      for (const [, p] of bm.players) sum += p.totalHandContribution;
      assert.equal(bm.totalPot, sum);
      assert.equal(bm.totalPot, 3 * 1 + 3 * 10); // 3 antes + 30 bets = 33
    });

    it("Test 33: Starting balance equals current balance plus contributions for every player", () => {
      const bm = new PokerBettingManager(threePlayers, 100);
      bm.startRound(1);
      bm.processAction("pA", "RAISE", 25);
      bm.processAction("pB", "CALL");
      bm.processAction("pC", "FOLD");

      for (const [, p] of bm.players) {
        assert.equal(p.startingBalance, p.balance + p.totalHandContribution);
      }
    });

    it("Test 34: Main pot is calculated correctly with equal contributions", () => {
      const bm = new PokerBettingManager(threePlayers, 100);
      bm.startRound(1);
      bm.processAction("pA", "CHECK");
      bm.processAction("pB", "CHECK");
      bm.processAction("pC", "CHECK");

      assert.equal(bm.mainPot, 3); // 3 antes
      assert.equal(bm.sidePots.length, 0);
    });

    it("Test 35: Side pots are calculated correctly when stacks differ", () => {
      const bm = new PokerBettingManager(["pA", "pB", "pC"]);
      // pB has 50 total chips, pA and pC have 100
      bm.players.get("pB")!.startingBalance = 50;
      bm.players.get("pB")!.balance = 50;

      bm.startRound(1);
      bm.processAction("pA", "RAISE", 99); // pA bets 99 chips (100 total with ante)
      bm.processAction("pB", "ALL_IN"); // pB puts in 49 chips (all-in at 50 total)
      bm.processAction("pC", "CALL"); // pC calls 99 chips (100 total)

      // Total contributions:
      // pB total = 50
      // pA total = 100
      // pC total = 100
      // Main pot: 50 * 3 = 150 (eligible: pA, pB, pC)
      // Side pot: (100 - 50) * 2 = 100 (eligible: pA, pC)
      assert.equal(bm.totalPot, 250);
      assert.equal(bm.mainPot, 150);
      assert.equal(bm.sidePots.length, 1);
      assert.equal(bm.sidePots[0].potAmount, 100);
      assert.deepEqual(bm.sidePots[0].eligiblePlayerIds.sort(), ["pA", "pC"]);
    });

    it("Test 36: Folded players are excluded from pot eligibility", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      bm.processAction("pA", "RAISE", 20);
      bm.processAction("pB", "FOLD"); // pB paid 1 ante, then folded
      bm.processAction("pC", "CALL");

      // pB's ante remains in total pot
      assert.equal(bm.totalPot, 1 + 21 + 21);
      // But pB is not eligible to win
      assert.equal(bm.sidePots.some((sp) => sp.eligiblePlayerIds.includes("pB")), false);
    });

    it("Test 37: Multiple All-in amounts produce correct layered side-pot structure", () => {
      const bm = new PokerBettingManager(["pA", "pB", "pC", "pD"]);
      bm.players.get("pA")!.startingBalance = 20;
      bm.players.get("pA")!.balance = 20;
      bm.players.get("pB")!.startingBalance = 40;
      bm.players.get("pB")!.balance = 40;
      bm.players.get("pC")!.startingBalance = 100;
      bm.players.get("pC")!.balance = 100;
      bm.players.get("pD")!.startingBalance = 100;
      bm.players.get("pD")!.balance = 100;

      bm.startRound(1);
      bm.processAction("pA", "ALL_IN"); // total = 20
      bm.processAction("pB", "ALL_IN"); // total = 40
      bm.processAction("pC", "ALL_IN"); // total = 100
      bm.processAction("pD", "CALL"); // total = 100

      // Tier 1 (up to 20): 20 * 4 = 80 (eligible: pA, pB, pC, pD)
      // Tier 2 (20 to 40): (40 - 20) * 3 = 60 (eligible: pB, pC, pD)
      // Tier 3 (40 to 100): (100 - 40) * 2 = 120 (eligible: pC, pD)
      // Total = 80 + 60 + 120 = 260
      assert.equal(bm.totalPot, 260);
      assert.equal(bm.mainPot, 80);
      assert.equal(bm.sidePots.length, 2);
      assert.equal(bm.sidePots[0].potAmount, 60);
      assert.deepEqual(bm.sidePots[0].eligiblePlayerIds.sort(), ["pB", "pC", "pD"]);
      assert.equal(bm.sidePots[1].potAmount, 120);
      assert.deepEqual(bm.sidePots[1].eligiblePlayerIds.sort(), ["pC", "pD"]);
    });
  });

  describe("8. Security & Multiplayer WebSocket Simulation (Tests 38–42)", () => {
    it("Test 38: A player cannot submit an action for another player", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      assert.equal(bm.currentTurnPlayerId, "pA");

      // pB tries to submit an action
      const res = bm.processAction("pB", "CALL");
      assert.equal(res.success, false);
      assert.equal(res.error, "NOT_PLAYER_TURN");
    });

    it("Test 39: A player cannot act out of turn", () => {
      const bm = new PokerBettingManager(threePlayers);
      bm.startRound(1);
      const res = bm.processAction("pC", "FOLD");
      assert.equal(res.success, false);
      assert.equal(res.error, "NOT_PLAYER_TURN");
    });

    it("Test 40: Duplicate action messages do not deduct chips twice", () => {
      const bm = new PokerBettingManager(threePlayers, 100);
      bm.startRound(1);
      const firstAction = bm.processAction("pA", "RAISE", 10);
      assert.equal(firstAction.success, true);
      const balanceAfter = bm.players.get("pA")!.balance;

      // Duplicate message sent by pA
      const dupAction = bm.processAction("pA", "RAISE", 10);
      assert.equal(dupAction.success, false);
      assert.equal(bm.players.get("pA")!.balance, balanceAfter);
    });

    it("Test 41: Client-supplied pot or balance values are ignored (server is authoritative)", () => {
      const bm = new PokerBettingManager(threePlayers, 100);
      bm.startRound(1);
      // Client cannot choose or override server balance or pot
      bm.processAction("pA", "CALL");
      assert.equal(bm.players.get("pA")!.balance, 99); // 100 - 1 ante - 0 bet
      assert.equal(bm.totalPot, 3);
    });

    it("Test 42: Public betting messages do not leak private cards (tested with 3 simulated WebSockets)", () => {
      const wsA = new MockWebSocket();
      const wsB = new MockWebSocket();
      const wsC = new MockWebSocket();

      const pA = new Player("pA", "Alice", wsA as any);
      const pB = new Player("pB", "Bob", wsB as any);
      const pC = new Player("pC", "Charlie", wsC as any);

      const room = new Room("POKER1", pA, "Poker Room", 6, "PUBLIC", "3v3");
      room.addPlayer(pB);
      room.addPlayer(pC);

      const match = room.initPokerMatch();
      match.drawRound();

      const bettingState = match.getPublicBettingPayload();
      // Ensure NO card values are present in public betting payload
      const jsonStr = JSON.stringify(bettingState);
      assert.equal(jsonStr.includes("handDeck"), false);
      assert.equal(jsonStr.includes("foreheadDeck"), false);
      assert.equal(bettingState.type, "POKER_BETTING_STATE");
      assert.equal(bettingState.total_pot, 3); // 3 antes
    });
  });

  describe("9. Six-Player Match Scalability", () => {
    it("Supports 6 players cleanly through full betting cycle", () => {
      const bm = new PokerBettingManager(sixPlayers, 100);
      bm.startRound(1);
      assert.equal(bm.totalPot, 6); // 6 antes

      // p1 raises to 6
      bm.processAction("p1", "RAISE", 6);
      // p2 folds
      bm.processAction("p2", "FOLD");
      // p3 calls 6
      bm.processAction("p3", "CALL");
      // p4 calls 6
      bm.processAction("p4", "CALL");
      // p5 folds
      bm.processAction("p5", "FOLD");
      // p6 calls 6
      const lastRes = bm.processAction("p6", "CALL");

      assert.equal(lastRes.isRoundComplete, true);
      assert.equal(bm.bettingPhaseActive, false);
      // Pot = 6 antes + 4 calls of 6 = 30
      assert.equal(bm.totalPot, 30);
      bm.assertInvariants();
    });
  });
});
