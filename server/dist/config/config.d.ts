export declare const CONFIG: {
    PORT: number;
    HEARTBEAT_INTERVAL_MS: number;
    CLIENT_TIMEOUT_MS: number;
    ROOM_CODE_ALPHABET: string;
    ROOM_CODE_LENGTH: number;
    VALID_MODES: readonly ["1v1", "2v2", "3v3"];
    MODE_CAPACITIES: Record<string, number>;
    MODE_GRID_SIZES: Record<string, number>;
    VALID_CHARACTERS: readonly ["mint", "peach", "sky"];
    DEFAULT_CHARACTER_ID: string;
    TEAM_RED: number;
    TEAM_BLUE: number;
};
