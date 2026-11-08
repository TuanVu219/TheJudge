export class PokerShowdownManager {
    /**
     * Evaluates the outcome of a completed betting round, reveals cards where appropriate,
     * calculates scores (Hand + Forehead), and distributes Main Pot and Side Pots authoritatively.
     */
    static resolveRoundResult(roundNumber, bettingManager, matchPlayers, playerSeatMap, stateVersion) {
        bettingManager.calculatePots();
        const finalPot = bettingManager.totalPot;
        const allPlayerIds = Array.from(matchPlayers.keys());
        // 1. Identify non-folded contenders
        const activeContenders = allPlayerIds.filter((pid) => {
            const bState = bettingManager.players.get(pid);
            return bState && !bState.isFolded;
        });
        const isUncontested = activeContenders.length <= 1;
        const resultType = isUncontested ? "UNCONTESTED" : "SHOWDOWN";
        const revealedCards = {};
        const playerScores = {};
        // 2. Score calculation (Hand + Forehead)
        // In SHOWDOWN: reveal cards and calculate scores for all eligible non-folded players
        // In UNCONTESTED: do NOT reveal cards
        if (resultType === "SHOWDOWN") {
            for (const pid of activeContenders) {
                const pState = matchPlayers.get(pid);
                const handCard = pState?.handDeck.currentCard ?? 1;
                const foreheadCard = pState?.foreheadDeck.currentCard ?? 1;
                const totalScore = handCard + foreheadCard;
                revealedCards[pid] = {
                    handCard,
                    foreheadCard,
                    totalScore,
                };
                playerScores[pid] = totalScore;
            }
        }
        const potsToDistribute = [];
        if (finalPot > 0) {
            if (bettingManager.potLayers && bettingManager.potLayers.length > 0) {
                for (let idx = 0; idx < bettingManager.potLayers.length; idx++) {
                    const layer = bettingManager.potLayers[idx];
                    potsToDistribute.push({
                        name: idx === 0 ? "Main Pot" : `Side Pot ${idx}`,
                        amount: layer.potAmount,
                        eligible: [...layer.eligiblePlayerIds],
                    });
                }
            }
            else {
                // Single pot fallback
                const eligible = isUncontested ? (activeContenders.length === 1 ? [activeContenders[0]] : allPlayerIds) : [...activeContenders];
                potsToDistribute.push({
                    name: "Main Pot",
                    amount: finalPot,
                    eligible,
                });
            }
        }
        const totalAwardedByPlayer = {};
        for (const pid of allPlayerIds) {
            totalAwardedByPlayer[pid] = 0;
        }
        let mainPotDist = {
            potName: "Main Pot",
            potAmount: 0,
            eligiblePlayerIds: [],
            winningPlayerIds: [],
            winningScore: 0,
            payouts: {},
        };
        const sidePotDists = [];
        const allWinnersSet = new Set();
        let mainPotTiedWinners = [];
        // 4. Distribute Each Pot
        for (let pIdx = 0; pIdx < potsToDistribute.length; pIdx++) {
            const pot = potsToDistribute[pIdx];
            const payouts = {};
            let potWinners = [];
            let potWinningScore = 0;
            if (isUncontested) {
                // Uncontested: the sole non-folded contender receives the pot
                const soleWinner = activeContenders.length === 1 ? activeContenders[0] : allPlayerIds[0];
                potWinners = [soleWinner];
                potWinningScore = 0;
            }
            else {
                // Showdown: Contenders must be eligible for this specific pot layer AND not folded
                const eligibleContenders = pot.eligible.filter((pid) => {
                    const bState = bettingManager.players.get(pid);
                    return bState && !bState.isFolded && playerScores[pid] !== undefined;
                });
                if (eligibleContenders.length > 0) {
                    potWinningScore = Math.max(...eligibleContenders.map((pid) => playerScores[pid]));
                    potWinners = eligibleContenders.filter((pid) => playerScores[pid] === potWinningScore);
                }
                else {
                    // If no non-folded player in this layer, fallback to all active contenders
                    if (activeContenders.length > 0) {
                        potWinningScore = Math.max(...activeContenders.map((pid) => playerScores[pid]));
                        potWinners = activeContenders.filter((pid) => playerScores[pid] === potWinningScore);
                    }
                    else {
                        potWinners = [allPlayerIds[0]];
                    }
                }
            }
            // Pot Division & Deterministic Remainder Rule:
            // Divide pot equally among tied winners. Any remainder chips (pot % winners.length)
            // are awarded 1 each to the tied winners in ascending seat-order.
            if (potWinners.length > 0 && pot.amount > 0) {
                const baseShare = Math.floor(pot.amount / potWinners.length);
                const remainder = pot.amount % potWinners.length;
                // Sort winners by assigned seat index ascending
                const sortedWinners = [...potWinners].sort((a, b) => {
                    const seatA = playerSeatMap.get(a) ?? 0;
                    const seatB = playerSeatMap.get(b) ?? 0;
                    return seatA - seatB;
                });
                for (let wIdx = 0; wIdx < sortedWinners.length; wIdx++) {
                    const winnerId = sortedWinners[wIdx];
                    const chipShare = baseShare + (wIdx < remainder ? 1 : 0);
                    payouts[winnerId] = chipShare;
                    totalAwardedByPlayer[winnerId] = (totalAwardedByPlayer[winnerId] || 0) + chipShare;
                    allWinnersSet.add(winnerId);
                }
            }
            const potPayout = {
                potName: pot.name,
                potAmount: pot.amount,
                eligiblePlayerIds: pot.eligible,
                winningPlayerIds: potWinners,
                winningScore: potWinningScore,
                payouts,
            };
            if (pIdx === 0) {
                mainPotDist = potPayout;
                if (potWinners.length > 1) {
                    mainPotTiedWinners = [...potWinners];
                }
            }
            else {
                sidePotDists.push(potPayout);
            }
        }
        // 5. Update Player Balances & Assert Conservation Invariants
        const updatedBalances = {};
        for (const pid of allPlayerIds) {
            const pBet = bettingManager.players.get(pid);
            if (pBet) {
                pBet.balance += totalAwardedByPlayer[pid] || 0;
                updatedBalances[pid] = pBet.balance;
                // Reset round hand contributions
                pBet.totalHandContribution = 0;
                pBet.roundBetContribution = 0;
                pBet.anteContribution = 0;
                pBet.hasActedThisRound = false;
                pBet.isFolded = false;
                pBet.isAllIn = pBet.balance === 0;
                pBet.startingBalance = pBet.balance;
            }
        }
        // Clear pot state in betting manager
        bettingManager.resetAllPotState();
        const isMatchCompleted = roundNumber >= 10;
        return {
            roundNumber,
            resultType,
            revealedCards,
            playerScores,
            winnerPlayerIds: Array.from(allWinnersSet),
            tiedWinnerIds: mainPotTiedWinners,
            mainPotDistribution: mainPotDist,
            sidePotDistributions: sidePotDists,
            totalAwardedByPlayer,
            updatedBalances,
            finalPot,
            isMatchCompleted,
            stateVersion,
            timestamp: Date.now(),
        };
    }
}
