import { generateRoomCode, normalizeRoomCode, isValidRoomCode } from "../utils/code_generator.js";
import { Room } from "./room.js";
import type { Player } from "../players/player.js";

export class ServerRoomManager {
  private roomsByCode: Map<string, Room> = new Map();

  public createRoom(
    hostPlayer: Player,
    roomName: string = "",
    maxPlayers: number = 2,
    visibility: "PUBLIC" | "PRIVATE" = "PRIVATE",
    gameMode: string = "1v1",
    desiredCode?: string
  ): { success: boolean; room?: Room; error_code?: string; message?: string } {
    let code: string | null = null;
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

  public findRoomByCode(roomCode: string): Room | null {
    const norm = normalizeRoomCode(roomCode);
    if (!isValidRoomCode(norm)) {
      return null;
    }
    return this.roomsByCode.get(norm) || null;
  }

  public closeRoom(roomCode: string): boolean {
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

  public getActiveRoomCount(): number {
    return this.roomsByCode.size;
  }
}
