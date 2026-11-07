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
    constructor(playerId, displayName, ws, characterId = CONFIG.DEFAULT_CHARACTER_ID) {
        this.playerId = playerId;
        this.displayName = displayName.trim() || "Player";
        this.characterId = CONFIG.VALID_CHARACTERS.includes(characterId) ? characterId : CONFIG.DEFAULT_CHARACTER_ID;
        this.teamId = CONFIG.TEAM_RED;
        this.isReady = false;
        this.isHost = false;
        this.ws = ws;
    }
    toRecord() {
        return {
            player_id: this.playerId,
            display_name: this.displayName,
            team_id: this.teamId,
            character_id: this.characterId,
            is_host: this.isHost,
            is_ready: this.isReady,
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
