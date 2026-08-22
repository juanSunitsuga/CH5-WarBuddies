import Foundation
import RiftboundExpertSystem

/// One thing a card's text tells the game to do, in both forms the app
/// needs: the structured `EffectInstruction` the Expert System consumes,
/// and a sentence a player can read.
public struct ParsedAbility: Sendable, Equatable {
    /// The Game Action this resolves to (586–607). Named in the engine's
    /// own vocabulary rather than the card's wording, because that closed
    /// set is the only thing the engine can act on.
    public let action: String
    /// Player-facing, e.g. "Draw 2 cards."
    public let summary: String
    /// Rule 718/725: this ability is only playable in the windows the
    /// keyword opens, which is the difference between "I can do this now"
    /// and "I can do this during a showdown."
    public let timing: String?
    /// Who/what this ability reaches, read off the same sentence the verb
    /// came from — "me", "a unit", "each enemy unit", "up to two units".
    /// `.unresolved` for an ability with no target of its own (Draw,
    /// Channel, Discard) or a target shape this reader doesn't recognize
    /// yet; `instruction(for:)` still emits the effect either way; a
    /// caller just can't auto-resolve `.unresolved`'s target.
    public let target: EffectInstruction.TargetSpec

    public init(action: String, summary: String, timing: String? = nil, target: EffectInstruction.TargetSpec = .unresolved) {
        self.action = action
        self.summary = summary
        self.timing = timing
        self.target = target
    }
}

/// Turns printed card text into the closed vocabulary of Game Actions
/// (586–607) — the parse step this package exists for, and the one
/// `ExpertSystemTranslatorAdapter.parseAbility` returned `[]` for.
///
/// **This is deliberately a reader, not a rules engine.** It says what a
/// card claims to do so the player can be told; it does not decide whether
/// doing it is legal, and it does not execute anything. Those stay with
/// `LegalityValidator` and the (still unbuilt) effects pipeline.
///
/// Text that doesn't map onto a Game Action is reported as unparsed rather
/// than guessed at (CLAUDE.md point 4). A card whose ability shows as
/// "not understood" is a parser gap someone can go fix; a card whose
/// ability is silently invented is a wrong game state nobody can trace.
public enum CardAbilityParser {

    /// Everything one card's text says, plus whatever couldn't be read.
    public struct Reading: Sendable, Equatable {
        public var abilities: [ParsedAbility]
        /// Sentences that mention a game verb but didn't match any known
        /// shape. Surfaced, not swallowed.
        public var unparsed: [String]

        public var isEmpty: Bool { abilities.isEmpty && unparsed.isEmpty }
    }

    public static func read(_ text: String) -> Reading {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Reading(abilities: [], unparsed: [])
        }

        var abilities: [ParsedAbility] = []
        var unparsed: [String] = []

        let timing = self.timing(in: text)

        for sentence in sentences(in: text) {
            if let ability = ability(from: sentence, timing: timing) {
                abilities.append(ability)
            } else if mentionsAGameVerb(sentence) {
                unparsed.append(sentence)
            }
        }

        // Keywords are abilities in their own right (717–729), and carry no
        // verb of their own — they're read off the whole text, not per
        // sentence, so they don't get double-counted above.
        abilities.append(contentsOf: keywordAbilities(in: text))

