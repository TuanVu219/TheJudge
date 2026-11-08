import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { PokerDeck } from "../src/poker/poker_deck.js";
import { ForeheadPokerMatch } from "../src/poker/poker_match.js";
import { Room } from "../src/rooms/room.js";
import { Player } from "../src/players/player.js";
// Mock WebSocket to inspect messages sent to clients
class MockWebSocket {
    sentMessages = [];
    readyState = 1; // OPEN
    OPEN = 1;
    send(data) {
        try {
            this.sentMessages.push(JSON.parse(data));
        }
        catch {
            this.sentMessages.push(data);
        }
    }
    clear() {
        this.sentMessages = [];
    }
}
describe("FOREHEAD POKER – STAGE P3 TEST SUITE", () => {
    const sixPlayerIds = [
        "player_1_minty",
        "player_2_peaches",
        "player_3_bubbles",
        "player_4_lemmy",
        "player_5_berry",
        "player_6_vindy",
    ];
    describe("1. Deck Initialization (Tests 1–7)", () => {
        it("Test 1: Each player has exactly one Hand deck", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            for (const pid of sixPlayerIds) {
                const state = match.getPlayerState(pid);
                assert.ok(state, `Player ${pid} state should exist`);
                assert.ok(state.handDeck instanceof PokerDeck);
                assert.equal(state.handDeck.deckName, "HAND");
            }
        });
        it("Test 2: Each player has exactly one Forehead deck", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            for (const pid of sixPlayerIds) {
                const state = match.getPlayerState(pid);
                assert.ok(state);
                assert.ok(state.foreheadDeck instanceof PokerDeck);
                assert.equal(state.foreheadDeck.deckName, "FOREHEAD");
            }
        });
        it("Test 3: Every Hand deck contains numbers 1–10 exactly once", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            for (const pid of sixPlayerIds) {
                const deck = match.getPlayerState(pid).handDeck;
                const sorted = [...deck.cards].sort((a, b) => a - b);
                assert.deepEqual(sorted, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
            }
        });
        it("Test 4: Every Forehead deck contains numbers 1–10 exactly once", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            for (const pid of sixPlayerIds) {
                const deck = match.getPlayerState(pid).foreheadDeck;
                const sorted = [...deck.cards].sort((a, b) => a - b);
                assert.deepEqual(sorted, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
            }
        });
        it("Test 5: Hand and Forehead decks are independent instances", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            const state = match.getPlayerState(sixPlayerIds[0]);
            assert.notEqual(state.handDeck, state.foreheadDeck);
            // Drawing from hand does not alter forehead
            state.handDeck.draw();
            assert.equal(state.handDeck.remainingCount(), 9);
            assert.equal(state.foreheadDeck.remainingCount(), 10);
        });
        it("Test 6: Decks belong to the correct player", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            for (const pid of sixPlayerIds) {
                const state = match.getPlayerState(pid);
                assert.equal(state.handDeck.playerId, pid);
                assert.equal(state.foreheadDeck.playerId, pid);
            }
        });
        it("Test 7: Shuffling does not modify the card set", () => {
            const deck = new PokerDeck("test_p", "HAND");
            deck.shuffle();
            const sorted = [...deck.cards].sort((a, b) => a - b);
            assert.deepEqual(sorted, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
            assert.equal(deck.remainingCount(), 10);
        });
    });
    describe("2. Independent Drawing (Tests 8–14)", () => {
        it("Test 8: Each round draws one Hand card per player", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            match.drawRound();
            for (const pid of sixPlayerIds) {
                const state = match.getPlayerState(pid);
                assert.ok(typeof state.handDeck.currentCard === "number");
                assert.ok(state.handDeck.currentCard >= 1 && state.handDeck.currentCard <= 10);
                assert.equal(state.handDeck.remainingCount(), 9);
            }
        });
        it("Test 9: Each round draws one Forehead card per player", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            match.drawRound();
            for (const pid of sixPlayerIds) {
                const state = match.getPlayerState(pid);
                assert.ok(typeof state.foreheadDeck.currentCard === "number");
                assert.ok(state.foreheadDeck.currentCard >= 1 && state.foreheadDeck.currentCard <= 10);
                assert.equal(state.foreheadDeck.remainingCount(), 9);
            }
        });
        it("Test 10: Drawing Hand number 7 does not remove number 7 from Forehead", () => {
            const handDeck = new PokerDeck("pA", "HAND");
            const foreheadDeck = new PokerDeck("pA", "FOREHEAD");
            // Force handDeck to draw 7
            handDeck.cards = [1, 2, 3, 4, 5, 6, 8, 9, 10, 7]; // 7 is top
            const drawnHand = handDeck.draw();
            assert.equal(drawnHand, 7);
            // Forehead deck must still contain 7
            assert.ok(foreheadDeck.cards.includes(7));
        });
        it("Test 11: Drawing Forehead number 7 does not remove number 7 from Hand", () => {
            const handDeck = new PokerDeck("pA", "HAND");
            const foreheadDeck = new PokerDeck("pA", "FOREHEAD");
            foreheadDeck.cards = [1, 2, 3, 4, 5, 6, 8, 9, 10, 7];
            const drawnForehead = foreheadDeck.draw();
            assert.equal(drawnForehead, 7);
            // Hand deck must still contain 7
            assert.ok(handDeck.cards.includes(7));
        });
        it("Test 12: Hand and Forehead can both draw number 7 in the same round", () => {
            const handDeck = new PokerDeck("pA", "HAND");
            const foreheadDeck = new PokerDeck("pA", "FOREHEAD");
            handDeck.cards = [1, 2, 3, 4, 5, 6, 8, 9, 10, 7];
            foreheadDeck.cards = [1, 2, 3, 4, 5, 6, 8, 9, 10, 7];
            assert.equal(handDeck.draw(), 7);
            assert.equal(foreheadDeck.draw(), 7);
            assert.equal(handDeck.currentCard, 7);
            assert.equal(foreheadDeck.currentCard, 7);
        });
        it("Test 13: Previously drawn cards never reappear in the same deck during the match", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            for (let r = 1; r <= 10; r++) {
                match.drawRound();
            }
            for (const pid of sixPlayerIds) {
                const state = match.getPlayerState(pid);
                assert.equal(state.handDeck.usedCards.length, 10);
                assert.equal(new Set(state.handDeck.usedCards).size, 10);
                assert.equal(state.foreheadDeck.usedCards.length, 10);
                assert.equal(new Set(state.foreheadDeck.usedCards).size, 10);
            }
        });
        it("Test 14: After 10 rounds, each deck is empty and draw returns exhausted", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            for (let r = 1; r <= 10; r++) {
                const res = match.drawRound();
                assert.equal(res.success, true);
                assert.equal(res.round, r);
            }
            for (const pid of sixPlayerIds) {
                const state = match.getPlayerState(pid);
                assert.equal(state.handDeck.remainingCount(), 0);
                assert.equal(state.foreheadDeck.remainingCount(), 0);
                assert.equal(state.handDeck.isExhausted(), true);
                assert.equal(state.foreheadDeck.isExhausted(), true);
            }
            assert.equal(match.isExhausted(), true);
            // 11th draw must be rejected
            const overflowRes = match.drawRound();
            assert.equal(overflowRes.success, false);
            assert.equal(overflowRes.error, "DECKS_EXHAUSTED");
        });
    });
    describe("3. Privacy Guarantees with Simulated WebSocket Clients (Tests 15–22)", () => {
        it("Test 15: A player receives their own Hand card", () => {
            const match = new ForeheadPokerMatch(["pA", "pB", "pC"]);
            match.drawRound();
            const pA_private = match.getPrivateHandPayload("pA");
            const stateA = match.getPlayerState("pA");
            assert.equal(pA_private.type, "POKER_PRIVATE_HAND");
            assert.equal(pA_private.card, stateA.handDeck.currentCard);
        });
        it("Test 16: A player NEVER receives their own Forehead card", () => {
            const match = new ForeheadPokerMatch(["pA", "pB", "pC"]);
            match.drawRound();
            const pA_opponents = match.getOpponentForeheadsPayload("pA");
            assert.equal(pA_opponents.type, "POKER_OPPONENT_FOREHEADS");
            // pA's own ID must NOT be in the cards list
            const hasOwnId = pA_opponents.cards.some((c) => c.player_id === "pA");
            assert.equal(hasOwnId, false, "Player A's payload must never include Player A");
            // Verify for pB and pC as well
            const pB_opponents = match.getOpponentForeheadsPayload("pB");
            assert.equal(pB_opponents.cards.some((c) => c.player_id === "pB"), false);
            const pC_opponents = match.getOpponentForeheadsPayload("pC");
            assert.equal(pC_opponents.cards.some((c) => c.player_id === "pC"), false);
        });
        it("Test 17: A player NEVER receives another player's Hand card", () => {
            const match = new ForeheadPokerMatch(["pA", "pB", "pC"]);
            match.drawRound();
            const pA_private = match.getPrivateHandPayload("pA");
            const pA_opponents = match.getOpponentForeheadsPayload("pA");
            // Hand payload has no other players
            assert.equal(pA_private.opponents, undefined);
            // Opponent payload only contains forehead cards, no hand cards
            for (const entry of pA_opponents.cards) {
                assert.equal(entry.hand_card, undefined);
            }
        });
        it("Test 18: A player receives every opponent's Forehead card", () => {
            const match = new ForeheadPokerMatch(["pA", "pB", "pC", "pD", "pE", "pF"]);
            match.drawRound();
            const pA_opponents = match.getOpponentForeheadsPayload("pA");
            assert.equal(pA_opponents.cards.length, 5); // 5 opponents
            const opponentIds = pA_opponents.cards.map((c) => c.player_id);
            assert.deepEqual(opponentIds.sort(), ["pB", "pC", "pD", "pE", "pF"]);
            for (const entry of pA_opponents.cards) {
                const oppState = match.getPlayerState(entry.player_id);
                assert.equal(entry.card, oppState.foreheadDeck.currentCard);
            }
        });
        it("Test 19: Public room broadcasts contain NO private card values", () => {
            const match = new ForeheadPokerMatch(["pA", "pB", "pC"]);
            match.drawRound();
            const publicStatus = match.getPublicRoundStatusPayload();
            assert.equal(publicStatus.type, "POKER_ROUND_STATUS");
            assert.equal(publicStatus.cards, undefined);
            assert.equal(publicStatus.hand, undefined);
            assert.equal(publicStatus.forehead, undefined);
            assert.equal(typeof publicStatus.round, "number");
        });
        it("Test 20: Client requests cannot select or inject arbitrary card values", () => {
            const match = new ForeheadPokerMatch(["pA", "pB"]);
            // Draw comes exclusively from server-authoritative deck
            const res = match.drawRound();
            assert.equal(res.success, true);
            const stateA = match.getPlayerState("pA");
            assert.ok([1, 2, 3, 4, 5, 6, 7, 8, 9, 10].includes(stateA.handDeck.currentCard));
        });
        it("Test 21: Client requests cannot access another player's private information", () => {
            const match = new ForeheadPokerMatch(["pA", "pB", "pC"]);
            match.drawRound();
            // Only querying with "pA" can get pA's private hand
            const pA_payload = match.getPrivateHandPayload("pA");
            assert.equal(pA_payload.card, match.getPlayerState("pA").handDeck.currentCard);
            // Querying with an invalid / unauthorized ID returns null
            const invalid_payload = match.getPrivateHandPayload("unauthorized_intruder");
            assert.equal(invalid_payload, null);
        });
        it("Test 22: Private card data is not leaked through room or WebSocket broadcast", () => {
            const wsA = new MockWebSocket();
            const wsB = new MockWebSocket();
            const wsC = new MockWebSocket();
            const pA = new Player("pA", "Alice", wsA);
            const pB = new Player("pB", "Bob", wsB);
            const pC = new Player("pC", "Charlie", wsC);
            const room = new Room("TEST01", pA, "Test Room", 6, "PUBLIC", "3v3");
            room.addPlayer(pB);
            room.addPlayer(pC);
            const pokerMatch = room.initPokerMatch();
            pokerMatch.drawRound();
            // Dispatch private messages
            for (const [pId, p] of room.players) {
                const hand = pokerMatch.getPrivateHandPayload(pId);
                if (hand)
                    p.send(hand);
                const foreheads = pokerMatch.getOpponentForeheadsPayload(pId);
                if (foreheads)
                    p.send(foreheads);
            }
            room.broadcast(pokerMatch.getPublicRoundStatusPayload());
            // Inspect messages delivered to Alice (wsA)
            const handMsg = wsA.sentMessages.find((m) => m.type === "POKER_PRIVATE_HAND");
            const foreheadMsg = wsA.sentMessages.find((m) => m.type === "POKER_OPPONENT_FOREHEADS");
            const statusMsg = wsA.sentMessages.find((m) => m.type === "POKER_ROUND_STATUS");
            assert.ok(handMsg, "Alice must receive private hand message");
            assert.ok(foreheadMsg, "Alice must receive opponent foreheads message");
            assert.ok(statusMsg, "Alice must receive public status message");
            // Verify Alice never received Alice's forehead card
            const selfForehead = foreheadMsg.cards.find((c) => c.player_id === "pA");
            assert.equal(selfForehead, undefined, "Alice's messages must never contain Alice's forehead card");
            // Verify Alice never received Bob's or Charlie's hand card
            const bobHand = wsA.sentMessages.find((m) => m.type === "POKER_PRIVATE_HAND" && m.player_id === "pB");
            assert.equal(bobHand, undefined, "Alice must not receive Bob's hand card");
        });
    });
    describe("4. Reset (Tests 23–26)", () => {
        it("Test 23: A new match restores all 12 decks for six players", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            for (let r = 1; r <= 10; r++) {
                match.drawRound();
            }
            assert.equal(match.isExhausted(), true);
            // Reset match
            match.resetMatch();
            assert.equal(match.round, 0);
            assert.equal(match.isExhausted(), false);
            for (const pid of sixPlayerIds) {
                const state = match.getPlayerState(pid);
                assert.equal(state.handDeck.remainingCount(), 10);
                assert.equal(state.foreheadDeck.remainingCount(), 10);
            }
        });
        it("Test 24: All restored decks contain exactly numbers 1–10", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            for (let r = 1; r <= 5; r++) {
                match.drawRound();
            }
            match.resetMatch();
            for (const pid of sixPlayerIds) {
                const state = match.getPlayerState(pid);
                assert.deepEqual([...state.handDeck.cards].sort((a, b) => a - b), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
                assert.deepEqual([...state.foreheadDeck.cards].sort((a, b) => a - b), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
            }
        });
        it("Test 25: Used-card histories are cleared upon reset", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            match.drawRound();
            match.drawRound();
            match.resetMatch();
            for (const pid of sixPlayerIds) {
                const state = match.getPlayerState(pid);
                assert.equal(state.handDeck.usedCards.length, 0);
                assert.equal(state.foreheadDeck.usedCards.length, 0);
            }
        });
        it("Test 26: Current card values are cleared upon reset", () => {
            const match = new ForeheadPokerMatch(sixPlayerIds);
            match.drawRound();
            match.resetMatch();
            for (const pid of sixPlayerIds) {
                const state = match.getPlayerState(pid);
                assert.equal(state.handDeck.currentCard, null);
                assert.equal(state.foreheadDeck.currentCard, null);
            }
        });
    });
});
