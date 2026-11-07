import { Player, type PlayerRecord } from "../players/player.js";
import type { RoomRecord, ServerMessage } from "../websocket/protocol.js";
export declare class Room {
    roomId: string;
    roomCode: string;
    roomName: string;
    hostPlayerId: string;
    maxPlayers: number;
    visibility: "PUBLIC" | "PRIVATE";
    status: "WAITING" | "STARTED" | "CLOSED";
    gameMode: string;
    players: Map<string, Player>;
    startedMatchRoster: PlayerRecord[];
    gridColumns: number;
    gridRows: number;
    gridTiles: number[];
    redScore: number;
    blueScore: number;
    constructor(roomCode: string, hostPlayer: Player, roomName?: string, maxPlayers?: number, visibility?: "PUBLIC" | "PRIVATE", gameMode?: string);
    addPlayer(player: Player): {
        success: boolean;
        error_code?: string;
        message?: string;
    };
    removePlayer(playerId: string): {
        success: boolean;
        roomClosed: boolean;
    };
    updatePlayerTeam(playerId: string, targetTeamId: number): {
        success: boolean;
        error_code?: string;
        message?: string;
    };
    updatePlayerCharacter(playerId: string, characterId: string): {
        success: boolean;
        error_code?: string;
        message?: string;
    };
    updatePlayerDisplayName(playerId: string, displayName: string): {
        success: boolean;
        error_code?: string;
        message?: string;
    };
    togglePlayerReady(playerId: string): {
        success: boolean;
        is_ready?: boolean;
        error_code?: string;
        message?: string;
    };
    validateStartMatch(requestingPlayerId: string): {
        success: boolean;
        error_code?: string;
        message?: string;
    };
    startMatch(requestingPlayerId: string): {
        success: boolean;
        error_code?: string;
        message?: string;
        roster?: PlayerRecord[];
    };
    claimTile(playerId: string, col: number, row: number): {
        success: boolean;
        redScore: number;
        blueScore: number;
        teamId: number;
    } | null;
    resetMatch(): void;
    getTeamWithSpace(): number;
    broadcast(message: ServerMessage): void;
    broadcastExcept(excludePlayerId: string, message: ServerMessage): void;
    broadcastRoomState(): void;
    toRecord(): RoomRecord;
}
