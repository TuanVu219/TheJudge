import { CONFIG } from "../config/config.js";
import { Player, type PlayerRecord } from "../players/player.js";
import type { RoomRecord, ServerMessage } from "../websocket/protocol.js";

export class Room {
  public roomId: string;
  public roomCode: string;
  public roomName: string;
  public hostPlayerId: string;
  public maxPlayers: number;
  public visibility: "PUBLIC" | "PRIVATE";
  public status: "WAITING" | "STARTED" | "CLOSED";
  public gameMode: string;
  public players: Map<string, Player> = new Map();
  public startedMatchRoster: PlayerRecord[] = [];
  public gridColumns: number = 6;
  public gridRows: number = 6;
  public gridTiles: number[] = [];
  public redScore: number = 0;
  public blueScore: number = 0;

  constructor(
    roomCode: string,
    hostPlayer: Player,
    roomName: string = "",
    maxPlayers: number = 2,
    visibility: "PUBLIC" | "PRIVATE" = "PRIVATE",
    gameMode: string = "1v1"
  ) {
    this.roomCode = roomCode;
    this.roomId = `room_${roomCode}`;
    this.roomName = roomName.trim() || `Room ${roomCode}`;
    this.hostPlayerId = hostPlayer.playerId;
    this.visibility = visibility;
    this.status = "WAITING";

    const cleanMode = gameMode.trim();
    if (cleanMode && CONFIG.VALID_MODES.includes(cleanMode as any)) {
      this.gameMode = cleanMode;
      this.maxPlayers = CONFIG.MODE_CAPACITIES[cleanMode] || maxPlayers;
    } else {
      this.gameMode = "";
      this.maxPlayers = maxPlayers;
    }

    hostPlayer.isHost = true;
    hostPlayer.teamId = CONFIG.TEAM_RED;
    hostPlayer.isReady = false;
    this.addPlayer(hostPlayer);
  }

  public addPlayer(player: Player): { success: boolean; error_code?: string; message?: string } {
    if (this.status !== "WAITING") {
      return { success: false, error_code: "ROOM_NOT_WAITING", message: "This room is no longer in the lobby." };
    }
    if (this.players.has(player.playerId)) {
      return { success: false, error_code: "DUPLICATE_PLAYER", message: "Player already in this room." };
    }
    if (this.players.size >= this.maxPlayers) {
      return { success: false, error_code: "ROOM_FULL", message: "This room has reached maximum capacity." };
    }

    // Auto-assign to team with fewer players
    if (player.playerId !== this.hostPlayerId) {
      player.teamId = this.getTeamWithSpace();
      player.isHost = false;
      player.isReady = false;
    }

    player.currentRoomCode = this.roomCode;
    this.players.set(player.playerId, player);
    return { success: true };
  }

  public removePlayer(playerId: string): { success: boolean; roomClosed: boolean } {
    const player = this.players.get(playerId);
    if (!player) {
      return { success: false, roomClosed: false };
    }

    player.currentRoomCode = null;
    this.players.delete(playerId);

    if (playerId === this.hostPlayerId) {
      this.status = "CLOSED";
      return { success: true, roomClosed: true };
    }

    return { success: true, roomClosed: false };
  }

  public updatePlayerTeam(playerId: string, targetTeamId: number): { success: boolean; error_code?: string; message?: string } {
    if (this.status !== "WAITING") {
      return { success: false, error_code: "ROOM_NOT_WAITING", message: "Cannot change team after match start." };
    }
    const player = this.players.get(playerId);
    if (!player) {
      return { success: false, error_code: "PLAYER_NOT_IN_ROOM", message: "Player not found in room." };
    }
    if (targetTeamId !== CONFIG.TEAM_RED && targetTeamId !== CONFIG.TEAM_BLUE) {
      return { success: false, error_code: "INVALID_TEAM", message: "Invalid team choice." };
    }
    if (player.teamId === targetTeamId) {
      return { success: true };
    }

    const teamCapacity = Math.floor(this.maxPlayers / 2);
    let targetTeamCount = 0;
    for (const p of this.players.values()) {
      if (p.teamId === targetTeamId) {
        targetTeamCount++;
      }
    }

    if (targetTeamCount >= teamCapacity) {
      return { success: false, error_code: "TEAM_FULL", message: "That team is already full." };
    }

    player.teamId = targetTeamId;
    return { success: true };
  }

