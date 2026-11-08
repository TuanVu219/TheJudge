import { generateRoomCode, normalizeRoomCode, isValidRoomCode } from "../utils/code_generator.js";
import { Room } from "./room.js";
export class ServerRoomManager {
    roomsByCode = new Map();
    createRoom(hostPlayer, roomName = "", maxPlayers = 2, visibility = "PRIVATE", gameMode = "1v1", desiredCode) {
        let code = null;
        if (desiredCode) {
            const norm = normalizeRoomCode(desiredCode);
            if (isValidRoomCode(norm) && !this.roomsByCode.has(norm)) {
                code = norm;
            }
        }
        if (!code) {
            code = generateRoomCode((c) => this.roomsByCode.has(c));
        }
        if (!code) {
            return { success: false, error_code: "CODE_GEN_FAILED", message: "Failed to generate unique room code." };
        }
        const room = new Room(code, hostPlayer, roomName, maxPlayers, visibility, gameMode);
        this.roomsByCode.set(code, room);
        return { success: true, room };
    }
    findRoomByCode(roomCode) {
        const norm = normalizeRoomCode(roomCode);
        if (!isValidRoomCode(norm)) {
            return null;
        }
        return this.roomsByCode.get(norm) || null;
    }
    closeRoom(roomCode) {
        const norm = normalizeRoomCode(roomCode);
        const room = this.roomsByCode.get(norm);
        if (!room) {
            return false;
        }
        for (const player of room.players.values()) {
            player.currentRoomCode = null;
        }
        room.status = "CLOSED";
        this.roomsByCode.delete(norm);
        return true;
    }
    getActiveRoomCount() {
        return this.roomsByCode.size;
    }
}
