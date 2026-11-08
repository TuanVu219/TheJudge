import { WebSocketServer } from "ws";
import { CONFIG } from "./config/config.js";
import { ServerRoomManager } from "./rooms/room_manager.js";
import { WebSocketHandler } from "./websocket/handler.js";
const roomManager = new ServerRoomManager();
const handler = new WebSocketHandler(roomManager);
const wss = new WebSocketServer({ port: CONFIG.PORT, host: "0.0.0.0" }, () => {
    console.log(`[TheJudge Server] WebSocket server listening on ws://0.0.0.0:${CONFIG.PORT}`);
});
wss.on("connection", (ws) => {
    handler.handleConnection(ws);
});
// Periodic heartbeat
const heartbeat = setInterval(() => {
    // ping / prune logic if desired
}, CONFIG.HEARTBEAT_INTERVAL_MS);
process.on("SIGINT", () => {
    clearInterval(heartbeat);
    wss.close(() => {
        console.log("[TheJudge Server] Server closed.");
        process.exit(0);
    });
});
process.on("SIGTERM", () => {
    clearInterval(heartbeat);
    wss.close(() => {
        console.log("[TheJudge Server] Server closed.");
        process.exit(0);
    });
});
