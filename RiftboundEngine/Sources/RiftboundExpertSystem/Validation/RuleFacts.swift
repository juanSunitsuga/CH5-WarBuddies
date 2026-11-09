import Foundation

/// The working memory: everything the rule base is allowed to ask about a
/// proposed action.
///
/// This is the one place that reads a `GameState`. The rules never touch the
/// state directly — they name facts, and this decides what each fact is
/// worth right now. That split is what lets a rule change without a code
/// change: a new rule can only be written against facts that already exist,
/// and adding a fact is the only reason this file has to grow.
///
/// Facts are flat values on purpose. Anything that needed a loop to work out
/// — which of several moving units is the one that broke the rule — is
/// resolved here into a single fact plus an operand, because "which unit"
/// is an observation about the board, not a rule.
struct RuleFacts {
    /// Which group of rules applies. `"unsupported"` is a real kind, not an
    /// error: the rule base states that those actions are not modeled.
    let actionKind: String
    let values: [String: FactValue]
    let operands: FailureOperands
}

/// A fact's value. Five shapes, because that is what the conditions in
/// `RuleCondition` can compare.
enum FactValue: Equatable {
    case bool(Bool)
    case number(Int)
    case text(String)
    case texts(Set<String>)
}

/// Board values a failure needs to carry, which no condition can see.
///
/// Separate from the facts deliberately. A rule decides *whether* something
/// is illegal from facts alone; these only fill in the detail of the report,
/// so letting rules read them would blur which half of the system is which.
struct FailureOperands {
    var winner: PlayerID?
    var phase: Phase?
    var action: GameAction?
    var cardID: ObjectID?
    var playDestination: PlayDestination?
    var missingUnit: ObjectID?
    var exhaustedUnit: ObjectID?
    var illegalMove: (from: Location, to: Location)?
    var destinationBattlefield: BattlefieldID?
    var domain: Domain?
}

// MARK: - Derivation

extension RuleFacts {

    /// Reads the board once, into the facts the rule base names.
    static func derive(
        for action: GameAction,
        in state: GameState,
        proposedBy player: PlayerID,
        ruleBase: RuleBase
    ) -> RuleFacts {
        var values: [String: FactValue] = [:]
        var operands = FailureOperands()

        // Facts every rule may use.
        values["gameWon"] = .bool(state.winner != nil)
        values["phase"] = .text(phaseName(state.phase))
        values["phaseStep"] = .text(phaseStepName(state.phase))
        values["turnState"] = .text(turnStateName(state.turnState))
        values["hasPriority"] = .bool(state.turnState.playerWithPriority(turnPlayer: state.turnPlayer) == player)
        values["isTurnPlayer"] = .bool(state.turnPlayer == player)
        operands.winner = state.winner
        operands.phase = state.phase
        operands.action = action

        switch action {
        case .play(let cardID, let destination, _, let observedExhaustedRuneCount):
            operands.cardID = cardID
            operands.playDestination = destination
            values["destinationKind"] = .text(playDestinationName(destination))
            if case .battlefield(let battlefieldID) = destination {
                operands.destinationBattlefield = battlefieldID
                values["otherControllersAtDestination"] = .number(
                    otherControllers(at: .battlefield(battlefieldID), in: state, besides: player)
                )
            }
            if let observedExhaustedRuneCount {
                values["observedRuneCount"] = .number(observedExhaustedRuneCount)
            }

            let card = state.zones[player]?.hand.first { $0.id == cardID }
            values["cardInHand"] = .bool(card != nil)
            if let card {
                values["cardType"] = .text(cardTypeName(card.type))
                values["keywords"] = .texts(Set(card.keywords.map(keywordName)))
                values["energyCost"] = .number(card.cost.energy)
                values["powerCost"] = .number(card.cost.powerCost)
                values["availableEnergy"] = .number(state.zones[player]?.runePool.energy ?? 0)
                values["availablePower"] = .number(
                    payablePower(for: card.cost, from: state.zones[player]?.runePool.power ?? [])
                )
            }
            return RuleFacts(actionKind: "play", values: values, operands: operands)

        case .standardMove(let unitIDs, let destination):
            values["destinationKind"] = .text(locationName(destination))
            if case .battlefield(let battlefieldID) = destination {
                operands.destinationBattlefield = battlefieldID
                values["otherControllersAtDestination"] = .number(
                    otherControllers(at: destination, in: state, besides: player)
                )
            }
            let violation = firstMoveViolation(
                unitIDs, to: destination, in: state, ruleBase: ruleBase, operands: &operands
            )
            values["moveViolation"] = .text(violation)
            return RuleFacts(actionKind: "standardMove", values: values, operands: operands)

        case .pass:
            return RuleFacts(actionKind: "pass", values: values, operands: operands)

        case .endTurn:
            return RuleFacts(actionKind: "endTurn", values: values, operands: operands)

        case .recycleRune(let domain):
            operands.domain = domain
            values["runeOfDomainAvailable"] = .bool(
                state.runes.values.contains { $0.controller == player && $0.domain == domain }
            )
            return RuleFacts(actionKind: "recycleRune", values: values, operands: operands)

        case .exhaust(let objects):
            // 157.2.a's `[T]: Add [1]` is the Rune's own activated ability,
            // so exhausting your own Runes is discretionary. Exhausting
            // anything else stays a Limited Action (592) — an opponent's
            // Unit doesn't exhaust because you decided so. Which of the two
            // this is, is a fact; what each one then requires is a rule.
            values["isOwnRuneExhaust"] = .bool(
                !objects.isEmpty && objects.allSatisfy { state.runes[$0]?.controller == player }
            )
            values["limitedActionAuthorized"] = .bool(
                state.pendingLimitedActions[player]?.contains(action) == true
            )
            return RuleFacts(actionKind: "exhaust", values: values, operands: operands)

        case .draw, .ready, .recycle, .discard, .stun, .reveal,
             .counter, .buff, .banish, .kill, .add, .channel, .burnOut:
            values["limitedActionAuthorized"] = .bool(
                state.pendingLimitedActions[player]?.contains(action) == true
            )
            return RuleFacts(actionKind: "limitedAction", values: values, operands: operands)

        case .activateAbility, .hide, .invite:
            return RuleFacts(actionKind: "unsupported", values: values, operands: operands)
        }
    }
}