        return Reading(abilities: abilities, unparsed: unparsed)
    }

    /// The `EffectInstruction`s the Expert System can consume, using each
    /// ability's own `target` — real `TargetSpec` cases where the sentence
    /// resolved one, `.unresolved` where it didn't (the *summary* still
    /// carries the meaning for a human in that case; nothing auto-resolves
    /// it, but nothing invents a wrong target for it either).
    public static func instructions(for text: String) -> [EffectInstruction] {
        read(text).abilities.compactMap(instruction(for:))
    }

    private static func instruction(for ability: ParsedAbility) -> EffectInstruction? {
        switch ability.action {
        case "Draw":
            return .draw(count: ability.count ?? 1)
        case "Channel":
            return .channelRune(count: ability.count ?? 1, exhausted: ability.summary.lowercased().contains("exhausted"))
        case "Discard":
            return .discard(count: ability.count ?? 1)
        case "Deal damage":
            return .dealDamage(amount: ability.count ?? 0, targets: ability.target)
        case "Kill":
            return .killUnit(targets: ability.target)
        case "Stun":
            return .stunUnit(targets: ability.target)
        case "Banish":
            return .banishCard(targets: ability.target)
        case "Counter":
            return .counterSpell(targets: ability.target)
        case "Ready":
            return .readyObject(targets: ability.target)
        case "Exhaust":
            return .exhaustObject(targets: ability.target)
        case "Buff":
            return .buff(targets: ability.target)
        case "Recycle":
            return .recycleCard(targets: ability.target, destination: .mainDeck)
        default:
            // Keywords (Assault/Shield modulate Might per 625.1.b, Tank/
            // Ganking/etc. are passive, not a resolved effect) don't map
            // onto a single Game Action.
            return nil
        }
    }

    // MARK: - Sentence-level verbs

    private static func ability(from sentence: String, timing: String?) -> ParsedAbility? {
        let lower = sentence.lowercased()

        if let n = number(after: #"draw\s+"#, in: lower) {
            return ParsedAbility(action: "Draw", summary: "Draw \(n) card\(n == 1 ? "" : "s").", timing: timing)
        }
        if let n = number(after: #"channel\s+"#, in: lower) {
            let exhausted = lower.contains("exhausted")
            return ParsedAbility(
                action: "Channel",
                summary: "Channel \(n) rune\(n == 1 ? "" : "s")\(exhausted ? " exhausted" : "").",
                timing: timing
            )
        }
        if let n = number(after: #"discard\s+"#, in: lower) {
            return ParsedAbility(action: "Discard", summary: "Discard \(n) card\(n == 1 ? "" : "s").", timing: timing)
        }
        // Printed text says "Deal 6 to a unit at a battlefield" — the word
        // "damage" itself rarely appears. Requiring it (as an earlier
        // version of this pattern did) meant this branch never actually
        // fired against real card text; "deal N" alone is specific enough
        // in a rules-text context that dropping the requirement doesn't
        // risk false positives.
        // "Your spells and abilities deal 1 Bonus Damage" is a standing
        // modifier on *other* cards, not an instruction to deal 1. Read as
        // an action it told the player to do something the card never asks
        // for — see `damageBonus(in:)`, which is what actually reads it.
        if let n = number(after: #"deal\s+"#, in: lower), !lower.contains("bonus damage") {
            return ParsedAbility(action: "Deal damage", summary: "Deal \(n) damage.", timing: timing, target: target(in: sentence))
        }
        if let n = number(after: #"recycle\s+"#, in: lower) {
            return ParsedAbility(action: "Recycle", summary: "Recycle \(n) card\(n == 1 ? "" : "s").", timing: timing)
        }
        if lower.contains("kill ") {
            return ParsedAbility(action: "Kill", summary: "Kill a unit.", timing: timing, target: target(in: sentence))
        }
        if lower.contains("stun ") {
            return ParsedAbility(action: "Stun", summary: "Stun a unit.", timing: timing, target: target(in: sentence))
        }
        if lower.contains("banish ") {
            return ParsedAbility(action: "Banish", summary: "Banish a card.", timing: timing, target: target(in: sentence))
        }
        if lower.contains("counter ") {
            return ParsedAbility(action: "Counter", summary: "Counter a spell or ability.", timing: timing)
        }
        if lower.contains("ready ") {
            return ParsedAbility(action: "Ready", summary: "Ready a game object.", timing: timing, target: target(in: sentence))
        }
        if lower.contains("exhaust ") {
            return ParsedAbility(action: "Exhaust", summary: "Exhaust a game object.", timing: timing, target: target(in: sentence))
        }
        if let boost = mightBoost(in: sentence) {
            return ParsedAbility(action: "Buff", summary: "Give +\(boost) Might.", timing: timing, target: target(in: sentence))
        }
        return nil
    }

    /// Reads who/what a sentence's effect reaches. Checked in order from
    /// most to least specific, since e.g. "each enemy unit" would also
    /// match a looser "unit" scan if checked second.
    ///
    /// "me" is checked as the *object* of the verb ("give me", "deal 3
    /// damage to me") — a bare "me" appearing earlier in the sentence for
    /// some other reason is deliberately not enough on its own, so this
    /// doesn't misread a self-reference that wasn't actually the target.
    private static func target(in sentence: String) -> EffectInstruction.TargetSpec {
        let lower = sentence.lowercased()

        if lower.range(of: #"\b(give|deal(?:s)?\s+\d+(?:\s+to)?)\s+me\b"#, options: .regularExpression) != nil {
            return .source
        }

        let filter: EffectInstruction.UnitFilter = lower.contains("friendly") ? .friendly : (lower.contains("enemy") ? .enemy : .any)

        // Checked before the "each"/"all" scan below: "each of up to two
        // units" contains both "each " and "up to" — it means the bounded
        // count, not an unbounded "every unit," so the more specific
        // pattern has to win the race.
        if let n = number(afterSpelledOutOrDigit: #"up to\s+"#, in: lower) {
            return .upToUnits(maximum: n, filter: filter)
        }
        if (lower.contains("each ") || lower.contains("all ")), lower.contains("unit") {
            return .allUnits(filter)
        }
        if lower.contains(" a unit") || lower.contains(" an enemy unit") || lower.contains(" a friendly unit") {
            return .chosenUnit(filter)
        }

        return .unresolved
    }

    /// Rules 717–729. Reported as abilities because that is what they are —
    /// a Tank unit *does* something (626.1.d.1) even though its text is one
    /// word.
    private static func keywordAbilities(in text: String) -> [ParsedAbility] {
        var found: [ParsedAbility] = []
        let lower = text.lowercased()

        if let value = bracketedValue("assault", in: lower) {
            found.append(ParsedAbility(action: "Buff", summary: "Assault \(value) — +\(value) Might while attacking (Rule 719).") )
        }
        if let value = bracketedValue("shield", in: lower) {
            found.append(ParsedAbility(action: "Buff", summary: "Shield \(value) — +\(value) Might while defending (Rule 726)."))
        }
        if lower.contains("[tank]") {
            found.append(ParsedAbility(action: "—", summary: "Tank — must be assigned combat damage first (Rule 727)."))
        }
        if lower.contains("[ganking]") {
            found.append(ParsedAbility(action: "Move", summary: "Ganking — may move between battlefields (Rule 722)."))
        }
        if lower.contains("[accelerate]") {
            found.append(ParsedAbility(action: "—", summary: "Accelerate — enters play ready instead of exhausted (Rule 717)."))
        }
        if lower.contains("[deathknell]") {
            found.append(ParsedAbility(action: "—", summary: "Deathknell — triggers when it dies (Rule 720)."))
        }
        if lower.contains("[hidden]") {
            found.append(ParsedAbility(action: "Hide", summary: "Hidden — may be played facedown at a battlefield (Rule 723)."))
        }
        if lower.contains("[legion]") {
            found.append(ParsedAbility(action: "—", summary: "Legion — triggers if you played another main deck card this turn (Rule 724)."))
        }
        return found
    }

    // MARK: - Timing (718/725)

    private static func timing(in text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("[reaction]") {
            return "Reaction — playable whenever something is resolving (Rule 725)."
        }
        if lower.contains("[action]") {
            return "Action — playable during a showdown when you have focus (Rule 718)."
        }
        return nil
    }

    // MARK: - Text helpers

    private static func sentences(in text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: ". ")
            .components(separatedBy: CharacterSet(charactersIn: ".;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// A sentence that clearly instructs something but didn't match a known
    /// shape. Used to surface parser gaps instead of silently dropping text.
    private static func mentionsAGameVerb(_ sentence: String) -> Bool {
        let verbs = ["draw", "kill", "stun", "banish", "counter", "channel",
                     "recycle", "discard", "damage", "deal", "buff", "move", "ready", "exhaust"]
        let lower = sentence.lowercased()
        return verbs.contains { lower.contains($0) }
    }

    private static func number(after prefix: String, in text: String) -> Int? {
        guard let range = text.range(of: prefix + #"\d+"#, options: .regularExpression) else { return nil }
        return Int(text[range].filter(\.isNumber))
    }

    private static let spelledOutNumbers = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
    ]

    /// Same as `number(after:in:)`, but also reads "two"/"three"/etc. —
    /// needed for "up to two units," where a digit never appears at all.
    private static func number(afterSpelledOutOrDigit prefix: String, in text: String) -> Int? {
        if let n = number(after: prefix, in: text) { return n }
        guard let range = text.range(of: prefix + #"[a-z]+"#, options: .regularExpression) else { return nil }
        let word = text[range].replacingOccurrences(of: prefix, with: "", options: .regularExpression)
        return spelledOutNumbers[word]
    }

    private static func mightBoost(in text: String) -> Int? {
        guard let range = text.range(of: #"\+\d+"#, options: .regularExpression),
              text.lowercased().contains("might") || text.contains("[S]") else { return nil }
        return Int(text[range].filter(\.isNumber))
    }

    private static func bracketedValue(_ keyword: String, in lower: String) -> Int? {
        guard let range = lower.range(of: "\\[" + keyword + #"\s*\d*\]"#, options: .regularExpression) else { return nil }
        let digits = lower[range].filter(\.isNumber)
        return digits.isEmpty ? 1 : Int(digits)
    }
}

private extension ParsedAbility {
    /// The count embedded in this ability's own summary — the parser wrote
    /// it there, so re-reading it avoids carrying a second field that could
    /// disagree with the sentence the player is shown.
    var count: Int? {
        guard let range = summary.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(summary[range])
    }
}
