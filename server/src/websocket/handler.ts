import type { WebSocket, RawData } from "ws";
import { ServerRoomManager } from "../rooms/room_manager.js";
import { Player } from "../players/player.js";
import type { ClientMessage, ServerMessage } from "./protocol.js";

export class WebSocketHandler {
  private roomManager: ServerRoomManager;
  private playersByWs: Map<WebSocket, Player> = new Map();
  private nextClientId: number = 1;

  constructor(roomManager: ServerRoomManager) {
    this.roomManager = roomManager;
  }

  public handleConnection(ws: WebSocket): void {
    const defaultId = `player_${this.nextClientId++}`;
    const player = new Player(defaultId, "Player", ws);
    this.playersByWs.set(ws, player);

    // Send connection ack
    player.send({
      type: "CONNECTED",
      client_id: player.playerId,
      reconnect_token: player.reconnectToken,
    });

    ws.on("message", (data: RawData) => {
      this.handleMessage(ws, data);
    });

    ws.on("close", () => {
      this.handleDisconnect(ws);
    });

    ws.on("error", (err) => {
      console.error(`WebSocket error for player ${player.playerId}:`, err);
    });
  }

  public handleDisconnect(ws: WebSocket): void {
    const player = this.playersByWs.get(ws);
    if (!player) return;

    if (player.currentRoomCode) {
      const room = this.roomManager.findRoomByCode(player.currentRoomCode);
      if (room) {
        const { roomClosed } = room.removePlayer(player.playerId);
        if (room.pokerMatch) {
          room.pokerMatch.bettingManager.handleDisconnect(player.playerId);
          if (room.pokerMatch.bettingManager.bettingPhaseActive) {
            room.broadcast(room.pokerMatch.getPublicBettingPayload());
          }
        }
        if (roomClosed) {
          room.broadcast({
            type: "ROOM_CLOSED",
            room_code: room.roomCode,
            reason: "The host disconnected.",
          });
          this.roomManager.closeRoom(room.roomCode);
        } else {
          room.broadcastRoomState();
        }
      }
    }

    this.playersByWs.delete(ws);
  }

  private handleMessage(ws: WebSocket, raw: RawData): void {
    const player = this.playersByWs.get(ws);
    if (!player) return;

    let msg: ClientMessage;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      player.send({ type: "ERROR", error_code: "BAD_JSON", message: "Malformed JSON payload." });
      return;
    }

