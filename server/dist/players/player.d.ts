import type { WebSocket } from "ws";
export interface PlayerRecord {
    player_id: string;
    display_name: string;
    team_id: number;
    character_id: string;
    is_host: boolean;
    is_ready: boolean;
}
export declare class Player {
    playerId: string;
    displayName: string;
    characterId: string;
    teamId: number;
    isReady: boolean;
    isHost: boolean;
    currentRoomCode: string | null;
    ws: WebSocket;
    isAlive: boolean;
    constructor(playerId: string, displayName: string, ws: WebSocket, characterId?: string);
    toRecord(): PlayerRecord;
    send(message: Record<string, any>): void;
}