// MARK: - Board questions

private extension RuleFacts {

    /// Rule 140: walks the moving units in the order they were proposed and
    /// names the first thing wrong, so a mixed list reports the same reason
    /// a player would notice first.
    static func firstMoveViolation(
        _ unitIDs: [ObjectID],
        to destination: Location,
        in state: GameState,
        ruleBase: RuleBase,
        operands: inout FailureOperands
    ) -> String {
        for unitID in unitIDs {
            guard let unit = state.units[unitID] else {
                operands.missingUnit = unitID
                return "missingUnit"
            }
            guard !unit.isExhausted else {
                operands.exhaustedUnit = unitID
                return "exhaustedUnit"
            }
            guard permitsMove(from: unit.location, to: destination, unit: unit, ruleBase: ruleBase) else {
                operands.illegalMove = (from: unit.location, to: destination)
                return "illegalDestination"
            }
        }
        return "none"
    }

    /// Matches one unit's move against rule 140.4's table in the knowledge
    /// base. No Origin → Destination pair is written in Swift: a row that
    /// isn't in the file isn't a legal move.
    static func permitsMove(
        from origin: Location,
        to destination: Location,
        unit: Unit,
        ruleBase: RuleBase
    ) -> Bool {
        let keywords = Set((unit.printedKeywords + unit.grantedKeywords).map(keywordName))
        return ruleBase.moveDestinations.contains { row in
            guard row.from == locationName(origin), row.to == locationName(destination) else {
                return false
            }
            if row.distinctPlaces == true, origin == destination {
                return false
            }
            if let required = row.requiresKeyword, !keywords.contains(required) {
                return false
            }
            return true
        }
    }

    /// Rules 610.2.a/623.2: how many players other than the proposer
    /// already have units at a place.
    static func otherControllers(at location: Location, in state: GameState, besides player: PlayerID) -> Int {
        Set(
            state.units.values
                .filter { $0.location == location }
                .map(\.controller)
        )
        .subtracting([player])
        .count
    }

    /// Rule 560–561/130.3: how much of the Rune Pool's Power can actually
    /// pay this cost. Non-matching entries are real, spendable Power for
    /// some other card, so they are excluded rather than counted.
    static func payablePower(for cost: Cost, from pool: [PowerType]) -> Int {
        pool.filter { powerType in
            switch powerType {
            case .universal: return true
            case .domain(let domain): return cost.eligibleDomains.contains(domain)
            }
        }
        .count
    }
}

// MARK: - Names the rule base uses

private extension RuleFacts {

    static func phaseName(_ phase: Phase) -> String {
        switch phase {
        case .startOfTurn: return "startOfTurn"
        case .action: return "action"
        case .endOfTurn: return "endOfTurn"
        }
    }

    /// The finer grain, so a rule can single out one step without the
    /// knowledge base needing a new fact added in code.
    static func phaseStepName(_ phase: Phase) -> String {
        switch phase {
        case .startOfTurn(.awaken): return "awaken"
        case .startOfTurn(.beginning): return "beginning"
        case .startOfTurn(.channel): return "channel"
        case .startOfTurn(.draw): return "draw"
        case .action: return "action"
        case .endOfTurn(.ending): return "ending"
        case .endOfTurn(.expiration): return "expiration"
        case .endOfTurn(.cleanup): return "cleanup"
        }
    }

    static func turnStateName(_ turnState: TurnState) -> String {
        switch turnState {
        case .neutralOpen: return "neutralOpen"
        case .neutralClosed: return "neutralClosed"
        case .showdownOpen: return "showdownOpen"
        case .showdownClosed: return "showdownClosed"
        }
    }

    static func cardTypeName(_ type: MainDeckCardType) -> String {
        switch type {
        case .unit: return "unit"
        case .gear: return "gear"
        case .spell: return "spell"
        }
    }

    static func playDestinationName(_ destination: PlayDestination) -> String {
        switch destination {
        case .base: return "base"
        case .battlefield: return "battlefield"
        case .none: return "none"
        }
    }

    static func locationName(_ location: Location) -> String {
        switch location {
        case .base: return "base"
        case .battlefield: return "battlefield"
        }
    }

    /// Magnitudes are dropped: a rule asks whether a card *has* Ganking or
    /// Reaction, never how much Assault it has.
    static func keywordName(_ keyword: Keyword) -> String {
        switch keyword {
        case .accelerate: return "accelerate"
        case .action: return "action"
        case .assault: return "assault"
        case .deathknell: return "deathknell"
        case .deflect: return "deflect"
        case .ganking: return "ganking"
        case .hidden: return "hidden"
        case .legion: return "legion"
        case .reaction: return "reaction"
        case .shield: return "shield"
        case .tank: return "tank"
        case .temporary: return "temporary"
        case .vision: return "vision"
        }
    }
}
