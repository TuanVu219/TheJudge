import { Player } from "../players/player.js";
export class WebSocketHandler {
    roomManager;
    playersByWs = new Map();
    nextClientId = 1;
    constructor(roomManager) {
        this.roomManager = roomManager;
    }
    handleConnection(ws) {
        const defaultId = `player_${this.nextClientId++}`;
        const player = new Player(defaultId, "Player", ws);
        this.playersByWs.set(ws, player);
        // Send connection ack
        player.send({
            type: "CONNECTED",
            client_id: player.playerId,
        });
        ws.on("message", (data) => {
            this.handleMessage(ws, data);
        });
        ws.on("close", () => {
            this.handleDisconnect(ws);
        });
        ws.on("error", (err) => {
            console.error(`WebSocket error for player ${player.playerId}:`, err);
        });
    }
    handleDisconnect(ws) {
        const player = this.playersByWs.get(ws);
        if (!player)
            return;
        if (player.currentRoomCode) {
            const room = this.roomManager.findRoomByCode(player.currentRoomCode);
            if (room) {
                const { roomClosed } = room.removePlayer(player.playerId);
                if (roomClosed) {
                    room.broadcast({
                        type: "ROOM_CLOSED",
                        room_code: room.roomCode,
                        reason: "The host disconnected.",
                    });
                    this.roomManager.closeRoom(room.roomCode);
                }
                else {
                    room.broadcastRoomState();
                }
            }
        }
        this.playersByWs.delete(ws);
    }
    handleMessage(ws, raw) {
        const player = this.playersByWs.get(ws);
        if (!player)
            return;
        let msg;
        try {
            msg = JSON.parse(raw.toString());
        }
        catch {
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
            default:
                player.send({ type: "ERROR", error_code: "UNKNOWN_MESSAGE", message: `Unknown message type: ${msg.type}` });
                break;
        }
    }
    handleCreateRoom(player, msg) {
        if (player.currentRoomCode) {
            player.send({ type: "ERROR", error_code: "ALREADY_IN_ROOM", message: "Leave current room before creating a new one." });
            return;
        }
        if (msg.display_name?.trim()) {
            player.displayName = msg.display_name.trim();
        }
        if (msg.character_id) {
            player.characterId = msg.character_id;
        }
        const maxPlayers = msg.max_players || 2;
        const visibility = (msg.visibility?.toUpperCase() === "PUBLIC" ? "PUBLIC" : "PRIVATE");
        const gameMode = msg.game_mode || "1v1";
        const roomName = msg.room_name || "";
        const res = this.roomManager.createRoom(player, roomName, maxPlayers, visibility, gameMode, msg.room_code);
        if (!res.success || !res.room) {
            player.send({ type: "ERROR", error_code: res.error_code || "CREATE_FAILED", message: res.message || "Failed to create room." });
            return;
        }
        res.room.broadcastRoomState();
    }
    handleJoinRoom(player, msg) {
        if (!msg.room_code) {
            player.send({ type: "ERROR", error_code: "MISSING_ROOM_CODE", message: "Enter a room code." });
            return;
        }
        const room = this.roomManager.findRoomByCode(msg.room_code);
        if (!room) {
            player.send({ type: "ERROR", error_code: "ROOM_NOT_FOUND", message: "No room with that code exists." });
            return;
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
    handleLeaveRoom(player, msg) {
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
        const { roomClosed } = room.removePlayer(player.playerId);
        if (roomClosed) {
            room.broadcast({
                type: "ROOM_CLOSED",
                room_code: room.roomCode,
                reason: "The host left the room.",
            });
            this.roomManager.closeRoom(room.roomCode);
        }
        else {
            room.broadcastRoomState();
        }
    }
    handleUpdateTeam(player, msg) {
        const code = msg.room_code || player.currentRoomCode;
        if (!code)
            return;
        const room = this.roomManager.findRoomByCode(code);
        if (!room)
            return;
        const res = room.updatePlayerTeam(player.playerId, msg.team_id || 1);
        if (!res.success) {
            player.send({ type: "ERROR", error_code: res.error_code || "TEAM_UPDATE_FAILED", message: res.message || "Failed to update team." });
            return;
        }
        room.broadcastRoomState();
    }
    handleUpdateCharacter(player, msg) {
        const code = msg.room_code || player.currentRoomCode;
        if (!code)
            return;
        const room = this.roomManager.findRoomByCode(code);
        if (!room)
            return;
        const res = room.updatePlayerCharacter(player.playerId, msg.character_id || "mint");
        if (!res.success) {
            player.send({ type: "ERROR", error_code: res.error_code || "CHAR_UPDATE_FAILED", message: res.message || "Failed to update character." });
            return;
        }
        room.broadcastRoomState();
    }
    handleUpdateName(player, msg) {
        const code = msg.room_code || player.currentRoomCode;
        if (!code)
            return;
        const room = this.roomManager.findRoomByCode(code);
        if (!room)
            return;
        const res = room.updatePlayerDisplayName(player.playerId, msg.display_name || "Player");
        if (!res.success) {
            player.send({ type: "ERROR", error_code: res.error_code || "NAME_UPDATE_FAILED", message: res.message || "Failed to update name." });
            return;
        }
        room.broadcastRoomState();
    }
    handleToggleReady(player, msg) {
        const code = msg.room_code || player.currentRoomCode;
        if (!code)
            return;
        const room = this.roomManager.findRoomByCode(code);
        if (!room)
            return;
        const res = room.togglePlayerReady(player.playerId);
        if (!res.success) {
            player.send({ type: "ERROR", error_code: res.error_code || "READY_TOGGLE_FAILED", message: res.message || "Failed to toggle ready." });
            return;
        }
        room.broadcastRoomState();
    }
    handleStartMatch(player, msg) {
        const code = msg.room_code || player.currentRoomCode;
        if (!code)
            return;
        const room = this.roomManager.findRoomByCode(code);
        if (!room)
            return;
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
        });
    }
    handlePlayerMove(player, msg) {
        const code = msg.room_code || player.currentRoomCode;
        if (!code)
            return;
        const room = this.roomManager.findRoomByCode(code);
        if (!room || room.status !== "STARTED")
            return;
        room.broadcastExcept(player.playerId, {
            type: "PLAYER_MOVED",
            player_id: player.playerId,
            position: msg.position,
            velocity: msg.velocity,
            rotation: msg.rotation,
        });
    }
    handleClaimTile(player, msg) {
        const code = msg.room_code || player.currentRoomCode;
        if (!code || msg.col === undefined || msg.row === undefined)
            return;
        const room = this.roomManager.findRoomByCode(code);
        if (!room || room.status !== "STARTED")
            return;
        const result = room.claimTile(player.playerId, msg.col, msg.row);
        if (!result)
            return;
        room.broadcast({
            type: "TILE_CLAIMED",
            col: msg.col,
            row: msg.row,
            team_id: result.teamId,
            red_score: result.redScore,
            blue_score: result.blueScore,
        });
    }
    handleRematch(player, msg) {
        const code = msg.room_code || player.currentRoomCode;
        if (!code)
            return;
        const room = this.roomManager.findRoomByCode(code);
        if (!room)
            return;
        room.resetMatch();
        room.broadcast({
            type: "MATCH_RESET",
            room_code: room.roomCode,
        });
        room.broadcastRoomState();
    }
}