    switch (msg.type) {
      case "PING":
        player.isAlive = true;
        player.send({ type: "PONG" });
        break;

      case "CONNECT_CLIENT":
        if (msg.player_id?.trim()) {
          player.playerId = msg.player_id.trim();
        }
        if (msg.display_name?.trim()) {
          player.displayName = msg.display_name.trim();
        }
        player.send({
          type: "CONNECTED",
          client_id: player.playerId,
        });
        break;

      case "CREATE_ROOM":
        this.handleCreateRoom(player, msg);
        break;

      case "JOIN_ROOM":
        this.handleJoinRoom(player, msg);
        break;

      case "LEAVE_ROOM":
        this.handleLeaveRoom(player, msg);
        break;

      case "UPDATE_TEAM":
        this.handleUpdateTeam(player, msg);
        break;

      case "UPDATE_CHARACTER":
        this.handleUpdateCharacter(player, msg);
        break;

      case "UPDATE_NAME":
        this.handleUpdateName(player, msg);
        break;

      case "TOGGLE_READY":
        this.handleToggleReady(player, msg);
        break;

      case "START_MATCH":
        this.handleStartMatch(player, msg);
        break;

      case "PLAYER_MOVE":
        this.handlePlayerMove(player, msg);
        break;

      case "CLAIM_TILE":
        this.handleClaimTile(player, msg);
        break;

      case "REMATCH_REQUEST":
        this.handleRematch(player, msg);
        break;

      case "POKER_START_MATCH":
        this.handlePokerStartMatch(player, msg);
        break;

      case "POKER_DRAW_ROUND":
        this.handlePokerDrawRound(player, msg);
        break;

      case "POKER_RESET_MATCH":
        this.handlePokerResetMatch(player, msg);
        break;

      case "POKER_BETTING_ACTION":
        this.handlePokerBettingAction(player, msg);
        break;

      case "POKER_PICK_CARDS":
        this.handlePokerPickCards(player, msg);
        break;

      case "POKER_RECONNECT":
        this.handlePokerReconnect(player, msg);
        break;

      default:
        player.send({ type: "ERROR", error_code: "UNKNOWN_MESSAGE", message: `Unknown message type: ${(msg as any).type}` });
        break;
    }
  }

  private handleCreateRoom(player: Player, msg: ClientMessage): void {
    if (player.currentRoomCode) {
      const existing = this.roomManager.findRoomByCode(player.currentRoomCode);
      if (existing) {
        const { roomClosed } = existing.removePlayer(player.playerId);
        if (roomClosed) {
          existing.broadcast({
            type: "ROOM_CLOSED",
            room_code: existing.roomCode,
            reason: "The room was closed.",
          });
          this.roomManager.closeRoom(existing.roomCode);
        } else {
          existing.broadcastRoomState();
        }
      }
      player.currentRoomCode = null;
    }

    if (msg.display_name?.trim()) {
      player.displayName = msg.display_name.trim();
    }
    if (msg.character_id) {
      player.characterId = msg.character_id;
    }

    const maxPlayers = msg.max_players || 2;
    const visibility = (msg.visibility?.toUpperCase() === "PUBLIC" ? "PUBLIC" : "PRIVATE") as "PUBLIC" | "PRIVATE";
    const gameMode = msg.game_mode || msg.mode || "1v1";
    const roomName = msg.room_name || "";

    const res = this.roomManager.createRoom(player, roomName, maxPlayers, visibility, gameMode, msg.room_code);
    if (!res.success || !res.room) {
      player.send({ type: "ERROR", error_code: res.error_code || "CREATE_FAILED", message: res.message || "Failed to create room." });
      return;
    }

    res.room.broadcastRoomState();
  }

  private handleJoinRoom(player: Player, msg: ClientMessage): void {
    if (!msg.room_code) {
      player.send({ type: "ERROR", error_code: "MISSING_ROOM_CODE", message: "Enter a room code." });
      return;
    }

    const room = this.roomManager.findRoomByCode(msg.room_code);
    if (!room) {
      player.send({ type: "ERROR", error_code: "ROOM_NOT_FOUND", message: "No room with that code exists." });
      return;
    }

    if (player.currentRoomCode && player.currentRoomCode !== room.roomCode) {
      const oldRoom = this.roomManager.findRoomByCode(player.currentRoomCode);
      if (oldRoom) {
        const { roomClosed } = oldRoom.removePlayer(player.playerId);
        if (roomClosed) {
          oldRoom.broadcast({
            type: "ROOM_CLOSED",
            room_code: oldRoom.roomCode,
            reason: "The room was closed.",
          });
          this.roomManager.closeRoom(oldRoom.roomCode);
        } else {
          oldRoom.broadcastRoomState();
        }
      }
      player.currentRoomCode = null;
    }

    if (msg.display_name?.trim()) {
      player.displayName = msg.display_name.trim();
    }
    if (msg.character_id) {
      player.characterId = msg.character_id;
    }

    const addRes = room.addPlayer(player);
    if (!addRes.success) {
      player.send({ type: "ERROR", error_code: addRes.error_code || "JOIN_FAILED", message: addRes.message || "Could not join room." });
      return;
    }

    room.broadcastRoomState();
  }

  private handleLeaveRoom(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    player.currentRoomCode = null;
    if (!code) {
      player.send({ type: "ERROR", error_code: "NOT_IN_ROOM", message: "You are not in a room." });
      return;
    }

    const room = this.roomManager.findRoomByCode(code);
    if (!room) {
      player.send({ type: "ERROR", error_code: "ROOM_NOT_FOUND", message: "Room not found." });
      return;
    }

    const { roomClosed } = room.removePlayer(player.playerId);
    if (roomClosed) {
      room.broadcast({
        type: "ROOM_CLOSED",
        room_code: room.roomCode,
        reason: "The host left the room.",
      });
      this.roomManager.closeRoom(room.roomCode);
    } else {
      room.broadcastRoomState();
    }
  }

  private handleUpdateTeam(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code) return;

    const room = this.roomManager.findRoomByCode(code);
    if (!room) return;

    const res = room.updatePlayerTeam(player.playerId, msg.team_id || 1);
    if (!res.success) {
      player.send({ type: "ERROR", error_code: res.error_code || "TEAM_UPDATE_FAILED", message: res.message || "Failed to update team." });
      return;
    }

    room.broadcastRoomState();
  }

  private handleUpdateCharacter(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code) return;

    const room = this.roomManager.findRoomByCode(code);
    if (!room) return;

    const res = room.updatePlayerCharacter(player.playerId, msg.character_id || "mint");
    if (!res.success) {
      player.send({ type: "ERROR", error_code: res.error_code || "CHAR_UPDATE_FAILED", message: res.message || "Failed to update character." });
      return;
    }

    room.broadcastRoomState();
  }

  private handleUpdateName(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code) return;

    const room = this.roomManager.findRoomByCode(code);
    if (!room) return;

    const res = room.updatePlayerDisplayName(player.playerId, msg.display_name || "Player");
    if (!res.success) {
      player.send({ type: "ERROR", error_code: res.error_code || "NAME_UPDATE_FAILED", message: res.message || "Failed to update name." });
      return;
    }

    room.broadcastRoomState();
  }

  private handleToggleReady(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code) return;

    const room = this.roomManager.findRoomByCode(code);
    if (!room) return;

    const res = room.togglePlayerReady(player.playerId);
    if (!res.success) {
      player.send({ type: "ERROR", error_code: res.error_code || "READY_TOGGLE_FAILED", message: res.message || "Failed to toggle ready." });
      return;
    }

    room.broadcastRoomState();
  }

  private handleStartMatch(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code) return;

    const room = this.roomManager.findRoomByCode(code);
    if (!room) return;

    const res = room.startMatch(player.playerId);
    if (!res.success) {
      player.send({ type: "ERROR", error_code: res.error_code || "START_FAILED", message: res.message || "Cannot start match." });
      return;
    }

    // Broadcast MATCH_STARTED to all clients in the room
    room.broadcast({
      type: "MATCH_STARTED",
      room_code: room.roomCode,
      roster: res.roster,
      game_mode: room.gameMode,
      mode: room.gameMode,
    });
  }

  private handlePlayerMove(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code) return;
    const room = this.roomManager.findRoomByCode(code);
    if (!room || room.status !== "STARTED") return;

    room.broadcastExcept(player.playerId, {
      type: "PLAYER_MOVED",
      player_id: player.playerId,
      position: msg.position,
      velocity: msg.velocity,
      rotation: msg.rotation,
      pitch: msg.pitch,
    });
  }

  private handleClaimTile(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code || msg.col === undefined || msg.row === undefined) return;
    const room = this.roomManager.findRoomByCode(code);
    if (!room || room.status !== "STARTED") return;

    const result = room.claimTile(player.playerId, msg.col, msg.row);
    if (!result) return;

    room.broadcast({
      type: "TILE_CLAIMED",
      col: msg.col,
      row: msg.row,
      team_id: result.teamId,
      red_score: result.redScore,
      blue_score: result.blueScore,
    });
  }

  private handleRematch(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code) return;
    const room = this.roomManager.findRoomByCode(code);
    if (!room) return;

    room.resetMatch();
    room.broadcast({
      type: "MATCH_RESET",
      room_code: room.roomCode,
    });
    room.broadcastRoomState();
  }

  private handlePokerStartMatch(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code) {
      player.send({ type: "ERROR", error_code: "NOT_IN_ROOM", message: "You are not in a room." });
      return;
    }

    const room = this.roomManager.findRoomByCode(code);
    if (!room) {
      player.send({ type: "ERROR", error_code: "ROOM_NOT_FOUND", message: "Room not found." });
      return;
    }

    if (player.playerId !== room.hostPlayerId) {
      player.send({ type: "ERROR", error_code: "NOT_HOST", message: "Only the host can start the poker match." });
      return;
    }

    if (room.status === "WAITING") {
      const res = room.startMatch(player.playerId);
      if (!res.success) {
        player.send({ type: "ERROR", error_code: res.error_code || "START_FAILED", message: res.message || "Failed to start match." });
        return;
      }
      room.broadcast({
        type: "MATCH_STARTED",
        room_code: room.roomCode,
        roster: res.roster,
        game_mode: room.gameMode,
      });
    }

    room.broadcast({
      type: "POKER_MATCH_INIT",
      room_code: room.roomCode,
      total_rounds: 10,
    });
  }

  private handlePokerReconnect(player: Player, msg: ClientMessage): void {
    const code = msg.room_code?.trim().toUpperCase();
    const pid = msg.player_id?.trim();
    const token = msg.reconnect_token?.trim();

    if (!code || !pid || !token) {
      player.send({
        type: "ERROR",
        error_code: "INVALID_RECONNECT_DATA",
        message: "Room code, player ID and reconnect token are required to reconnect.",
      });
      return;
    }

    const room = this.roomManager.findRoomByCode(code);
    if (!room) {
      player.send({
        type: "ERROR",
        error_code: "ROOM_NOT_FOUND",
        message: "Room not found.",
      });
      return;
    }

    const res = room.reconnectPlayer(pid, token, player.ws);
    if (!res.success) {
      player.send({
        type: "ERROR",
        error_code: res.error_code || "RECONNECT_FAILED",
        message: res.message || "Reconnect failed.",
      });
      return;
    }

    this.playersByWs.delete(player.ws);
    const existingPlayer = room.players.get(pid)!;
    this.playersByWs.set(existingPlayer.ws, existingPlayer);
  }

  private handlePokerDrawRound(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code) {
      player.send({ type: "ERROR", error_code: "NOT_IN_ROOM", message: "You are not in a room." });
      return;
    }

    const room = this.roomManager.findRoomByCode(code);
    if (!room) {
      player.send({ type: "ERROR", error_code: "ROOM_NOT_FOUND", message: "Room not found." });
      return;
    }

    if (player.playerId !== room.hostPlayerId) {
      player.send({ type: "ERROR", error_code: "NOT_HOST", message: "Only the host can draw a new round." });
      return;
    }

    const startRes = room.startPokerRound();
    if (!startRes.success) {
      player.send({
        type: "ERROR",
        error_code: startRes.error || "DRAW_FAILED",
        message: startRes.error === "DECKS_EXHAUSTED" ? "All 10 rounds have been completed." : "Failed to draw round.",
      });
      return;
    }
  }

  private handlePokerPickCards(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code) {
      player.send({ type: "ERROR", error_code: "NOT_IN_ROOM", message: "You are not in a room." });
      return;
    }

    const room = this.roomManager.findRoomByCode(code);
    if (!room) {
      player.send({ type: "ERROR", error_code: "ROOM_NOT_FOUND", message: "Room not found." });
      return;
    }

    const handSlot = typeof msg.hand_slot === "number" ? msg.hand_slot : null;
    const foreheadSlot = typeof msg.forehead_slot === "number" ? msg.forehead_slot : null;

    const res = room.handlePlayerPokerPick(player.playerId, handSlot, foreheadSlot);
    if (!res.success) {
      player.send({
        type: "ERROR",
        error_code: res.error || "PICK_FAILED",
        message: `Failed to pick cards: ${res.error}`,
      });
    }
  }

  private handlePokerBettingAction(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code) {
      player.send({ type: "ERROR", error_code: "NOT_IN_ROOM", message: "You are not in a room." });
      return;
    }

    const room = this.roomManager.findRoomByCode(code);
    if (!room) {
      player.send({ type: "ERROR", error_code: "ROOM_NOT_FOUND", message: "Room not found." });
      return;
    }

    if (!room.pokerMatch || !room.pokerMatch.bettingManager.bettingPhaseActive) {
      player.send({ type: "ERROR", error_code: "BETTING_INACTIVE", message: "Betting phase is not active." });
      return;
    }

    if (!msg.action) {
      player.send({ type: "ERROR", error_code: "MISSING_ACTION", message: "Betting action must be specified." });
      return;
    }

    // Process action server-authoritatively
    const targetBet = typeof msg.target_bet === "number" ? msg.target_bet : 0;
    const result = room.pokerMatch.processBettingAction(player.playerId, msg.action, targetBet);

    if (!result.success) {
      player.send({
        type: "ERROR",
        error_code: result.error || "ILLEGAL_ACTION",
        message: `Illegal action ${msg.action}: ${result.error}`,
      });
      return;
    }

    // Broadcast action result
    room.broadcast({
      type: "POKER_ACTION_RESULT",
      action_result: {
        success: true,
        action: result.action,
        player_id: result.playerId,
        amount_added: result.amountAdded,
        target_bet: result.targetBet,
        is_round_complete: result.isRoundComplete,
        next_turn_player_id: result.nextTurnPlayerId,
      },
    });

    // Broadcast updated betting state (pot, balances, current turn)
    room.broadcast(room.pokerMatch.getPublicBettingPayload());

    // If betting completed, broadcast completion and resolve showdown
    if (result.isRoundComplete) {
      room.broadcast({
        type: "POKER_BETTING_COMPLETED",
        round: room.pokerMatch.round,
        total_pot: room.pokerMatch.bettingManager.totalPot,
        main_pot: room.pokerMatch.bettingManager.mainPot,
        side_pots: room.pokerMatch.bettingManager.sidePots,
      });

      // Authoritative P6 Showdown, Winner Determination & Pot Distribution
      room.resolvePokerShowdown();
    }
  }

  private handlePokerResetMatch(player: Player, msg: ClientMessage): void {
    const code = msg.room_code || player.currentRoomCode;
    if (!code) return;

    const room = this.roomManager.findRoomByCode(code);
    if (!room) return;

    if (player.playerId !== room.hostPlayerId) {
      player.send({ type: "ERROR", error_code: "NOT_HOST", message: "Only host can reset match." });
      return;
    }

    room.resetPokerMatch();
    room.broadcast({
      type: "POKER_MATCH_RESET",
      room_code: room.roomCode,
    });
  }
}
