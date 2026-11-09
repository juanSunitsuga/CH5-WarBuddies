import Foundation

/// The knowledge base: Riftbound's legality rules as data, loaded from
/// `Resources/RuleBase.json`.
///
/// This is the half of the expert system that holds *what the rules are*.
/// `RuleEngine` holds *how rules are applied*, and `RuleFacts` holds *what
/// is currently true of the board*. Before this existed, all three were one
/// Swift function, which made the usual expert-system claim — a knowledge
/// base separate from the inference engine — untrue of this app: changing a
/// rule meant editing and recompiling Swift.
///
/// Now a rule's timing window, its keyword requirement, its cost check and
/// the failure it reports are entries in a JSON file. The Swift side knows
/// how to read a `GameState` into facts and how to match a condition
/// against them; it contains no Riftbound rule of its own.
///
/// What is deliberately *not* here: how a legal action changes the board
/// (`GameActionApplier`), what a card's ability does (`EffectExecutor`),
/// and turn structure (`TurnSequencer`). Those are procedures, not
/// constraints, and writing them as data would buy nothing.
public struct RuleBase: Decodable, Sendable {
    /// Bumped when the rule language changes shape, not when a rule's
    /// numbers change — the point of the file is that the latter needs no
    /// code release.
    public let version: String
    /// Evaluated in order. The first rule that applies and is not satisfied
    /// decides the verdict, so order *is* rule precedence and is part of
    /// the knowledge, not an implementation detail.
    public let rules: [Rule]
    /// Rule 140.4's legal Origin → Destination table for a Standard Move.
    /// A table rather than a condition because it is matched against each
    /// moving unit in turn, and which unit failed is part of the answer.
    public let moveDestinations: [MoveDestinationRule]

    public init(version: String, rules: [Rule], moveDestinations: [MoveDestinationRule]) {
        self.version = version
        self.rules = rules
        self.moveDestinations = moveDestinations
    }
}

public extension RuleBase {

    /// One constraint: when it applies, what must hold, and what to report
    /// when it does not.
    struct Rule: Decodable, Sendable {
        /// The Riftbound rule number. Carried as data so a rejection can
        /// cite its source without a Swift comment being the only record.
        public let id: String
        /// Plain-language note for whoever edits this file.
        public let note: String?
        /// Action kinds this rule constrains, or `["any"]` for all of them.
        public let appliesTo: [String]
        /// Narrows the rule further — a rule with an unmet guard is skipped
        /// rather than failed.
        public let guardCondition: RuleCondition?
        /// What must be true for the action to stay legal.
        public let require: RuleCondition
        public let failure: FailureTemplate

        enum CodingKeys: String, CodingKey {
            case id, note, appliesTo, require, failure
            case guardCondition = "when"
        }
    }

    /// Which `LegalityValidator.Failure` a broken rule reports. Payloads
    /// that are board values (which unit, which phase) come from the facts'
    /// operands; the two numeric pairs name their facts here, because
    /// "required" and "available" mean different facts for Energy than for
    /// Power.
    struct FailureTemplate: Decodable, Sendable {
        public let kind: String
        public let required: String?
        public let available: String?
        public let observed: String?
    }

    /// One row of rule 140.4's destination table.
    struct MoveDestinationRule: Decodable, Sendable {
        public let id: String
        /// `base` or `battlefield`.
        public let from: String
        public let to: String
        /// Keyword the unit must carry for this row to permit the move —
        /// 140.4.c.1's Ganking.
        public let requiresKeyword: String?
        /// Whether Origin and Destination must be different places. Set for
        /// Battlefield → Battlefield: a unit "moving" to the Battlefield it
        /// already occupies would pay the Exhaust cost for no change, and
        /// in practice means the camera saw jitter.
        public let distinctPlaces: Bool?

        enum CodingKeys: String, CodingKey {
            case id, from, to, requiresKeyword
            case distinctPlaces = "distinct"
        }
    }
}

// MARK: - Loading

public extension RuleBase {

