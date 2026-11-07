import type { PlayerRecord } from "../players/player.js";

export type ClientMessageType =
  | "CONNECT_CLIENT"
  | "CREATE_ROOM"
  | "JOIN_ROOM"
  | "LEAVE_ROOM"
  | "UPDATE_TEAM"
  | "UPDATE_CHARACTER"
  | "UPDATE_NAME"
  | "TOGGLE_READY"
  | "START_MATCH"
  | "PLAYER_MOVE"
  | "CLAIM_TILE"
  | "REMATCH_REQUEST"
  | "PING";

export type ServerMessageType =
  | "CONNECTED"
  | "ROOM_STATE"
  | "MATCH_STARTED"
  | "ROOM_CLOSED"
  | "PLAYER_MOVED"
  | "TILE_CLAIMED"
  | "MATCH_RESET"
  | "ERROR"
  | "PONG";

export interface RoomRecord {
  room_id: string;
  room_code: string;
  room_name: string;
  host_player_id: string;
  max_players: number;
  visibility: string;
  status: "WAITING" | "STARTED" | "CLOSED";
  game_mode: string;
  players: PlayerRecord[];
  started_match_roster: PlayerRecord[];
}

export interface ClientMessage {
  type: ClientMessageType;
  player_id?: string;
  display_name?: string;
  room_code?: string;
  room_name?: string;
  game_mode?: string;
  max_players?: number;
  visibility?: string;
  team_id?: number;
  character_id?: string;
  position?: [number, number, number];
  velocity?: [number, number, number];
  rotation?: number;
  col?: number;
  row?: number;
}

export interface ServerMessage {
  type: ServerMessageType;
  client_id?: string;
  room?: RoomRecord;
  roster?: PlayerRecord[];
  room_code?: string;
  game_mode?: string;
  reason?: string;
  error_code?: string;
  message?: string;
  player_id?: string;
  position?: [number, number, number];
  velocity?: [number, number, number];
  rotation?: number;
  col?: number;
  row?: number;
  team_id?: number;
  red_score?: number;
  blue_score?: number;
}

