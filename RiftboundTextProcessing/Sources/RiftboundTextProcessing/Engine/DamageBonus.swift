import Foundation

/// A standing "+N damage" that a card already on the table grants to
/// *other* cards — the thing a player is most likely to forget, because it
/// isn't printed on the card they're about to play.
///
/// Two shapes exist in the card set, and they differ in where they apply:
///
/// - **Annie - Fiery** (a Unit): "Your spells and abilities deal 1 Bonus
///   Damage." Yours, wherever the damage lands.
/// - **Void Gate** (a Battlefield): "Spells and abilities affecting units
///   here each deal 1 Bonus Damage." Only at that battlefield.
///
/// Worth stating plainly because it is easy to assume otherwise: neither is
/// a Legend. The bonus comes from a card being *in play*, not from the deck
/// you chose, so it can arrive and leave mid-game.
public struct DamageBonus: Sendable, Equatable {
    public enum Scope: Sendable, Equatable {
        /// Applies to your damage wherever it lands.
        case anywhere
        /// Applies only to damage at the battlefield granting it.
        case atThisBattlefield
    }

    public let amount: Int
    public let scope: Scope

    public init(amount: Int, scope: Scope) {
        self.amount = amount
        self.scope = scope
    }
}

/// A `DamageBonus` that is live right now, with the card granting it named
/// so the advice can say where the number came from.
public struct ActiveDamageBonus: Sendable, Equatable {
    /// The card in play granting it — "Annie - Fiery", "Void Gate".
    public let source: String
    public let bonus: DamageBonus

    public init(source: String, bonus: DamageBonus) {
        self.source = source
        self.bonus = bonus
    }
}

public extension CardAbilityParser {

    /// The standing damage bonus a card grants while it is in play, if any.
    ///
    /// Deliberately separate from `read(_:)`. That reads a card as things
    /// *to do*; this reads it as a rule that changes someone else's
    /// numbers. Conflating them is what made "Your spells and abilities deal
    /// 1 Bonus Damage" parse as an instruction to deal 1 damage — a static
    /// modifier read as an action, which would have told the player to do
    /// something the card never asks for.
    static func damageBonus(in text: String) -> DamageBonus? {
        let lower = text.lowercased()
        guard let range = lower.range(of: #"deal\s+(\d+)\s+bonus damage"#, options: .regularExpression),
              let amount = Int(lower[range].filter(\.isNumber))
        else { return nil }

        // "here" is what scopes Void Gate to its own battlefield; without it
        // the bonus is unqualified and applies to your damage anywhere.
        let scope: DamageBonus.Scope = lower.contains("here") ? .atThisBattlefield : .anywhere
        return DamageBonus(amount: amount, scope: scope)
    }

    /// How much damage a card's own text deals, if it deals any.
    ///
    /// Printed text says "Deal 6 to a unit at a battlefield" — the word
    /// "damage" often doesn't appear. A "Bonus Damage" clause is explicitly
    /// *not* this: it modifies other cards rather than dealing anything
    /// itself.
    static func damageDealt(in text: String) -> Int? {
        guard damageBonus(in: text) == nil else { return nil }
        let lower = text.lowercased()
        guard let range = lower.range(of: #"deal\s+(\d+)"#, options: .regularExpression) else { return nil }
        return Int(lower[range].filter(\.isNumber))
    }
}
