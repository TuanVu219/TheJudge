export const POKER_CONFIG = {
  STARTING_CHIPS: 100,
  ANTE_AMOUNT: 1,
  MIN_OPENING_BET: 2,
  MAX_ROUNDS: 10,
} as const;

export type BettingActionType = "FOLD" | "CHECK" | "CALL" | "RAISE" | "ALL_IN";

