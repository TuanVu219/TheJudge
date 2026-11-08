import type { PlayerRecord } from "../players/player.js";
export type ClientMessageType = "CONNECT_CLIENT" | "CREATE_ROOM" | "JOIN_ROOM" | "LEAVE_ROOM" | "UPDATE_TEAM" | "UPDATE_CHARACTER" | "UPDATE_NAME" | "TOGGLE_READY" | "START_MATCH" | "PLAYER_MOVE" | "CLAIM_TILE" | "REMATCH_REQUEST" | "PING" | "POKER_START_MATCH" | "POKER_DRAW_ROUND" | "POKER_RESET_MATCH" | "POKER_BETTING_ACTION" | "POKER_RECONNECT";
export type ServerMessageType = "CONNECTED" | "ROOM_STATE" | "MATCH_STARTED" | "ROOM_CLOSED" | "PLAYER_MOVED" | "TILE_CLAIMED" | "MATCH_RESET" | "ERROR" | "PONG" | "POKER_MATCH_INIT" | "POKER_PRIVATE_HAND" | "POKER_OPPONENT_FOREHEADS" | "POKER_ROUND_STATUS" | "POKER_MATCH_RESET" | "POKER_BETTING_STATE" | "POKER_ACTION_RESULT" | "POKER_BETTING_COMPLETED" | "POKER_RECONNECT_RESPONSE";
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
    mode?: string;
    max_players?: number;
    visibility?: string;
    team_id?: number;
    character_id?: string;
    position?: [number, number, number];
    velocity?: [number, number, number];
    rotation?: number;
    pitch?: number;
    col?: number;
    row?: number;
    action?: "FOLD" | "CHECK" | "CALL" | "RAISE" | "ALL_IN";
    target_bet?: number;
    action_id?: string;
    reconnect_token?: string;
}
export interface ServerMessage {
    type: ServerMessageType;
    client_id?: string;
    room?: RoomRecord;
    roster?: PlayerRecord[];
    room_code?: string;
    game_mode?: string;
    mode?: string;
    reason?: string;
    error_code?: string;
    message?: string;
    player_id?: string;
    position?: [number, number, number];
    velocity?: [number, number, number];
    rotation?: number;
    pitch?: number;
    col?: number;
    row?: number;
    team_id?: number;
    red_score?: number;
    blue_score?: number;
    reconnect_token?: string;
    seat_index?: number;
    round?: number;
    card?: number | null;
    history?: number[];
    cards?: Array<{
        player_id: string;
        card: number | null;
        history?: number[];
    }>;
    total_rounds?: number;
    is_exhausted?: boolean;
    version?: number;
    total_pot?: number;
    main_pot?: number;
    side_pots?: Array<{
        potAmount: number;
        eligiblePlayerIds: string[];
    }>;
    current_highest_bet?: number;
    min_raise_increment?: number;
    current_turn_player_id?: string | null;
    betting_active?: boolean;
    betting_phase_active?: boolean;
    last_action_player_id?: string | null;
    last_action_type?: string | null;
    last_action_amount?: number | null;
    last_action?: {
        player_id: string;
        action: string | null;
        amount: number | null;
    } | null;
    players?: Array<{
        player_id: string;
        seat_index: number;
        balance: number;
        round_bet: number;
        total_contribution: number;
        is_folded: boolean;
        is_all_in: boolean;
        has_acted: boolean;
        is_disconnected?: boolean;
    }>;
    players_state?: Record<string, any>;
    action_result?: {
        success: boolean;
        action: string;
        player_id: string;
        amount_added: number;
        target_bet: number;
        is_round_complete: boolean;
        next_turn_player_id: string | null;
    };
}
