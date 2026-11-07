import { Room } from "./room.js";
import type { Player } from "../players/player.js";
export declare class ServerRoomManager {
    private roomsByCode;
    createRoom(hostPlayer: Player, roomName?: string, maxPlayers?: number, visibility?: "PUBLIC" | "PRIVATE", gameMode?: string, desiredCode?: string): {
        success: boolean;
        room?: Room;
        error_code?: string;
        message?: string;
    };
    findRoomByCode(roomCode: string): Room | null;
    closeRoom(roomCode: string): boolean;
    getActiveRoomCount(): number;
}
