import { randomUUID } from "crypto";
import { CONFIG } from "../config/config.js";
export class Player {
    playerId;
    displayName;
    characterId;
    teamId;
    isReady;
    isHost;
    currentRoomCode = null;
    ws;
    isAlive = true;
    reconnectToken;
    seatIndex = -1;
    isDisconnected = false;
    disconnectTimeout = null;
    constructor(playerId, displayName, ws, characterId = CONFIG.DEFAULT_CHARACTER_ID) {
        this.playerId = playerId;
        this.displayName = displayName.trim() || "Player";
        this.characterId = CONFIG.VALID_CHARACTERS.includes(characterId) ? characterId : CONFIG.DEFAULT_CHARACTER_ID;
        this.teamId = CONFIG.TEAM_RED;
        this.isReady = false;
        this.isHost = false;
        this.ws = ws;
        this.reconnectToken = randomUUID();
    }
    toRecord() {
        return {
            player_id: this.playerId,
            display_name: this.displayName,
            team_id: this.teamId,
            character_id: this.characterId,
            is_host: this.isHost,
            is_ready: this.isReady,
            seat_index: this.seatIndex,
            is_disconnected: this.isDisconnected,
        };
    }
    send(message) {
        if (this.ws.readyState === this.ws.OPEN) {
            try {
                this.ws.send(JSON.stringify(message));
            }
            catch (err) {
                console.error(`Failed to send message to player ${this.playerId}:`, err);
            }
        }
    }
}
