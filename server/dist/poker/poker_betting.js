import { POKER_CONFIG } from "./poker_config.js";
export class PokerBettingManager {
    players = new Map();
    playerOrder = [];
    currentHighestBet = 0;
    minRaiseIncrement = POKER_CONFIG.MIN_OPENING_BET;
    currentTurnPlayerId = null;
    bettingPhaseActive = false;
    roundNumber = 0;
    anteDeductedThisRound = false;
    // Last action tracking
    lastActionPlayerId = null;
    lastActionType = null;
    lastActionAmount = null;
    // Pot calculation cache
    mainPot = 0;
    sidePots = [];
    potLayers = [];
    totalPot = 0;
    constructor(playerIds = [], startingChips = POKER_CONFIG.STARTING_CHIPS) {
        if (playerIds.length > 0) {
            this.initPlayers(playerIds, startingChips);
        }
    }
    initPlayers(playerIds, startingChips = POKER_CONFIG.STARTING_CHIPS) {
        this.players.clear();
        this.playerOrder = [...playerIds];
        this.roundNumber = 0;
        this.resetAllPotState();
        for (const pid of playerIds) {
            this.players.set(pid, {
                playerId: pid,
                startingBalance: startingChips,
                balance: startingChips,
                anteContribution: 0,
                roundBetContribution: 0,
                totalHandContribution: 0,
                isFolded: false,
                isAllIn: false,
                hasActedThisRound: false,
                isDisconnected: false,
            });
        }
    }
    /**
     * Starts a new round of betting:
     * 1. Collects ante exactly once per round.
     * 2. Resets round-specific bet contributions.
     * 3. Sets first active turn.
     */
    startRound(roundNum) {
        this.roundNumber = roundNum;
        this.currentHighestBet = 0;
        this.minRaiseIncrement = POKER_CONFIG.MIN_OPENING_BET;
        this.bettingPhaseActive = true;
        this.lastActionPlayerId = null;
        this.lastActionType = null;
        this.lastActionAmount = null;
        // Reset per-round betting flags
        for (const [, p] of this.players) {
            p.roundBetContribution = 0;
            p.totalHandContribution = 0;
            p.anteContribution = 0;
            p.startingBalance = p.balance;
            p.hasActedThisRound = false;
            // Do not reset isFolded / isAllIn if already folded/all-in from previous match state
        }
        // Deduct Ante (Idempotent guard)
        this.anteDeductedThisRound = false;
        this.collectAnte();
        this.calculatePots();
        this.assertInvariants();
        // Find first player to act
        this.currentTurnPlayerId = this.findNextEligiblePlayer(-1);
        // If only one or zero players can act, complete betting immediately
        if (this.checkBettingComplete()) {
            this.finishBettingPhase();
        }
        return { success: true };
    }
    /**
     * Deducts mandatory ante from every eligible player.
     */
    collectAnte() {
        if (this.anteDeductedThisRound) {
            return;
        }
        this.anteDeductedThisRound = true;
        for (const [, p] of this.players) {
            if (p.isFolded || p.balance <= 0) {
                if (p.balance === 0)
                    p.isAllIn = true;
                continue;
            }
            if (p.balance >= POKER_CONFIG.ANTE_AMOUNT) {
                p.balance -= POKER_CONFIG.ANTE_AMOUNT;
                p.anteContribution += POKER_CONFIG.ANTE_AMOUNT;
                p.totalHandContribution += POKER_CONFIG.ANTE_AMOUNT;
            }
            else {
                // Player has less than ante amount, contributes remaining and goes all-in
                const rem = p.balance;
                p.balance = 0;
                p.anteContribution += rem;
                p.totalHandContribution += rem;
                p.isAllIn = true;
            }
        }
    }
    /**
     * Processes a player betting action (FOLD, CHECK, CALL, RAISE, ALL_IN).
     */
    processAction(playerId, action, targetRaiseBet = 0) {
        if (!this.bettingPhaseActive) {
            return this.failResult(action, playerId, "BETTING_PHASE_NOT_ACTIVE");
        }
        if (this.currentTurnPlayerId !== playerId) {
            return this.failResult(action, playerId, "NOT_PLAYER_TURN");
        }
        const player = this.players.get(playerId);
        if (!player) {
            return this.failResult(action, playerId, "PLAYER_NOT_FOUND");
        }
        if (player.isFolded) {
            return this.failResult(action, playerId, "PLAYER_ALREADY_FOLDED");
        }
        if (player.isAllIn) {
            return this.failResult(action, playerId, "PLAYER_ALREADY_ALL_IN");
        }
        let amountAdded = 0;
        let newRoundBet = player.roundBetContribution;
        switch (action) {
            case "FOLD": {
                player.isFolded = true;
                player.hasActedThisRound = true;
                break;
            }
            case "CHECK": {
                if (player.roundBetContribution < this.currentHighestBet) {
                    return this.failResult(action, playerId, "CANNOT_CHECK_MUST_CALL_OR_FOLD");
                }
                player.hasActedThisRound = true;
                break;
            }
            case "CALL": {
                const toCall = this.currentHighestBet - player.roundBetContribution;
                if (toCall <= 0) {
                    // Effectively a check
                    player.hasActedThisRound = true;
                    break;
                }
                if (player.balance >= toCall) {
                    amountAdded = toCall;
                    player.balance -= toCall;
                    newRoundBet += toCall;
                    player.roundBetContribution = newRoundBet;
                    player.totalHandContribution += toCall;
                    player.hasActedThisRound = true;
                    if (player.balance === 0) {
                        player.isAllIn = true;
                    }
                }
                else {
                    // Insufficient chips to complete full call -> Automatic All-In
                    amountAdded = player.balance;
                    newRoundBet += amountAdded;
                    player.roundBetContribution = newRoundBet;
                    player.totalHandContribution += amountAdded;
                    player.balance = 0;
                    player.isAllIn = true;
                    player.hasActedThisRound = true;
                }
                break;
            }
            case "RAISE": {
                // targetRaiseBet is the desired total round contribution
                if (targetRaiseBet <= this.currentHighestBet) {
                    return this.failResult(action, playerId, "RAISE_MUST_EXCEED_CURRENT_BET");
                }
                const additionalNeeded = targetRaiseBet - player.roundBetContribution;
                if (additionalNeeded > player.balance) {
                    return this.failResult(action, playerId, "INSUFFICIENT_CHIPS_FOR_RAISE");
                }
                const raiseIncrement = targetRaiseBet - this.currentHighestBet;
                const isAllInRaise = additionalNeeded === player.balance;
                // Check minimum raise increment (unless going all-in)
                if (!isAllInRaise && raiseIncrement < this.minRaiseIncrement) {
                    return this.failResult(action, playerId, `MINIMUM_RAISE_IS_${this.minRaiseIncrement}`);
                }
                // Apply deduction
                amountAdded = additionalNeeded;
                player.balance -= additionalNeeded;
                newRoundBet = targetRaiseBet;
                player.roundBetContribution = newRoundBet;
                player.totalHandContribution += additionalNeeded;
                player.hasActedThisRound = true;
                if (isAllInRaise) {
                    player.isAllIn = true;
                }
                // Update highest bet
                this.currentHighestBet = targetRaiseBet;
                // If it was a full raise (or all-in raise >= min raise increment), update min increment
                // and re-open betting action for all other non-folded, non-all-in players
                if (raiseIncrement >= this.minRaiseIncrement) {
                    this.minRaiseIncrement = raiseIncrement;
                    this.reopenActionForOthers(playerId);
                }
                else if (isAllInRaise) {
                    // Short all-in: still gives players who now owe chips a chance to call/respond
                    this.reopenActionForUnderpayingOthers(playerId);
                }
                break;
            }
            case "ALL_IN": {
                if (player.balance <= 0) {
                    return this.failResult(action, playerId, "NO_CHIPS_TO_ALL_IN");
                }
                amountAdded = player.balance;
                const totalCandidate = player.roundBetContribution + amountAdded;
                player.balance = 0;
                player.isAllIn = true;
                player.roundBetContribution = totalCandidate;
                player.totalHandContribution += amountAdded;
                player.hasActedThisRound = true;
                newRoundBet = totalCandidate;
                if (totalCandidate > this.currentHighestBet) {
                    const inc = totalCandidate - this.currentHighestBet;
                    if (inc >= this.minRaiseIncrement) {
                        this.minRaiseIncrement = inc;
                        this.reopenActionForOthers(playerId);
                    }
                    else {
                        this.reopenActionForUnderpayingOthers(playerId);
                    }
                    this.currentHighestBet = totalCandidate;
                }
                break;
            }
        }
        this.lastActionPlayerId = playerId;
        this.lastActionType = action;
        this.lastActionAmount = amountAdded;
        this.calculatePots();
        this.assertInvariants();
        // Check if betting round is complete
        const isComplete = this.checkBettingComplete();
        if (isComplete) {
            this.finishBettingPhase();
            return {
                success: true,
                action,
                playerId,
                amountAdded,
                targetBet: newRoundBet,
                isRoundComplete: true,
                nextTurnPlayerId: null,
            };
        }
        // Advance turn to next eligible player
        const currentIndex = this.playerOrder.indexOf(playerId);
        this.currentTurnPlayerId = this.findNextEligiblePlayer(currentIndex);
        return {
            success: true,
            action,
            playerId,
            amountAdded,
            targetBet: newRoundBet,
            isRoundComplete: false,
            nextTurnPlayerId: this.currentTurnPlayerId,
        };
    }
    /**
     * Re-opens action for all non-folded, non-all-in players when a full raise occurs.
     */
    reopenActionForOthers(raiserId) {
        for (const [pid, p] of this.players) {
            if (pid !== raiserId && !p.isFolded && !p.isAllIn) {
                p.hasActedThisRound = false;
            }
        }
    }
    /**
     * Re-opens action only for players who currently owe chips.
     */
    reopenActionForUnderpayingOthers(raiserId) {
        for (const [pid, p] of this.players) {
            if (pid !== raiserId && !p.isFolded && !p.isAllIn) {
                if (p.roundBetContribution < this.currentHighestBet) {
                    p.hasActedThisRound = false;
                }
            }
        }
    }
    /**
     * Finds the next player in cyclic order who is not folded, not all-in, and not disconnected.
     */
    findNextEligiblePlayer(fromIndex) {
        const total = this.playerOrder.length;
        for (let i = 1; i <= total; i++) {
            const idx = (fromIndex + i) % total;
            const pid = this.playerOrder[idx];
            const p = this.players.get(pid);
            if (p && !p.isFolded && !p.isAllIn && !p.isDisconnected) {
                return pid;
            }
        }
        return null;
    }
    /**
     * Checks whether the current betting round is complete according to poker rules:
     * 1. Only one non-folded player remains; OR
     * 2. All remaining eligible players have acted AND matched the highest bet; OR
     * 3. All non-folded players are All-In.
     */
    checkBettingComplete() {
        const activeNonFolded = Array.from(this.players.values()).filter((p) => !p.isFolded);
        // Rule 1: Only one non-folded player remains (everyone else folded)
        if (activeNonFolded.length <= 1) {
            return true;
        }
        // Rule 3: All active non-folded players are all-in
        const playersCanAct = activeNonFolded.filter((p) => !p.isAllIn && !p.isDisconnected);
        if (playersCanAct.length === 0) {
            return true;
        }
        // If only one player can act and everyone else is all-in or folded, and that player has matched the highest bet
        if (playersCanAct.length === 1) {
            const solePlayer = playersCanAct[0];
            if (solePlayer.hasActedThisRound && solePlayer.roundBetContribution >= this.currentHighestBet) {
                return true;
            }
        }
        // Rule 2: Every player who can act has acted AND contributed equal to the highest bet
        for (const p of playersCanAct) {
            if (!p.hasActedThisRound) {
                return false;
            }
            if (p.roundBetContribution < this.currentHighestBet) {
                return false;
            }
        }
        return true;
    }
    finishBettingPhase() {
        this.bettingPhaseActive = false;
        this.currentTurnPlayerId = null;
        this.calculatePots();
        this.assertInvariants();
    }
    /**
     * Calculates main pot and layered side pots based on all players' totalHandContribution.
     * Folded contributions are kept in the pots, but folded players are strictly excluded from eligibility.
     */
    calculatePots() {
        this.totalPot = 0;
        this.mainPot = 0;
        this.sidePots = [];
        // Calculate total pot
        for (const [, p] of this.players) {
            this.totalPot += p.totalHandContribution;
        }
        if (this.totalPot === 0) {
            return;
        }
        // Collect distinct contribution thresholds from non-folded, contributing players
        const activeContenders = Array.from(this.players.values()).filter((p) => !p.isFolded && p.totalHandContribution > 0);
        // If no active contenders (or only 1 left), the remaining player gets the pot
        if (activeContenders.length <= 1) {
            this.mainPot = this.totalPot;
            return;
        }
        // Distinct thresholds sorted ascending
        const thresholds = Array.from(new Set(activeContenders.map((p) => p.totalHandContribution))).sort((a, b) => a - b);
        let prevLevel = 0;
        const potLayers = [];
        for (const level of thresholds) {
            const tierSize = level - prevLevel;
            if (tierSize <= 0)
                continue;
            let tierPot = 0;
            // All players (including folded) who contributed past prevLevel contribute to this tier
            for (const [, p] of this.players) {
                if (p.totalHandContribution > prevLevel) {
                    tierPot += Math.min(p.totalHandContribution - prevLevel, tierSize);
                }
            }
            // Eligible players are non-folded players whose contribution is at least this level
            const eligible = activeContenders.filter((p) => p.totalHandContribution >= level).map((p) => p.playerId);
            if (tierPot > 0 && eligible.length > 0) {
                potLayers.push({
                    potAmount: tierPot,
                    eligiblePlayerIds: eligible,
                });
            }
            prevLevel = level;
        }
        if (potLayers.length > 0) {
            this.potLayers = potLayers;
            this.mainPot = potLayers[0].potAmount;
            this.sidePots = potLayers.slice(1);
        }
        else {
            this.potLayers = [];
            this.mainPot = this.totalPot;
            this.sidePots = [];
        }
    }
    /**
     * Asserts mathematical invariants:
     * 1. Total pot === sum of all players' totalHandContribution.
     * 2. Starting balance === current balance + totalHandContribution.
     */
    assertInvariants() {
        let sumContrib = 0;
        for (const [, p] of this.players) {
            sumContrib += p.totalHandContribution;
            if (p.startingBalance !== p.balance + p.totalHandContribution) {
                throw new Error(`Invariant Violation for ${p.playerId}: starting (${p.startingBalance}) !== balance (${p.balance}) + contribution (${p.totalHandContribution})`);
            }
            if (p.balance < 0) {
                throw new Error(`Invariant Violation: ${p.playerId} has negative balance: ${p.balance}`);
            }
        }
        if (this.totalPot !== sumContrib) {
            throw new Error(`Invariant Violation: totalPot (${this.totalPot}) !== sum of contributions (${sumContrib})`);
        }
    }
    handleDisconnect(playerId) {
        const p = this.players.get(playerId);
        if (!p)
            return;
        p.isDisconnected = true;
        // If it was this player's turn, advance turn or finish
        if (this.currentTurnPlayerId === playerId) {
            const currentIndex = this.playerOrder.indexOf(playerId);
            this.currentTurnPlayerId = this.findNextEligiblePlayer(currentIndex);
            if (this.checkBettingComplete()) {
                this.finishBettingPhase();
            }
        }
    }
    handleReconnect(playerId) {
        const p = this.players.get(playerId);
        if (!p)
            return;
        p.isDisconnected = false;
    }
    resetAllPotState() {
        this.mainPot = 0;
        this.sidePots = [];
        this.potLayers = [];
        this.totalPot = 0;
        this.currentHighestBet = 0;
        this.minRaiseIncrement = POKER_CONFIG.MIN_OPENING_BET;
        this.currentTurnPlayerId = null;
        this.bettingPhaseActive = false;
        this.anteDeductedThisRound = false;
    }
    toPublicState() {
        const playerSummaries = {};
        for (const [pid, p] of this.players) {
            playerSummaries[pid] = {
                player_id: pid,
                balance: p.balance,
                round_bet: p.roundBetContribution,
                total_contribution: p.totalHandContribution,
                is_folded: p.isFolded,
                is_all_in: p.isAllIn,
                has_acted: p.hasActedThisRound,
            };
        }
        return {
            round: this.roundNumber,
            total_pot: this.totalPot,
            main_pot: this.mainPot,
            side_pots: this.sidePots,
            current_highest_bet: this.currentHighestBet,
            min_raise_increment: this.minRaiseIncrement,
            current_turn_player_id: this.currentTurnPlayerId,
            betting_active: this.bettingPhaseActive,
            last_action: this.lastActionPlayerId
                ? {
                    player_id: this.lastActionPlayerId,
                    action: this.lastActionType,
                    amount: this.lastActionAmount,
                }
                : null,
            players: playerSummaries,
        };
    }
    failResult(action, playerId, error) {
        return {
            success: false,
            action,
            playerId,
            amountAdded: 0,
            targetBet: 0,
            error,
            isRoundComplete: false,
            nextTurnPlayerId: this.currentTurnPlayerId,
        };
    }
}
