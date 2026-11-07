export const CONFIG = {
  PORT: process.env.PORT ? parseInt(process.env.PORT, 10) : 8080,
  HEARTBEAT_INTERVAL_MS: 15000,
  CLIENT_TIMEOUT_MS: 30000,
  ROOM_CODE_ALPHABET: "ABCDEFGHJKMNPQRSTUVWXYZ23456789",
  ROOM_CODE_LENGTH: 6,
  VALID_MODES: ["1v1", "2v2", "3v3"] as const,
  MODE_CAPACITIES: {
    "1v1": 2,
    "2v2": 4,
    "3v3": 6,
  } as Record<string, number>,
  MODE_GRID_SIZES: {
    "1v1": 6,
    "2v2": 8,
    "3v3": 10,
  } as Record<string, number>,
  VALID_CHARACTERS: ["mint", "peach", "sky", "lemon", "berry", "lavender"] as const,
  DEFAULT_CHARACTER_ID: "mint",
  TEAM_RED: 1,
  TEAM_BLUE: 2,
};