  public updatePlayerCharacter(playerId: string, characterId: string): { success: boolean; error_code?: string; message?: string } {
    if (this.status !== "WAITING") {
      return { success: false, error_code: "ROOM_NOT_WAITING", message: "Cannot change character after match start." };
    }
    const player = this.players.get(playerId);
    if (!player) {
      return { success: false, error_code: "PLAYER_NOT_IN_ROOM", message: "Player not found in room." };
    }
    if (!CONFIG.VALID_CHARACTERS.includes(characterId as any)) {
      return { success: false, error_code: "INVALID_CHARACTER", message: "Invalid character choice." };
    }

    player.characterId = characterId;
    return { success: true };
  }

  public updatePlayerDisplayName(playerId: string, displayName: string): { success: boolean; error_code?: string; message?: string } {
    if (this.status !== "WAITING") {
      return { success: false, error_code: "ROOM_NOT_WAITING", message: "Cannot change name after match start." };
    }
    const player = this.players.get(playerId);
    if (!player) {
      return { success: false, error_code: "PLAYER_NOT_IN_ROOM", message: "Player not found in room." };
    }
    const clean = displayName.trim();
    if (!clean) {
      return { success: false, error_code: "INVALID_NAME", message: "Name cannot be empty." };
    }
    player.displayName = clean;
    return { success: true };
  }

  public togglePlayerReady(playerId: string): { success: boolean; is_ready?: boolean; error_code?: string; message?: string } {
    if (this.status !== "WAITING") {
      return { success: false, error_code: "ROOM_NOT_WAITING", message: "Cannot toggle ready after match start." };
    }
    const player = this.players.get(playerId);
    if (!player) {
      return { success: false, error_code: "PLAYER_NOT_IN_ROOM", message: "Player not found in room." };
    }

    player.isReady = !player.isReady;
    return { success: true, is_ready: player.isReady };
  }

  public validateStartMatch(requestingPlayerId: string): { success: boolean; error_code?: string; message?: string } {
    if (this.status !== "WAITING") {
      return { success: false, error_code: "ROOM_NOT_WAITING", message: "Match has already started or room is closed." };
    }
    if (this.hostPlayerId !== requestingPlayerId) {
      return { success: false, error_code: "HOST_ONLY", message: "Only the host can start the match." };
    }

    const playerCount = this.players.size;
    if (playerCount < 2) {
      return { success: false, error_code: "NOT_ENOUGH_PLAYERS", message: "At least 2 registered players are required." };
    }
    if (playerCount > this.maxPlayers) {
      return { success: false, error_code: "ROOM_OVER_CAPACITY", message: "Player count exceeds capacity." };
    }

    let redCount = 0;
    let blueCount = 0;
    let readyCount = 0;

    for (const p of this.players.values()) {
      if (p.teamId === CONFIG.TEAM_RED) redCount++;
      else if (p.teamId === CONFIG.TEAM_BLUE) blueCount++;
      if (p.isReady) readyCount++;
    }

    if (this.gameMode && CONFIG.VALID_MODES.includes(this.gameMode as any)) {
      const expectedCapacity = CONFIG.MODE_CAPACITIES[this.gameMode];
      const targetPerTeam = Math.floor(expectedCapacity / 2);
      if (playerCount !== expectedCapacity) {
        return { success: false, error_code: "ROOM_NOT_FULL", message: `The room must be full (${expectedCapacity} players) before starting.` };
      }
      if (redCount !== targetPerTeam || blueCount !== targetPerTeam) {
        return { success: false, error_code: "TEAMS_NOT_EQUAL", message: `Both teams must have exactly ${targetPerTeam} players.` };
      }
    } else {
      if (redCount < 1 || blueCount < 1) {
        return { success: false, error_code: "BOTH_TEAMS_REQUIRED", message: "At least one player must be on each team." };
      }
    }

    if (readyCount !== playerCount) {
      return { success: false, error_code: "PLAYERS_NOT_READY", message: "Every player must be READY before starting." };
    }

    return { success: true };
  }

