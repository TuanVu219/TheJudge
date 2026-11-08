import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { ServerRoomManager } from "../src/rooms/room_manager.js";
import { Room } from "../src/rooms/room.js";
import { Player } from "../src/players/player.js";
import { WebSocketHandler } from "../src/websocket/handler.js";
class MockWebSocket {
    sentMessages = [];
    readyState = 1;
    OPEN = 1;
    listeners = {};
    on(event, callback) {
        if (!this.listeners[event])
            this.listeners[event] = [];
        this.listeners[event].push(callback);
    }
    emit(event, ...args) {
        if (this.listeners[event]) {
            for (const cb of this.listeners[event]) {
                cb(...args);
            }
        }
    }
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
describe("FOREHEAD POKER – STAGE P5 MULTIPLAYER SYNCHRONIZATION SUITE", () => {
    describe("A. Room Management (Tests 1–7)", () => {
        it("Test 1: Create Forehead Poker room with correct defaults", () => {
            const roomMgr = new ServerRoomManager();
            const wsHost = new MockWebSocket();
            const host = new Player("host_1", "HostMinty", wsHost);
            const res = roomMgr.createRoom(host, "Saloon Room", 6, "PUBLIC", "FOREHEAD_POKER", "SALOON");
            assert.equal(res.success, true);
            assert.ok(res.room);
            assert.equal(res.room.gameMode, "FOREHEAD_POKER");
            assert.equal(res.room.maxPlayers, 6);
            assert.equal(res.room.status, "WAITING");
            assert.equal(res.room.hostPlayerId, "host_1");
            assert.equal(host.seatIndex, 0); // Host gets seat 0
        });
        it("Test 2: Join room using valid room code and receive unique seat assignment", () => {
            const roomMgr = new ServerRoomManager();
            const wsHost = new MockWebSocket();
            const host = new Player("host_1", "HostMinty", wsHost);
            const createRes = roomMgr.createRoom(host, "Saloon Room", 6, "PUBLIC", "FOREHEAD_POKER");
            const room = createRes.room;
            const wsGuest = new MockWebSocket();
            const guest = new Player("guest_2", "GuestPeaches", wsGuest);
            const joinRes = room.addPlayer(guest);
            assert.equal(joinRes.success, true);
            assert.equal(guest.currentRoomCode, room.roomCode);
            assert.equal(room.players.size, 2);
            assert.equal(guest.seatIndex, 1); // Second player gets seat 1
        });
        it("Test 3: Reject invalid room code", () => {
            const roomMgr = new ServerRoomManager();
            const room = roomMgr.findRoomByCode("NONEXIST");
            assert.equal(room, null);
        });
        it("Test 4: Reject full room (>6 players)", () => {
            const roomMgr = new ServerRoomManager();
            const wsHost = new MockWebSocket();
            const host = new Player("p0", "Host", wsHost);
            const createRes = roomMgr.createRoom(host, "Saloon Room", 6, "PUBLIC", "FOREHEAD_POKER", "SALOON");
            const room = createRes.room;
            for (let i = 1; i <= 5; i++) {
                const ws = new MockWebSocket();
                const p = new Player(`p${i}`, `Player${i}`, ws);
                const res = room.addPlayer(p);
                assert.equal(res.success, true);
            }
            assert.equal(room.players.size, 6);
            // 7th player must be rejected
            const wsExtra = new MockWebSocket();
            const extra = new Player("p7", "Extra", wsExtra);
            const rejectRes = room.addPlayer(extra);
            assert.equal(rejectRes.success, false);
            assert.equal(rejectRes.error_code, "ROOM_FULL");
        });
        it("Test 5: Prevent duplicate player entries", () => {
            const roomMgr = new ServerRoomManager();
            const wsHost = new MockWebSocket();
            const host = new Player("p0", "Host", wsHost);
            const createRes = roomMgr.createRoom(host, "Saloon Room", 6, "PUBLIC", "FOREHEAD_POKER", "SALOON");
            const room = createRes.room;
            // Attempt to add host again
            const dupRes = room.addPlayer(host);
            assert.equal(dupRes.success, false);
            assert.equal(dupRes.error_code, "DUPLICATE_PLAYER");
        });
        it("Test 6: Reject joining after match has started", () => {
            const roomMgr = new ServerRoomManager();
            const wsHost = new MockWebSocket();
            const host = new Player("p0", "Host", wsHost);
            const createRes = roomMgr.createRoom(host, "Saloon Room", 6, "PUBLIC", "FOREHEAD_POKER", "SALOON");
            const room = createRes.room;
            const wsGuest = new MockWebSocket();
            const guest = new Player("p1", "Guest", wsGuest);
            room.addPlayer(guest);
            host.isReady = true;
            guest.isReady = true;
            const startRes = room.startMatch("p0");
            assert.equal(startRes.success, true);
            assert.equal(room.status, "STARTED");
            // Attempt to join after start
            const wsLate = new MockWebSocket();
            const latePlayer = new Player("pLate", "Late", wsLate);
            const joinLate = room.addPlayer(latePlayer);
            assert.equal(joinLate.success, false);
            assert.equal(joinLate.error_code, "ROOM_NOT_WAITING");
        });
        it("Test 7: Two independent rooms do not share state", () => {
            const roomMgr = new ServerRoomManager();
            const ws1 = new MockWebSocket();
            const host1 = new Player("h1", "Host1", ws1);
            const r1 = roomMgr.createRoom(host1, "Room 1", 6, "PUBLIC", "FOREHEAD_POKER", "ROOM01").room;
            const ws2 = new MockWebSocket();
            const host2 = new Player("h2", "Host2", ws2);
            const r2 = roomMgr.createRoom(host2, "Room 2", 6, "PUBLIC", "FOREHEAD_POKER", "ROOM02").room;
            assert.notEqual(r1.roomId, r2.roomId);
            assert.equal(r1.players.size, 1);
            assert.equal(r2.players.size, 1);
            assert.equal(r1.players.has("h1"), true);
            assert.equal(r1.players.has("h2"), false);
            assert.equal(r2.players.has("h2"), true);
            assert.equal(r2.players.has("h1"), false);
        });
    });
    describe("B. Card Privacy Verification (Tests 8–10)", () => {
        it("Test 8: Strict WebSocket payload inspection for 3 players", () => {
            const wsA = new MockWebSocket();
            const wsB = new MockWebSocket();
            const wsC = new MockWebSocket();
            const pA = new Player("pA", "Alice", wsA);
            const pB = new Player("pB", "Bob", wsB);
            const pC = new Player("pC", "Charlie", wsC);
            const room = new Room("POKER3", pA, "Poker Room", 6, "PUBLIC", "FOREHEAD_POKER");
            room.addPlayer(pB);
            room.addPlayer(pC);
            pA.isReady = true;
            pB.isReady = true;
            pC.isReady = true;
            // Start match -> draws round 1 and sends segregated payloads
            const startRes = room.startMatch("pA");
            assert.equal(startRes.success, true);
            // Verify Player A's received payloads
            const msgsA = wsA.sentMessages;
            const privateHandA = msgsA.find((m) => m.type === "POKER_PRIVATE_HAND");
            const opponentForeheadsA = msgsA.find((m) => m.type === "POKER_OPPONENT_FOREHEADS");
            const bettingStateA = msgsA.find((m) => m.type === "POKER_BETTING_STATE");
            assert.ok(privateHandA, "Player A must receive POKER_PRIVATE_HAND");
            assert.ok(opponentForeheadsA, "Player A must receive POKER_OPPONENT_FOREHEADS");
            assert.ok(bettingStateA, "Player A must receive POKER_BETTING_STATE");
            // 1. Player A receives their own Hand card (number between 1 and 10)
            assert.equal(typeof privateHandA.card, "number");
            assert.ok(privateHandA.card >= 1 && privateHandA.card <= 10);
            // 2. Player A NEVER receives their own Forehead card
            const ownForeheadInA = opponentForeheadsA.cards.find((c) => c.player_id === "pA");
            assert.equal(ownForeheadInA, undefined, "Player A's forehead card must NOT be in opponent foreheads sent to A");
            // 3. Player A receives B and C forehead cards
            assert.equal(opponentForeheadsA.cards.length, 2);
            const foreheadB = opponentForeheadsA.cards.find((c) => c.player_id === "pB");
            const foreheadC = opponentForeheadsA.cards.find((c) => c.player_id === "pC");
            assert.ok(foreheadB && typeof foreheadB.card === "number");
            assert.ok(foreheadC && typeof foreheadC.card === "number");
            // 4. Opponents' Hand cards are NEVER sent to Player A
            const actualHandB = room.pokerMatch.getPlayerState("pB").handDeck.currentCard;
            const actualHandC = room.pokerMatch.getPlayerState("pC").handDeck.currentCard;
            const privateHandsA = msgsA.filter((m) => m.type === "POKER_PRIVATE_HAND");
            assert.equal(privateHandsA.length, 1);
            assert.equal(privateHandsA[0].card, room.pokerMatch.getPlayerState("pA").handDeck.currentCard);
            // 5. No entire deck or future draw order is present in any payload
            const rawPayloadsA = JSON.stringify(msgsA);
            assert.equal(rawPayloadsA.includes("handDeck"), false);
            assert.equal(rawPayloadsA.includes("cardsRemaining"), false);
        });
        it("Test 9: Mutual card privacy across all 3 players", () => {
            const wsA = new MockWebSocket();
            const wsB = new MockWebSocket();
            const wsC = new MockWebSocket();
            const pA = new Player("pA", "Alice", wsA);
            const pB = new Player("pB", "Bob", wsB);
            const pC = new Player("pC", "Charlie", wsC);
            const room = new Room("POKER3B", pA, "Poker Room", 6, "PUBLIC", "FOREHEAD_POKER");
            room.addPlayer(pB);
            room.addPlayer(pC);
            pA.isReady = true;
            pB.isReady = true;
            pC.isReady = true;
            room.startMatch("pA");
            const match = room.pokerMatch;
            const actualHandA = match.getPlayerState("pA").handDeck.currentCard;
            const actualForeheadA = match.getPlayerState("pA").foreheadDeck.currentCard;
            const actualHandB = match.getPlayerState("pB").handDeck.currentCard;
            const actualForeheadB = match.getPlayerState("pB").foreheadDeck.currentCard;
            // Verify B's perspective
            const msgsB = wsB.sentMessages;
            const privateHandB = msgsB.find((m) => m.type === "POKER_PRIVATE_HAND");
            const opponentForeheadsB = msgsB.find((m) => m.type === "POKER_OPPONENT_FOREHEADS");
            assert.equal(privateHandB.card, actualHandB);
            assert.equal(opponentForeheadsB.cards.find((c) => c.player_id === "pB"), undefined);
            const seenAByB = opponentForeheadsB.cards.find((c) => c.player_id === "pA");
            assert.equal(seenAByB.card, actualForeheadA);
            // Verify A's perspective
            const msgsA = wsA.sentMessages;
            const opponentForeheadsA = msgsA.find((m) => m.type === "POKER_OPPONENT_FOREHEADS");
            const seenBByA = opponentForeheadsA.cards.find((c) => c.player_id === "pB");
            assert.equal(seenBByA.card, actualForeheadB);
        });
        it("Test 10: Public round status contains ZERO card numbers", () => {
            const room = new Room("POKER_PUB", new Player("p1", "P1", new MockWebSocket()), "", 6, "PUBLIC", "FOREHEAD_POKER");
            room.addPlayer(new Player("p2", "P2", new MockWebSocket()));
            room.players.get("p1").isReady = true;
            room.players.get("p2").isReady = true;
            room.startMatch("p1");
            const status = room.pokerMatch.getPublicRoundStatusPayload();
            const str = JSON.stringify(status);
            assert.equal(str.includes("card"), false);
            assert.equal(status.type, "POKER_ROUND_STATUS");
            assert.equal(status.round, 1);
        });
    });
    describe("C. Betting Synchronization & State Versioning (Tests 11–15)", () => {
        it("Test 11: Real-time action broadcast and balance synchronization", () => {
            const wsA = new MockWebSocket();
            const wsB = new MockWebSocket();
            const wsC = new MockWebSocket();
            const pA = new Player("pA", "Alice", wsA);
            const pB = new Player("pB", "Bob", wsB);
            const pC = new Player("pC", "Charlie", wsC);
            const roomMgr = new ServerRoomManager();
            const handler = new WebSocketHandler(roomMgr);
            handler.handleConnection(wsA);
            handler.handleConnection(wsB);
            handler.handleConnection(wsC);
            // Get assigned player IDs
            const pIdA = wsA.sentMessages[0].client_id;
            const pIdB = wsB.sentMessages[0].client_id;
            const pIdC = wsC.sentMessages[0].client_id;
            // Host creates room
            wsA.emit("message", Buffer.from(JSON.stringify({
                type: "CREATE_ROOM",
                room_name: "Poker Saloon",
                game_mode: "FOREHEAD_POKER",
                max_players: 6,
            })));
            const roomStateMsg = wsA.sentMessages.find((m) => m.type === "ROOM_STATE");
            assert.ok(roomStateMsg, "Host must receive initial ROOM_STATE");
            const createdRoomCode = roomStateMsg.room.room_code;
            assert.ok(createdRoomCode, "Room code must be assigned");
            // Guests join
            wsB.emit("message", Buffer.from(JSON.stringify({ type: "JOIN_ROOM", room_code: createdRoomCode })));
            wsC.emit("message", Buffer.from(JSON.stringify({ type: "JOIN_ROOM", room_code: createdRoomCode })));
            // Ready up
            wsA.emit("message", Buffer.from(JSON.stringify({ type: "TOGGLE_READY", room_code: createdRoomCode })));
            wsB.emit("message", Buffer.from(JSON.stringify({ type: "TOGGLE_READY", room_code: createdRoomCode })));
            wsC.emit("message", Buffer.from(JSON.stringify({ type: "TOGGLE_READY", room_code: createdRoomCode })));
            // Start match
            wsA.emit("message", Buffer.from(JSON.stringify({ type: "START_MATCH", room_code: createdRoomCode })));
            const room = roomMgr.findRoomByCode(createdRoomCode);
            assert.ok(room, "Room must be found");
            assert.equal(room.status, "STARTED");
            assert.equal(room.pokerMatch.round, 1);
            // Ante deducted: each has 99, total pot = 3
            wsA.clear();
            wsB.clear();
            wsC.clear();
            // Current turn player performs RAISE to 4
            const activePid = room.pokerMatch.bettingManager.currentTurnPlayerId;
            const activeWs = activePid === pIdA ? wsA : (activePid === pIdB ? wsB : wsC);
            activeWs.emit("message", Buffer.from(JSON.stringify({
                type: "POKER_BETTING_ACTION",
                room_code: createdRoomCode,
                action: "RAISE",
                target_bet: 4,
            })));
            // All 3 WebSockets must receive POKER_ACTION_RESULT and POKER_BETTING_STATE
            for (const ws of [wsA, wsB, wsC]) {
                const actionResult = ws.sentMessages.find((m) => m.type === "POKER_ACTION_RESULT");
                const bettingState = ws.sentMessages.find((m) => m.type === "POKER_BETTING_STATE");
                assert.ok(actionResult, "Must receive POKER_ACTION_RESULT");
                assert.ok(bettingState, "Must receive POKER_BETTING_STATE");
                assert.equal(actionResult.action_result.action, "RAISE");
                assert.equal(actionResult.action_result.player_id, activePid);
                assert.equal(bettingState.current_highest_bet, 4);
                assert.equal(bettingState.total_pot, 7); // 3 antes + 4 bet
                assert.ok(bettingState.version > 1, "State version must increment");
            }
        });
        it("Test 12: Monotonic state versioning increments on each state mutation", () => {
            const room = new Room("VER01", new Player("p1", "P1", new MockWebSocket()), "", 6, "PUBLIC", "FOREHEAD_POKER");
            room.addPlayer(new Player("p2", "P2", new MockWebSocket()));
            room.players.get("p1").isReady = true;
            room.players.get("p2").isReady = true;
            room.startMatch("p1");
            const v1 = room.pokerMatch.stateVersion;
            assert.ok(v1 >= 2, "Version must be at least 2 after match start and round 1 draw");
            room.pokerMatch.processBettingAction("p1", "CHECK");
            const v2 = room.pokerMatch.stateVersion;
            assert.ok(v2 > v1, "Version must increment after action");
            room.pokerMatch.processBettingAction("p2", "CHECK");
            const v3 = room.pokerMatch.stateVersion;
            assert.ok(v3 > v2, "Version must increment after second action");
        });
        it("Test 13: Canonical protocol schema validates required fields", () => {
            const room = new Room("SCH01", new Player("p1", "P1", new MockWebSocket()), "", 6, "PUBLIC", "FOREHEAD_POKER");
            room.addPlayer(new Player("p2", "P2", new MockWebSocket()));
            room.players.get("p1").isReady = true;
            room.players.get("p2").isReady = true;
            room.startMatch("p1");
            const payload = room.pokerMatch.getPublicBettingPayload();
            // Check canonical property names
            assert.equal(payload.type, "POKER_BETTING_STATE");
            assert.equal(typeof payload.version, "number");
            assert.equal(typeof payload.betting_phase_active, "boolean");
            assert.equal(typeof payload.betting_active, "boolean");
            assert.ok(Array.isArray(payload.players), "payload.players must be an Array");
            assert.equal(payload.players.length, 2);
            const p0 = payload.players[0];
            assert.ok("player_id" in p0);
            assert.ok("seat_index" in p0);
            assert.ok("balance" in p0);
            assert.ok("round_bet" in p0);
            assert.ok("total_contribution" in p0);
            assert.ok("is_folded" in p0);
            assert.ok("is_all_in" in p0);
            assert.ok("has_acted" in p0);
        });
        it("Test 14: Action out of turn is rejected without altering chip balance or version", () => {
            const room = new Room("TURN01", new Player("p1", "P1", new MockWebSocket()), "", 6, "PUBLIC", "FOREHEAD_POKER");
            room.addPlayer(new Player("p2", "P2", new MockWebSocket()));
            room.players.get("p1").isReady = true;
            room.players.get("p2").isReady = true;
            room.startMatch("p1");
            const nonTurnPlayer = room.pokerMatch.bettingManager.currentTurnPlayerId === "p1" ? "p2" : "p1";
            const verBefore = room.pokerMatch.stateVersion;
            const res = room.pokerMatch.processBettingAction(nonTurnPlayer, "RAISE", 10);
            assert.equal(res.success, false);
            assert.equal(res.error, "NOT_PLAYER_TURN");
            assert.equal(room.pokerMatch.stateVersion, verBefore, "Version must not advance on rejected action");
        });
        it("Test 15: Fold and All-in affect only the acting player", () => {
            const room = new Room("ACT01", new Player("p1", "P1", new MockWebSocket()), "", 6, "PUBLIC", "FOREHEAD_POKER");
            room.addPlayer(new Player("p2", "P2", new MockWebSocket()));
            room.players.get("p1").isReady = true;
            room.players.get("p2").isReady = true;
            room.startMatch("p1");
            const turn1 = room.pokerMatch.bettingManager.currentTurnPlayerId;
            room.pokerMatch.processBettingAction(turn1, "FOLD");
            const pub = room.pokerMatch.getPublicBettingPayload();
            const foldedEntry = pub.players.find((p) => p.player_id === turn1);
            const otherEntry = pub.players.find((p) => p.player_id !== turn1);
            assert.equal(foldedEntry.is_folded, true);
            assert.equal(otherEntry.is_folded, false);
        });
    });
    describe("D. Disconnection and Reconnection (Tests 16–19)", () => {
        it("Test 16: Disconnect during betting preserves seat, balance, and cards", () => {
            const wsA = new MockWebSocket();
            const wsB = new MockWebSocket();
            const pA = new Player("pA", "Alice", wsA);
            const pB = new Player("pB", "Bob", wsB);
            const room = new Room("DISC01", pA, "Poker Room", 6, "PUBLIC", "FOREHEAD_POKER");
            room.addPlayer(pB);
            pA.isReady = true;
            pB.isReady = true;
            room.startMatch("pA");
            const seatA = pA.seatIndex;
            const balanceA = room.pokerMatch.bettingManager.players.get("pA").balance;
            const handA = room.pokerMatch.getPlayerState("pA").handDeck.currentCard;
            // Player A disconnects
            const removeRes = room.removePlayer("pA");
            assert.equal(removeRes.success, true);
            assert.equal(removeRes.roomClosed, false, "Room must NOT close when 1 of 2 players disconnects during poker match");
            assert.equal(pA.isDisconnected, true);
            // Reconnect with valid token
            const wsANew = new MockWebSocket();
            const reconnectRes = room.reconnectPlayer("pA", pA.reconnectToken, wsANew);
            assert.equal(reconnectRes.success, true);
            assert.equal(pA.isDisconnected, false);
            assert.equal(pA.seatIndex, seatA, "Original seat must be restored");
            // Verify state snapshots delivered to newly connected WebSocket
            const reconnectedHand = wsANew.sentMessages.find((m) => m.type === "POKER_PRIVATE_HAND");
            const reconnectedBetting = wsANew.sentMessages.find((m) => m.type === "POKER_BETTING_STATE");
            const reconnectedAck = wsANew.sentMessages.find((m) => m.type === "POKER_RECONNECT_RESPONSE");
            assert.ok(reconnectedAck, "Must receive POKER_RECONNECT_RESPONSE");
            assert.equal(reconnectedAck.seat_index, seatA);
            assert.ok(reconnectedHand);
            assert.equal(reconnectedHand.card, handA, "Original Hand card must be restored");
            assert.ok(reconnectedBetting);
            const restoredEntry = reconnectedBetting.players.find((p) => p.player_id === "pA");
            assert.equal(restoredEntry.balance, balanceA, "Original chip balance must be preserved");
        });
        it("Test 17: Reconnect with invalid token is rejected", () => {
            const wsA = new MockWebSocket();
            const pA = new Player("pA", "Alice", wsA);
            const room = new Room("DISC02", pA, "Poker Room", 6, "PUBLIC", "FOREHEAD_POKER");
            const wsFake = new MockWebSocket();
            const res = room.reconnectPlayer("pA", "WRONG_TOKEN", wsFake);
            assert.equal(res.success, false);
            assert.equal(res.error_code, "INVALID_TOKEN");
        });
        it("Test 18: Disconnected player turn automatically advances without indefinitely blocking", () => {
            const wsA = new MockWebSocket();
            const wsB = new MockWebSocket();
            const wsC = new MockWebSocket();
            const pA = new Player("pA", "Alice", wsA);
            const pB = new Player("pB", "Bob", wsB);
            const pC = new Player("pC", "Charlie", wsC);
            const room = new Room("DISC03", pA, "Poker Room", 6, "PUBLIC", "FOREHEAD_POKER");
            room.addPlayer(pB);
            room.addPlayer(pC);
            pA.isReady = true;
            pB.isReady = true;
            pC.isReady = true;
            room.startMatch("pA");
            const currentTurnPid = room.pokerMatch.bettingManager.currentTurnPlayerId;
            // Disconnect whoever's turn it is
            room.removePlayer(currentTurnPid);
            // Turn must have advanced to another eligible player
            const nextTurnPid = room.pokerMatch.bettingManager.currentTurnPlayerId;
            assert.notEqual(nextTurnPid, currentTurnPid, "Turn must advance past disconnected player");
            assert.ok(nextTurnPid === "pA" || nextTurnPid === "pB" || nextTurnPid === "pC");
        });
        it("Test 19: Full room closure when all players disconnect", () => {
            const wsA = new MockWebSocket();
            const wsB = new MockWebSocket();
            const pA = new Player("pA", "Alice", wsA);
            const pB = new Player("pB", "Bob", wsB);
            const room = new Room("DISC04", pA, "Poker Room", 6, "PUBLIC", "FOREHEAD_POKER");
            room.addPlayer(pB);
            pA.isReady = true;
            pB.isReady = true;
            room.startMatch("pA");
            room.removePlayer("pA");
            const lastRemove = room.removePlayer("pB");
            assert.equal(lastRemove.roomClosed, true);
            assert.equal(room.status, "CLOSED");
        });
    });
    describe("E. Six-Player Full Scalability Test (Test 20)", () => {
        it("Test 20: 6 distinct players, 6 seats (0–5), private cards, and synchronized betting", () => {
            const sockets = [];
            const players = [];
            for (let i = 0; i < 6; i++) {
                const ws = new MockWebSocket();
                sockets.push(ws);
                const p = new Player(`player_${i}`, `P${i}`, ws);
                players.push(p);
            }
            const room = new Room("SIX01", players[0], "Big Table", 6, "PUBLIC", "FOREHEAD_POKER");
            for (let i = 1; i < 6; i++) {
                room.addPlayer(players[i]);
            }
            // Verify all 6 unique seats assigned
            const assignedSeats = players.map((p) => p.seatIndex);
            assert.deepEqual(assignedSeats.sort(), [0, 1, 2, 3, 4, 5]);
            for (const p of players) {
                p.isReady = true;
            }
            const startRes = room.startMatch("player_0");
            assert.equal(startRes.success, true);
            assert.equal(room.status, "STARTED");
            assert.equal(room.pokerMatch.getPlayerCount(), 6);
            // Verify card privacy for all 6 players
            for (let i = 0; i < 6; i++) {
                const msgs = sockets[i].sentMessages;
                const privateHand = msgs.find((m) => m.type === "POKER_PRIVATE_HAND");
                const opponentForeheads = msgs.find((m) => m.type === "POKER_OPPONENT_FOREHEADS");
                assert.ok(privateHand, `Player ${i} must receive private hand`);
                assert.ok(opponentForeheads, `Player ${i} must receive opponent foreheads`);
                assert.equal(opponentForeheads.cards.length, 5, `Player ${i} must see exactly 5 opponent foreheads`);
                // Own forehead card must never be present
                const selfSeen = opponentForeheads.cards.find((c) => c.player_id === `player_${i}`);
                assert.equal(selfSeen, undefined, `Player ${i} must NEVER receive own forehead card`);
            }
            // Check betting pot: 6 players * 1 ante = 6 chips
            const pubBetting = room.pokerMatch.getPublicBettingPayload();
            assert.equal(pubBetting.total_pot, 6);
            assert.equal(pubBetting.players.length, 6);
        });
    });
});
