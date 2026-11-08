import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { ServerRoomManager } from "../src/rooms/room_manager.js";
import { WebSocketHandler } from "../src/websocket/handler.js";
import { Player } from "../src/players/player.js";
import type { ServerMessage } from "../src/websocket/protocol.js";

function createMockWebSocket(onMessage?: (msg: ServerMessage) => void) {
  const sentMessages: ServerMessage[] = [];
  const mockWs: any = {
    OPEN: 1,
    readyState: 1,
    send: (payload: string) => {
      const parsed = JSON.parse(payload) as ServerMessage;
      sentMessages.push(parsed);
      if (onMessage) onMessage(parsed);
    },
    on: () => {},
    close: () => {},
  };
  return { mockWs, sentMessages };
}

describe("FOREHEAD POKER – P5.1 GAME MODE ROUTING & LOBBY SUITE", () => {
  it("Test 1: Client sends game_mode: FOREHEAD_POKER and server initializes poker room", () => {
    const roomManager = new ServerRoomManager();
    const handler = new WebSocketHandler(roomManager);

    const { mockWs, sentMessages } = createMockWebSocket();
    handler.handleConnection(mockWs);

    const host = (handler as any).playersByWs.get(mockWs) as Player;
    assert.ok(host);

    // Host sends CREATE_ROOM with game_mode: FOREHEAD_POKER
    (handler as any).handleMessage(mockWs, Buffer.from(JSON.stringify({
      type: "CREATE_ROOM",
      display_name: "PokerHost",
      game_mode: "FOREHEAD_POKER",
      max_players: 6,
    })));

    const roomStateMsg = sentMessages.find((m) => m.type === "ROOM_STATE");
    assert.ok(roomStateMsg, "Must receive ROOM_STATE");
    assert.ok(roomStateMsg.room);
    assert.equal(roomStateMsg.room.game_mode, "FOREHEAD_POKER");
    assert.equal(roomStateMsg.room.max_players, 6);

    const room = roomManager.findRoomByCode(roomStateMsg.room.room_code);
    assert.ok(room);
    assert.equal(room.gameMode, "FOREHEAD_POKER");
    assert.equal(room.maxPlayers, 6);

    const hostRecord = room.players.get(host.playerId);
    assert.ok(hostRecord);
    assert.equal(hostRecord.seatIndex, 0);
  });

  it("Test 2: Client sends mode: FOREHEAD_POKER (backward compatibility fallback)", () => {
    const roomManager = new ServerRoomManager();
    const handler = new WebSocketHandler(roomManager);

    const { mockWs, sentMessages } = createMockWebSocket();
    handler.handleConnection(mockWs);

    (handler as any).handleMessage(mockWs, Buffer.from(JSON.stringify({
      type: "CREATE_ROOM",
      display_name: "PokerHost2",
      mode: "FOREHEAD_POKER",
    })));

    const roomStateMsg = sentMessages.find((m) => m.type === "ROOM_STATE");
    assert.ok(roomStateMsg?.room);
    assert.equal(roomStateMsg.room.game_mode, "FOREHEAD_POKER");
    assert.equal(roomStateMsg.room.max_players, 6);
  });

  it("Test 3: Territory modes (1v1, 2v2, 3v3) preserve their respective mode and capacity", () => {
    const roomManager = new ServerRoomManager();
    const handler = new WebSocketHandler(roomManager);

    for (const [mode, expectedCap] of [["1v1", 2], ["2v2", 4], ["3v3", 6]] as const) {
      const { mockWs, sentMessages } = createMockWebSocket();
      handler.handleConnection(mockWs);

      (handler as any).handleMessage(mockWs, Buffer.from(JSON.stringify({
        type: "CREATE_ROOM",
        display_name: `TerritoryHost_${mode}`,
        game_mode: mode,
      })));

      const roomState = sentMessages.find((m) => m.type === "ROOM_STATE");
      assert.ok(roomState?.room);
      assert.equal(roomState.room.game_mode, mode);
      assert.equal(roomState.room.max_players, expectedCap);
    }
  });

  it("Test 4: Joining players receive game_mode: FOREHEAD_POKER and seat assignments 0–5", () => {
    const roomManager = new ServerRoomManager();
    const handler = new WebSocketHandler(roomManager);

    const { mockWs: hostWs, sentMessages: hostMsgs } = createMockWebSocket();
    handler.handleConnection(hostWs);

    (handler as any).handleMessage(hostWs, Buffer.from(JSON.stringify({
      type: "CREATE_ROOM",
      display_name: "HostPlayer",
      game_mode: "FOREHEAD_POKER",
    })));

    const roomCode = hostMsgs.find((m) => m.type === "ROOM_STATE")!.room!.room_code;

    // Join 3 guest players
    const guestWsList = [createMockWebSocket(), createMockWebSocket(), createMockWebSocket()];
    for (let i = 0; i < guestWsList.length; i++) {
      const { mockWs, sentMessages } = guestWsList[i];
      handler.handleConnection(mockWs);

      (handler as any).handleMessage(mockWs, Buffer.from(JSON.stringify({
        type: "JOIN_ROOM",
        room_code: roomCode,
        display_name: `Guest_${i + 1}`,
      })));

      const joinState = sentMessages.find((m) => m.type === "ROOM_STATE");
      assert.ok(joinState?.room);
      assert.equal(joinState.room.game_mode, "FOREHEAD_POKER");

      const guestPlayer = joinState.room.players.find((p) => p.display_name === `Guest_${i + 1}`);
      assert.ok(guestPlayer);
      assert.equal(guestPlayer.seat_index, i + 1, `Guest ${i + 1} should have seat_index ${i + 1}`);
    }
  });

  it("Test 5: Match start requires >= 2 players and all ready for Forehead Poker", () => {
    const roomManager = new ServerRoomManager();
    const handler = new WebSocketHandler(roomManager);

    const { mockWs: hostWs, sentMessages: hostMsgs } = createMockWebSocket();
    handler.handleConnection(hostWs);

    (handler as any).handleMessage(hostWs, Buffer.from(JSON.stringify({
      type: "CREATE_ROOM",
      display_name: "HostOnly",
      game_mode: "FOREHEAD_POKER",
    })));

    const roomCode = hostMsgs.find((m) => m.type === "ROOM_STATE")!.room!.room_code;

    // Host readies up alone
    (handler as any).handleMessage(hostWs, Buffer.from(JSON.stringify({
      type: "TOGGLE_READY",
      room_code: roomCode,
    })));

    // Try to start match with only 1 player
    (handler as any).handleMessage(hostWs, Buffer.from(JSON.stringify({
      type: "START_MATCH",
      room_code: roomCode,
    })));

    const errMsg = hostMsgs.find((m) => m.type === "ERROR" && (m.error_code === "NOT_ENOUGH_PLAYERS" || m.error_code === "START_FAILED"));
    assert.ok(errMsg, "Start match with 1 player should fail");
    assert.match(errMsg.message || "", /At least 2.*required/);

    // Guest joins
    const { mockWs: guestWs, sentMessages: guestMsgs } = createMockWebSocket();
    handler.handleConnection(guestWs);

    (handler as any).handleMessage(guestWs, Buffer.from(JSON.stringify({
      type: "JOIN_ROOM",
      room_code: roomCode,
      display_name: "GuestPlayer",
    })));

    // Host tries to start before guest is ready
    (handler as any).handleMessage(hostWs, Buffer.from(JSON.stringify({
      type: "START_MATCH",
      room_code: roomCode,
    })));

    const notReadyErr = hostMsgs.find((m) => m.type === "ERROR" && m.error_code === "PLAYERS_NOT_READY");
    assert.ok(notReadyErr, "Start match before all ready should fail");

    // Guest toggles ready
    (handler as any).handleMessage(guestWs, Buffer.from(JSON.stringify({
      type: "TOGGLE_READY",
      room_code: roomCode,
    })));

    // Host starts match now that 2/2 are ready
    (handler as any).handleMessage(hostWs, Buffer.from(JSON.stringify({
      type: "START_MATCH",
      room_code: roomCode,
    })));

    const hostMatchStarted = hostMsgs.find((m) => m.type === "MATCH_STARTED");
    const guestMatchStarted = guestMsgs.find((m) => m.type === "MATCH_STARTED");

    assert.ok(hostMatchStarted, "Host must receive MATCH_STARTED");
    assert.ok(guestMatchStarted, "Guest must receive MATCH_STARTED");

    assert.equal(hostMatchStarted.game_mode, "FOREHEAD_POKER");
    assert.equal(guestMatchStarted.game_mode, "FOREHEAD_POKER");
    assert.equal((hostMatchStarted as any).mode, "FOREHEAD_POKER");
  });

  it("Test 6: Territory mode start requires equal teams and full capacity", () => {
    const roomManager = new ServerRoomManager();
    const handler = new WebSocketHandler(roomManager);

    const { mockWs: hostWs, sentMessages: hostMsgs } = createMockWebSocket();
    handler.handleConnection(hostWs);

    (handler as any).handleMessage(hostWs, Buffer.from(JSON.stringify({
      type: "CREATE_ROOM",
      display_name: "TerritoryHost",
      game_mode: "1v1",
    })));

    const roomCode = hostMsgs.find((m) => m.type === "ROOM_STATE")!.room!.room_code;

    // Ready host alone
    (handler as any).handleMessage(hostWs, Buffer.from(JSON.stringify({
      type: "TOGGLE_READY",
      room_code: roomCode,
    })));

    // Try starting 1v1 with only 1 player
    (handler as any).handleMessage(hostWs, Buffer.from(JSON.stringify({
      type: "START_MATCH",
      room_code: roomCode,
    })));

    const err1 = hostMsgs.find((m) => m.type === "ERROR");
    assert.ok(err1);
    assert.match(err1.message || "", /At least 2.*required/);
  });
});