    /// The shipped rule base.
    ///
    /// A missing or malformed file is a packaging fault, not a game state to
    /// tolerate: the alternatives are accepting every action (an app with no
    /// rules at all) or rejecting every action (an app that looks broken for
    /// a reason nobody can see). Both are worse than stopping with the
    /// decoder's own message.
    static let bundled: RuleBase = {
        do {
            // `.module` is internal, so it can't be a default argument on a
            // public function — hence the bundle being passed here rather
            // than defaulted in `load`.
            return try load(from: .module)
        } catch {
            preconditionFailure("Couldn't load the rule base: \(error)")
        }
    }()

    static func load(from bundle: Bundle) throws -> RuleBase {
        guard let url = bundle.url(forResource: "RuleBase", withExtension: "json") else {
            throw RuleBaseError.missingResource
        }
        return try JSONDecoder().decode(RuleBase.self, from: try Data(contentsOf: url))
    }
}

public enum RuleBaseError: Error, LocalizedError {
    case missingResource

    public var errorDescription: String? {
        switch self {
        case .missingResource:
            return "RuleBase.json isn't in the bundle."
        }
    }
}

// MARK: - Conditions

/// The condition language the knowledge base is written in.
///
/// Kept this small on purpose. Every operator here is one a rule actually
/// needs, and a language that can express more than the rules require is a
/// language whose extra power is untested.
public indirect enum RuleCondition: Decodable, Sendable {
    /// `{"always": false}` — a rule that can never be satisfied, which is
    /// how "this action is not supported" is written as a rule.
    case always(Bool)
    /// A boolean fact is true.
    case isTrue(String)
    /// A fact has a value at all. A fact can be absent — a card that isn't
    /// in hand has no type — so this is how a rule says "only when known".
    case present(String)
    /// A named fact equals a literal.
    case equals(fact: String, value: String)
    /// A set-valued fact contains a literal.
    case contains(fact: String, value: String)
    case atLeast(fact: String, than: RuleTerm)
    case lessThan(fact: String, than: RuleTerm)
    case equalsNumber(fact: String, than: RuleTerm)
    case all([RuleCondition])
    case any([RuleCondition])
    case not(RuleCondition)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SingleKey.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "A condition is exactly one operator, got \(container.allKeys.count)."
            ))
        }

        switch key.stringValue {
        case "always":
            self = .always(try container.decode(Bool.self, forKey: key))
        case "isTrue":
            self = .isTrue(try container.decode(String.self, forKey: key))
        case "present":
            self = .present(try container.decode(String.self, forKey: key))
        case "not":
            self = .not(try container.decode(RuleCondition.self, forKey: key))
        case "all":
            self = .all(try container.decode([RuleCondition].self, forKey: key))
        case "any":
            self = .any(try container.decode([RuleCondition].self, forKey: key))
        case "equals", "contains":
            let pair = try container.decode([String].self, forKey: key)
            guard pair.count == 2 else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "\(key.stringValue) takes [fact, value]."
                ))
            }
            self = key.stringValue == "equals"
                ? .equals(fact: pair[0], value: pair[1])
                : .contains(fact: pair[0], value: pair[1])
        case "atLeast", "lessThan", "equalsNumber":
            let pair = try container.decode(Comparison.self, forKey: key)
            switch key.stringValue {
            case "atLeast": self = .atLeast(fact: pair.fact, than: pair.term)
            case "lessThan": self = .lessThan(fact: pair.fact, than: pair.term)
            default: self = .equalsNumber(fact: pair.fact, than: pair.term)
            }
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown condition operator '\(key.stringValue)'."
            ))
        }
    }

    private struct SingleKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// `[fact, fact-or-number]`.
    private struct Comparison: Decodable {
        let fact: String
        let term: RuleTerm

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            fact = try container.decode(String.self)
            term = try container.decode(RuleTerm.self)
        }
    }
}

/// The right-hand side of a numeric comparison: either another fact or a
/// constant written in the file.
public enum RuleTerm: Decodable, Sendable {
    case fact(String)
    case literal(Int)

    public init(from decoder: Decoder) throws {
        // A single-value container doesn't advance anything on a failed
        // attempt, unlike probing an unkeyed container, so trying the
        // number first is safe here.
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            self = .literal(number)
        } else {
            self = .fact(try container.decode(String.self))
        }
    }
}
