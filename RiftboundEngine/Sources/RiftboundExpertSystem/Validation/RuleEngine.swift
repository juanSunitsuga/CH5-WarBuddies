import Foundation

/// The inference engine: matches the knowledge base against the facts and
/// returns the first rule that is broken.
///
/// Contains no Riftbound rule. Everything it knows is how to evaluate a
/// condition and how to turn a broken rule into a `LegalityValidator.Failure`
/// — which is exactly the separation the expert-system design claims. Swap
/// `RuleBase.json` and this file's behaviour changes with it; edit this file
/// and no rule changes.
///
/// Forward chaining, one pass, first failure wins. A rule base this size
/// gains nothing from a conflict-resolution strategy: the rules are ordered
/// in the file, and that order is the precedence (rule 633's "the game is
/// over" has to be read before anything else, and a cost check is pointless
/// before the card is known to be in hand).
enum RuleEngine {

    static func evaluate(
        _ action: GameAction,
        in state: GameState,
        proposedBy player: PlayerID,
        ruleBase: RuleBase = .bundled
    ) -> Result<Void, LegalityValidator.Failure> {
        let facts = RuleFacts.derive(for: action, in: state, proposedBy: player, ruleBase: ruleBase)

        for rule in ruleBase.rules {
            guard rule.appliesTo.contains(facts.actionKind) || rule.appliesTo.contains("any") else {
                continue
            }
            if let guardCondition = rule.guardCondition,
               !holds(guardCondition, in: facts) {
                continue
            }
            if !holds(rule.require, in: facts) {
                return .failure(failure(from: rule.failure, facts: facts))
            }
        }
        return .success(())
    }

    // MARK: - Condition matching

    /// An absent fact makes its condition false rather than trapping.
    ///
    /// A fact can legitimately be missing — a card that isn't in the
    /// player's Hand has no cost — and rule order is what keeps a rule from
    /// reading one: the rule that establishes the card is in Hand comes
    /// first, and evaluation stops at the first failure. Returning false
    /// keeps a mis-ordered file to a wrong *reason* rather than a crash, and
    /// the validator's tests are what catch the ordering.
    static func holds(_ condition: RuleCondition, in facts: RuleFacts) -> Bool {
        switch condition {
        case .always(let value):
            return value

        case .isTrue(let name):
            return facts.values[name] == .bool(true)

        case .present(let name):
            return facts.values[name] != nil

        case .equals(let name, let value):
            return facts.values[name] == .text(value)

        case .contains(let name, let value):
            guard case .texts(let set) = facts.values[name] else { return false }
            return set.contains(value)

        case .atLeast(let name, let term):
            guard let lhs = number(name, in: facts), let rhs = number(term, in: facts) else { return false }
            return lhs >= rhs

        case .lessThan(let name, let term):
            guard let lhs = number(name, in: facts), let rhs = number(term, in: facts) else { return false }
            return lhs < rhs

        case .equalsNumber(let name, let term):
            guard let lhs = number(name, in: facts), let rhs = number(term, in: facts) else { return false }
            return lhs == rhs

        case .all(let conditions):
            return conditions.allSatisfy { holds($0, in: facts) }

        case .any(let conditions):
            return conditions.contains { holds($0, in: facts) }

        case .not(let inner):
            return !holds(inner, in: facts)
        }
    }

    private static func number(_ name: String, in facts: RuleFacts) -> Int? {
        guard case .number(let value) = facts.values[name] else { return nil }
        return value
    }

    private static func number(_ term: RuleTerm, in facts: RuleFacts) -> Int? {
        switch term {
        case .literal(let value): return value
        case .fact(let name): return number(name, in: facts)
        }
    }

    // MARK: - Reporting

    /// Builds the typed failure a broken rule reports.
    ///
    /// `.notImplemented` for an unknown kind or a missing operand: both mean
    /// the file and this switch disagree, which is a build-time fault the
    /// validator's tests fail on, and reporting it as "not modeled" is the
    /// honest reading of a rule this engine cannot express.
    private static func failure(
        from template: RuleBase.FailureTemplate,
        facts: RuleFacts
    ) -> LegalityValidator.Failure {
        let operands = facts.operands

        switch template.kind {
        case "gameAlreadyWon":
            guard let winner = operands.winner else { return .notImplemented }
            return .gameAlreadyWon(winner)

        case "notActionPhase":
            guard let phase = operands.phase else { return .notImplemented }
            return .notActionPhase(phase)

        case "notPlayersPriority":
            return .notPlayersPriority

        case "cardNotInHand":
            guard let cardID = operands.cardID else { return .notImplemented }
            return .cardNotInHand(cardID)

        case "reactionRequired":
            return .reactionRequired

        case "actionOrReactionRequired":
            return .actionOrReactionRequired

        case "invalidPlayDestination":
            guard let destination = operands.playDestination else { return .notImplemented }
            return .invalidPlayDestination(destination)

        case "destinationOccupiedByTwoOtherControllers":
            guard let battlefieldID = operands.destinationBattlefield else { return .notImplemented }
            return .destinationOccupiedByTwoOtherControllers(battlefieldID)

        case "insufficientEnergy":
            guard let required = number(template.required, facts: facts),
                  let available = number(template.available, facts: facts) else { return .notImplemented }
            return .insufficientEnergy(required: required, available: available)

        case "insufficientPower":
            guard let required = number(template.required, facts: facts),
                  let available = number(template.available, facts: facts) else { return .notImplemented }
            return .insufficientPower(required: required, available: available)

        case "exhaustedRuneCountMismatch":
            guard let required = number(template.required, facts: facts),
                  let observed = number(template.observed, facts: facts) else { return .notImplemented }
            return .exhaustedRuneCountMismatch(required: required, observed: observed)

        case "unitNotFound":
            guard let unitID = operands.missingUnit else { return .notImplemented }
            return .unitNotFound(unitID)

        case "unitAlreadyExhausted":
            guard let unitID = operands.exhaustedUnit else { return .notImplemented }
            return .unitAlreadyExhausted(unitID)

        case "illegalMoveDestination":
            guard let move = operands.illegalMove else { return .notImplemented }
            return .illegalMoveDestination(from: move.from, to: move.to)

        case "moveOriginsMismatch":
            return .moveOriginsMismatch

        case "noRuneOfDomainAvailable":
            guard let domain = operands.domain else { return .notImplemented }
            return .noRuneOfDomainAvailable(domain)

        case "limitedActionNotAuthorized":
            guard let action = operands.action else { return .notImplemented }
            return .limitedActionNotAuthorized(action)

        case "notImplemented":
            return .notImplemented

        default:
            return .notImplemented
        }
    }

    private static func number(_ name: String?, facts: RuleFacts) -> Int? {
        guard let name else { return nil }
        return number(name, in: facts)
    }
}