  public startMatch(requestingPlayerId: string): { success: boolean; error_code?: string; message?: string; roster?: PlayerRecord[] } {
    const val = this.validateStartMatch(requestingPlayerId);
    if (!val.success) {
      return val;
    }

    this.gridColumns = CONFIG.MODE_GRID_SIZES[this.gameMode] || 6;
    this.gridRows = this.gridColumns;
    this.gridTiles = new Array(this.gridColumns * this.gridRows).fill(0);
    this.redScore = 0;
    this.blueScore = 0;

    this.startedMatchRoster = Array.from(this.players.values()).map((p) => p.toRecord());
    this.status = "STARTED";
    return { success: true, roster: this.startedMatchRoster };
  }

  public claimTile(playerId: string, col: number, row: number): { success: boolean; redScore: number; blueScore: number; teamId: number } | null {
    if (this.status !== "STARTED") return null;
    const player = this.players.get(playerId);
    if (!player) return null;
    if (col < 0 || col >= this.gridColumns || row < 0 || row >= this.gridRows) return null;

    const index = row * this.gridColumns + col;
    const currentOwner = this.gridTiles[index];
    const targetTeam = player.teamId;

    if (currentOwner === targetTeam) {
      return null;
    }

    if (currentOwner === CONFIG.TEAM_RED) {
      this.redScore = Math.max(0, this.redScore - 1);
    } else if (currentOwner === CONFIG.TEAM_BLUE) {
      this.blueScore = Math.max(0, this.blueScore - 1);
    }

    this.gridTiles[index] = targetTeam;
    if (targetTeam === CONFIG.TEAM_RED) {
      this.redScore++;
    } else if (targetTeam === CONFIG.TEAM_BLUE) {
      this.blueScore++;
    }

    return {
      success: true,
      redScore: this.redScore,
      blueScore: this.blueScore,
      teamId: targetTeam,
    };
  }

  public resetMatch(): void {
    this.status = "WAITING";
    this.gridTiles = [];
    this.redScore = 0;
    this.blueScore = 0;
    this.startedMatchRoster = [];
    for (const p of this.players.values()) {
      p.isReady = false;
    }
  }

  public getTeamWithSpace(): number {
    let redCount = 0;
    let blueCount = 0;
    for (const p of this.players.values()) {
      if (p.teamId === CONFIG.TEAM_RED) redCount++;
      else if (p.teamId === CONFIG.TEAM_BLUE) blueCount++;
    }
    return redCount <= blueCount ? CONFIG.TEAM_RED : CONFIG.TEAM_BLUE;
  }

  public broadcast(message: ServerMessage): void {
    const payload = JSON.stringify(message);
    for (const p of this.players.values()) {
      if (p.ws.readyState === p.ws.OPEN) {
        try {
          p.ws.send(payload);
        } catch (err) {
          console.error(`Failed broadcast to player ${p.playerId}:`, err);
        }
      }
    }
  }

  public broadcastExcept(excludePlayerId: string, message: ServerMessage): void {
    const payload = JSON.stringify(message);
    for (const p of this.players.values()) {
      if (p.playerId !== excludePlayerId && p.ws.readyState === p.ws.OPEN) {
        try {
          p.ws.send(payload);
        } catch (err) {
          console.error(`Failed broadcast to player ${p.playerId}:`, err);
        }
      }
    }
  }

  public broadcastRoomState(): void {
    this.broadcast({
      type: "ROOM_STATE",
      room: this.toRecord(),
    });
  }

  public toRecord(): RoomRecord {
    return {
      room_id: this.roomId,
      room_code: this.roomCode,
      room_name: this.roomName,
      host_player_id: this.hostPlayerId,
      max_players: this.maxPlayers,
      visibility: this.visibility,
      status: this.status,
      game_mode: this.gameMode,
      players: Array.from(this.players.values()).map((p) => p.toRecord()),
      started_match_roster: this.startedMatchRoster,
    };
  }
}

