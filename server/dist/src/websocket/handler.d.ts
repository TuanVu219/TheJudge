import type { WebSocket } from "ws";
import { ServerRoomManager } from "../rooms/room_manager.js";
export declare class WebSocketHandler {
    private roomManager;
    private playersByWs;
    private nextClientId;
    constructor(roomManager: ServerRoomManager);
    handleConnection(ws: WebSocket): void;
    handleDisconnect(ws: WebSocket): void;
    private handleMessage;
    private handleCreateRoom;
    private handleJoinRoom;
    private handleLeaveRoom;
    private handleUpdateTeam;
    private handleUpdateCharacter;
    private handleUpdateName;
    private handleToggleReady;
    private handleStartMatch;
    private handlePlayerMove;
    private handleClaimTile;
    private handleRematch;
    private handlePokerStartMatch;
    private handlePokerReconnect;
    private handlePokerDrawRound;
    private handlePokerPickCards;
    private handlePokerBettingAction;
    private handlePokerResetMatch;
}
