import type { WebSocket } from "ws";
import { CONFIG } from "../config/config.js";

export interface PlayerRecord {
  player_id: string;
  display_name: string;
  team_id: number;
  character_id: string;
  is_host: boolean;
  is_ready: boolean;
}

export class Player {
  public playerId: string;
  public displayName: string;
  public characterId: string;
  public teamId: number;
  public isReady: boolean;
  public isHost: boolean;
  public currentRoomCode: string | null = null;
  public ws: WebSocket;
  public isAlive: boolean = true;

  constructor(playerId: string, displayName: string, ws: WebSocket, characterId: string = CONFIG.DEFAULT_CHARACTER_ID) {
    this.playerId = playerId;
    this.displayName = displayName.trim() || "Player";
    this.characterId = CONFIG.VALID_CHARACTERS.includes(characterId as any) ? characterId : CONFIG.DEFAULT_CHARACTER_ID;
    this.teamId = CONFIG.TEAM_RED;
    this.isReady = false;
    this.isHost = false;
    this.ws = ws;
  }

  public toRecord(): PlayerRecord {
    return {
      player_id: this.playerId,
      display_name: this.displayName,
      team_id: this.teamId,
      character_id: this.characterId,
      is_host: this.isHost,
      is_ready: this.isReady,
    };
  }

  public send(message: Record<string, any>): void {
    if (this.ws.readyState === this.ws.OPEN) {
      try {
        this.ws.send(JSON.stringify(message));
      } catch (err) {
        console.error(`Failed to send message to player ${this.playerId}:`, err);
      }
    }
  }
}

