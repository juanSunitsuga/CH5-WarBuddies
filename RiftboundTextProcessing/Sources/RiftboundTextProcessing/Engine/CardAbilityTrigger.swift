import Foundation

/// *When* a card's ability goes off, split out from *what* it does.
///
/// `CardAbilityParser` reads the effect half of a card's text — "draw 2",
/// "kill a unit". This reads the other half: the "When I move to a
/// battlefield," clause in front of it. The two are separate because the
/// app can only act on the trigger. It watches a table through a camera, so
/// it can see a card change zones; it cannot see an attack declared or a
/// battlefield conquered.
///
/// That split is the whole point. Rather than pretend to understand every
/// trigger, this names the two the camera can actually witness and files
/// the rest under `unobservable` — which keeps them visible as a known gap
/// instead of silently dropping card text on the floor.
public enum AbilityTrigger: Sendable, Equatable {
    /// "When you play me" — the card arrives on the board from hand.
    case played
    /// "When I move to a battlefield" — the narrower of the two move
    /// triggers, and the one the sample card set actually uses.
    case movedToBattlefield
    /// "When I move" — any zone change.
    case moved
    /// A real trigger this app has no way to observe: attacking,
    /// conquering, defending, another card being played. Carried with its
    /// own wording so it can still be *shown* as a standing reminder, just
    /// never fired automatically.
    case unobservable(String)

    /// Whether a zone change is enough to fire this.
    public var isObservable: Bool {
        switch self {
        case .played, .movedToBattlefield, .moved: return true
        case .unobservable: return false
        }
    }
}

/// One "when X, do Y" clause off a card, in the form the instruction band
/// needs: a trigger it can match against what the camera saw, and a
/// sentence a player can act on.
public struct TriggeredAbility: Sendable, Equatable {
    public let trigger: AbilityTrigger
    /// The effect half, cleaned of the card data's inline icon markup and
    /// ready to show. Deliberately the card's own wording rather than a
    /// Game Action: this is a reminder of what the player must resolve, and
    /// the printed sentence is both more precise and more trustworthy than
    /// anything this layer could paraphrase.
    public let effect: String

    public init(trigger: AbilityTrigger, effect: String) {
        self.trigger = trigger
        self.effect = effect
    }
}

public extension CardAbilityParser {

    /// Every "when …, …" clause on a card.
    ///
    /// Reads the raw printed text rather than `read(_:)`'s output, because
    /// `read` throws the trigger away — it is looking for Game Actions, and
    /// "when I move to a battlefield" isn't one. Both passes over the same
    /// text answer different questions.
    static func triggers(in text: String) -> [TriggeredAbility] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var found: [TriggeredAbility] = []
        // Reminder text in brackets restates a keyword the card already
        // carries, so firing on it would say the same thing twice.
        for clause in triggerClauses(in: stripParentheticals(text)) {
            guard let split = splitTrigger(clause) else { continue }
            let effect = plainMarkup(split.effect).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !effect.isEmpty else { continue }
            found.append(TriggeredAbility(trigger: split.trigger, effect: terminated(sentenceCased(effect))))
        }
        return found
    }

    /// Turns the card data's inline icon markup into words.
    ///
    /// The JSON writes costs and stats as `:rb_might:` / `:rb_energy_5:`
    /// tokens meant to be swapped for glyphs. Shown raw they read as
    /// mangled text in the middle of an instruction, which is exactly where
    /// a player is least able to shrug it off.
    static func plainMarkup(_ text: String) -> String {
        var out = text
        // Energy carries its value in the token itself (`:rb_energy_5:`).
        out = out.replacingOccurrences(
            of: #":rb_energy_(\d+):"#,
            with: "$1 Energy",
            options: .regularExpression
        )
        let words = [
            ":rb_might:": "Might",
            ":rb_power:": "Power",
            ":rb_energy:": "Energy",
        ]
        for (token, word) in words {
            out = out.replacingOccurrences(of: token, with: word)
        }
        // Anything still in the `:rb_…:` shape is a token this doesn't know.
        // Dropping it beats printing it: the sentence stays readable, and
        // the gap shows up in review rather than in front of a player.
        out = out.replacingOccurrences(of: #":rb_[a-z0-9_]+:"#, with: "", options: .regularExpression)
        // Collapse the double spaces the substitutions leave behind.
        out = out.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return out.replacingOccurrences(of: " .", with: ".")
    }

    // MARK: - Splitting "when X, Y"

    private static func splitTrigger(_ clause: String) -> (trigger: AbilityTrigger, effect: String)? {
        // The comma is the join in every printed trigger in the card set:
        // "When I move to a battlefield, play a … token here."
        guard let comma = clause.firstIndex(of: ",") else { return nil }
        let when = String(clause[clause.startIndex..<comma]).lowercased()
        let effect = String(clause[clause.index(after: comma)...])
        guard !effect.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        // Order matters: the battlefield form is a special case of the bare
        // move form, so it has to be tested first or it would never match.
        if when.contains("move") && when.contains("battlefield") {
            return (.movedToBattlefield, effect)
        }
        if when.contains("move") {
            return (.moved, effect)
        }
        if when.contains("play me") || when.contains("play a unit") {
            return (.played, effect)
        }
        return (.unobservable(when.trimmingCharacters(in: .whitespaces)), effect)
    }

    /// Each "when …" run, up to the end of its sentence.
    private static func triggerClauses(in text: String) -> [String] {
        let flattened = text.replacingOccurrences(of: "\n", with: " ")
        var clauses: [String] = []
        var search = flattened.startIndex

        while let start = flattened.range(
            of: #"\b(when|whenever)\b"#,
            options: [.regularExpression, .caseInsensitive],
            range: search..<flattened.endIndex
        ) {
            // A trigger runs to the end of its own sentence, so the next
            // full stop closes it — but not one inside a decimal or an
            // abbreviation, which is why this looks for ". " and end-of-text
            // rather than any period at all.
            let rest = flattened[start.upperBound...]
            let end = rest.range(of: #"\.(\s|$)"#, options: .regularExpression)?.lowerBound ?? flattened.endIndex
            clauses.append(String(flattened[start.lowerBound..<end]))
            search = end
            if search >= flattened.endIndex { break }
        }
        return clauses
    }

    /// Drops bracketed reminder text, which restates keywords the card
    /// already carries — "(It is also at the battlefield.)".
    private static func stripParentheticals(_ text: String) -> String {
        text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
    }

    /// The clause scanner stops *at* the full stop that ends a sentence, so
    /// the effect arrives without it. Put it back rather than widening the
    /// scanner, which would swallow the following sentence on a card that
    /// has two.
    private static func terminated(_ text: String) -> String {
        guard let last = text.last, !".!?".contains(last) else { return text }
        return text + "."
    }

    private static func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
