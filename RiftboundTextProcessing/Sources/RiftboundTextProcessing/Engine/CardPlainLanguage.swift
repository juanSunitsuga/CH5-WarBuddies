import Foundation

/// Card text and player instructions, rewritten in words someone can act on
/// without knowing the rulebook.
///
/// Printed card text is written for players who already speak the game:
/// `[Tank]`, `:rb_might:`, "recycle it", "when you conquer". Shown raw — as
/// the card detail panel did — it is a wall of jargon and icon markup at
/// exactly the moment a new player is trying to work out what to do.
///
/// **Every definition here is copied from `docs/rules/how-to-play.md`, not
/// invented.** A keyword this file has no grounded wording for is reported
/// in `unexplained` and passed through untouched. That matters more than
/// coverage: a card whose ability is described wrongly is worse than one
/// described tersely, because the player has no way to tell it happened.
public enum CardPlainLanguage {

    /// A card's text, broken into lines a player can read top to bottom.
    public struct Explanation: Sendable, Equatable {
        /// Ordered, player-facing. Keywords first — they qualify everything
        /// under them — then what the card does.
        public var lines: [String]
        /// Keywords found in the text that this file has no grounded plain
        /// wording for. Surfaced so the gap is fixable rather than silent.
        public var unexplained: [String]

        public var isEmpty: Bool { lines.isEmpty }
    }

    // MARK: - Cards

    /// Turns one card's printed text into plain lines.
    public static func explain(_ text: String) -> Explanation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Explanation(lines: [], unexplained: []) }

        var glossed: Set<String> = []
        var lines: [String] = []
        var unexplained: [String] = []

        // 1. Keywords. They modify everything else on the card, so they read
        //    first — and they're the densest jargon, so they benefit most.
        for keyword in keywords(in: trimmed) {
            if let plain = keywordGloss(keyword) {
                lines.append(plain)
            } else {
                unexplained.append(keyword.raw)
            }
        }

        // 2. Triggered abilities, as "When …: do …". The colon is doing real
        //    work: printed text runs the condition and the effect together
        //    in one sentence, and splitting them is most of what makes the
        //    ability scannable.
        let triggers = CardAbilityParser.triggers(in: trimmed)
        for ability in triggers {
            let effect = simplify(ability.effect, glossed: &glossed)
            lines.append("\(whenClause(for: ability.trigger)): \(lowerFirst(effect))")
        }

        // 3. Anything left that isn't a trigger and isn't bare keyword text —
        //    static abilities like "You may play me to an open battlefield."
        for sentence in leftoverSentences(in: trimmed, alreadyCoveredBy: triggers) {
            lines.append(simplify(sentence, glossed: &glossed))
        }

        return Explanation(lines: lines, unexplained: unexplained)
    }

    /// One card described for someone who has just tapped it and doesn't
    /// know what it is.
    ///
    /// Takes plain values rather than a `CardPrinting` on purpose: that
    /// type lives in `RiftboundVision`, which this package must not depend
    /// on. Keeping the seam at primitives is also what makes this testable
    /// without a card database — the caller is then a two-line adapter with
    /// nothing in it worth testing.
    public struct CardSummary: Sendable, Equatable {
        /// Name and type — "what kind of thing is this" is the first half
        /// of the answer to "what is this".
        public var headline: String
        /// Cost, then what the card does, in the wording above.
        public var detail: String
    }

    public static func describeCard(
        name: String,
        type: String,
        energyCost: Int?,
        powerCost: Int,
        powerDomains: [String] = [],
        printedText: String,
        activeBonuses: [ActiveDamageBonus] = []
    ) -> CardSummary {
        let trimmedType = type.trimmingCharacters(in: .whitespaces)
        let headline = trimmedType.isEmpty ? name : "\(name) — \(trimmedType)"

        var parts: [String] = []
        if let cost = costSentence(energyCost: energyCost, powerCost: powerCost, domains: powerDomains) { parts.append(cost) }

        let explanation = explain(printedText)
        parts.append(contentsOf: explanation.lines)
        // Shown as printed rather than paraphrased, same rule as everywhere
        // else here.
        parts.append(contentsOf: explanation.unexplained)

        // What's on the table can change this card's numbers, and that
        // bonus is printed on the *other* card — so it goes last, where a
        // correction belongs, rather than being folded silently into the
        // ability text as if the card said it.
        if let damage = CardAbilityParser.damageDealt(in: printedText),
           let advice = damageAdvice(base: damage, bonuses: activeBonuses) {
            parts.append(advice)
        }

        if parts.isEmpty {
            parts.append("No printed ability — it does what its type does, nothing more.")
        }
        return CardSummary(headline: headline, detail: parts.joined(separator: " "))
    }

    /// The cost as two physical acts, not two numbers.
    ///
    /// "Costs 2 Energy and 1 Power" names the currencies and leaves the
    /// player to know how each is paid, which is exactly the part they
    /// don't know: Energy comes from *exhausting* runes (157.2.a) and Power
    /// from *recycling* them (157.2.b). Recycling means to the **bottom of
    /// the rune deck** (594.1.b), not to a discard pile — which is the
    /// reading the word invites, and the one that puts a rune somewhere it
    /// can never come back from.
    ///
    /// Power is usually domain-locked (130.3), so the domain is named when
    /// the card has one: "recycle 1 Fury rune" is something a player can
    /// do, where "1 Power" is a symbol to go and look up.
    ///
    /// A card with no cost at all still says nothing rather than an empty
    /// line, which would read as a value that failed to load.
    private static func costSentence(energyCost: Int?, powerCost: Int, domains: [String]) -> String? {
        let energy = energyCost ?? 0
        guard energy > 0 || powerCost > 0 else { return nil }

        var parts: [String] = []
        if energy > 0 {
            parts.append("exhaust \(energy) rune\(energy == 1 ? "" : "s")")
        }
        if powerCost > 0 {
            let named = domains
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " or ")
            let domainPrefix = named.isEmpty ? "" : named + " "
            parts.append("recycle \(powerCost) \(domainPrefix)rune\(powerCost == 1 ? "" : "s") to the bottom of your rune deck")
        }
        return "To play it, " + parts.joined(separator: " and ") + "."
    }

    /// What a card will *actually* deal, given what's already on the table.
    ///
    /// The bonus is printed on the card granting it, not on the card being
    /// played, so this is precisely the arithmetic a player is likely to
    /// miss — and they only find out they were wrong after the damage is
    /// dealt. Says the final number first, because that is the one being
    /// acted on, and names the source so it can be checked rather than
    /// taken on trust.
    ///
    /// Battlefield-scoped bonuses are reported separately: they only apply
    /// where that battlefield is, so folding them into one total would
    /// overstate the damage everywhere else.
    static func damageAdvice(base: Int, bonuses: [ActiveDamageBonus]) -> String? {
        guard base > 0, !bonuses.isEmpty else { return nil }

        let everywhere = bonuses.filter { $0.bonus.scope == .anywhere }
        let located = bonuses.filter { $0.bonus.scope == .atThisBattlefield }

        let everywhereTotal = everywhere.reduce(0) { $0 + $1.bonus.amount }
        let running = base + everywhereTotal

        var sentences: [String] = []
        if everywhereTotal > 0 {
            let names = listing(everywhere.map(\.source))
            sentences.append("Deals \(running), not \(base) — \(names) in play.")
        }
        for bonus in located {
            let total = running + bonus.bonus.amount
            sentences.append(everywhereTotal > 0
                ? "At \(bonus.source), \(total)."
                : "Deals \(total), not \(base), at \(bonus.source).")
        }
        return sentences.joined(separator: " ")
    }

    /// "a", "a and b", "a, b and c".
    private static func listing(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
    }

    // MARK: - Instructions

    /// Rewrites one instruction sentence in plainer words.
    ///
    /// Used on what the app tells the player to do, not just on card text.
    /// The two had drifted: the band said "Channel 2 runes" while the card
    /// panel said "put the top 2 cards of your Rune Deck on the board", and
    /// only one of those can be read by someone on their first game.
    public static func simplify(_ sentence: String) -> String {
        var glossed: Set<String> = []
        return simplify(sentence, glossed: &glossed)
    }

    /// The same cleanup with the glossary switched off.
    ///
    /// A gloss is a whole extra sentence, which is right underneath an
    /// instruction and wrong inside a headline: the mascot band's headline
    /// is set at display size, so appending "Channelling takes runes off
    /// your rune deck and puts them on the board." to "0 of 2 runes
    /// channeled." doubled the largest text on screen and then said the
    /// same thing again in the line below it. Headlines take this; details
    /// take `simplify`.
    public static func tidy(_ sentence: String) -> String {
        var out = CardAbilityParser.plainMarkup(sentence)
        out = strippingRuleCitations(out)
        out = expandingInlineKeywords(out)
        out = thirdPerson(out)
        return collapsingSpaces(out)
    }

    /// The glossing set is threaded through so a term is explained once per
    /// card or per instruction, not once per sentence. Repeating "(turn it
    /// sideways)" three times in four lines reads as a malfunction.
    private static func simplify(_ sentence: String, glossed: inout Set<String>) -> String {
        var out = CardAbilityParser.plainMarkup(sentence)
        out = strippingRuleCitations(out)
        out = expandingInlineKeywords(out)
        out = thirdPerson(out)

        var notes: [String] = []
        for term in glossary where !glossed.contains(term.word) {
            guard out.range(
                of: #"\b"# + NSRegularExpression.escapedPattern(for: term.word),
                options: [.regularExpression, .caseInsensitive]
            ) != nil else { continue }
            // Belt and braces against a second pass over text that has
            // already been glossed. The `glossed` set only guards within one
            // call, and running this twice over the same string put "A token
            // is a unit created during play." on screen twice. The caller
            // shouldn't do that — but a gloss the text already contains is
            // never worth adding, whoever asked.
            guard !out.contains(term.note) else {
                glossed.insert(term.word)
                continue
            }
            glossed.insert(term.word)
            notes.append(term.note)
        }

        out = collapsingSpaces(out)
        guard !notes.isEmpty else { return out }
        if !out.hasSuffix(".") && !out.hasSuffix("!") && !out.hasSuffix("?") { out += "." }
        return out + " " + notes.joined(separator: " ")
    }

    // MARK: - Glossary (docs/rules/how-to-play.md, "Terms to Know")

    private struct Term {
        /// Matched as a stem, so "exhaust" also catches "exhausted".
        let word: String
        /// A whole sentence, appended after the instruction rather than
        /// spliced into it. Inline it read "every exhausted (turn it
        /// sideways) card", which is worse than the jargon it replaced —
        /// a gloss has to be grammatical where it lands, and the only
        /// position that is always grammatical is the end.
        let note: String
    }

    /// Only terms a first-time player genuinely can't guess. "Draw", "play"
    /// and "move" are left alone on purpose — glossing an ordinary English
    /// word is noise that makes the real glosses easier to skip over.
    private static let glossary: [Term] = [
        Term(word: "exhaust", note: "Exhausted means turned sideways."),
        Term(word: "recycle", note: "Recycling a card puts it on the bottom of its deck."),
        Term(word: "channel", note: "Channelling takes runes off your rune deck and puts them on the board."),
        Term(word: "stun", note: "A stunned unit deals no combat damage this turn."),
        Term(word: "showdown", note: "A showdown is the fight at a battlefield."),
        Term(word: "token", note: "A token is a unit created during play."),
    ]

    // MARK: - Keywords

    private struct Keyword {
        let raw: String
        let name: String
        let value: Int?
    }

    /// Grounded in the keyword glossary in `how-to-play.md`. A keyword
    /// absent from here returns `nil` and is reported as unexplained rather
    /// than paraphrased from its name, which is how "Deflect" would have
    /// become something confidently wrong.
    private static func keywordGloss(_ keyword: Keyword) -> String? {
        let n = keyword.value.map(String.init) ?? "some"
        switch keyword.name {
        case "tank":        return "Tank — this unit takes combat damage first."
        case "assault":     return "Assault \(n) — it gets +\(n) Might while attacking."
        case "shield":      return "Shield \(n) — it gets +\(n) Might while defending."
        case "deathknell":  return "Deathknell — this goes off when the unit dies."
        case "deflect":     return "Deflect — opponents pay extra Power to target it."
        case "ganking":     return "Ganking — it can move straight from one battlefield to another."
        case "accelerate":  return "Accelerate — for a cost, it arrives upright instead of sideways."
        case "temporary":   return "Temporary — it dies at the start of your turn."
        case "legion":      return "Legion — this only goes off if you already played another main deck card this turn."
        case "vision":      return "Vision — when you play it, look at the top card of your main deck; you may put it on the bottom."
        case "hidden":      return "Hidden — you can hide it face down at a battlefield you control."
        case "action":      return "Action — you can only play this during a fight at a battlefield, when it's your turn to act."
        case "reaction":    return "Reaction — you can play this while something else is still resolving."
        default:            return nil
        }
    }

    private static func keywords(in text: String) -> [Keyword] {
        let pattern = #"\[([A-Za-z]+)(?:\s+(\d+))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var seen: Set<String> = []
        var found: [Keyword] = []

        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            guard seen.insert(name).inserted else { continue }
            let value = match.range(at: 2).location == NSNotFound
                ? nil
                : Int(ns.substring(with: match.range(at: 2)))
            found.append(Keyword(raw: ns.substring(with: match.range), name: name, value: value))
        }
        return found
    }

    /// Inside a sentence a keyword is a noun, not a heading — "[Shield 2]"
    /// becomes "Shield 2", explained separately above rather than inline.
    private static func expandingInlineKeywords(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\[([A-Za-z]+)(\s+\d+)?\]"#,
            with: "$1$2",
            options: .regularExpression
        )
    }

    // MARK: - Sentences

    private static func whenClause(for trigger: AbilityTrigger) -> String {
        switch trigger {
        case .played:             return "When you play it"
        case .movedToBattlefield: return "When you move it to a battlefield"
        case .moved:              return "When you move it"
        case .unobservable(let wording):
            // Kept in the card's own words — these are the triggers the app
            // can't witness, and rewording one risks implying the app is
            // watching for it. Cleaned up all the same: leaving
            // ":rb_energy_5:" in the condition helps nobody.
            var glossed: Set<String> = []
            return sentenceCased(simplify(wording, glossed: &glossed))
        }
    }

    /// Sentences the keyword and trigger passes didn't already account for.
    ///
    /// Both of those render their own line, so anything they covered has to
    /// be dropped here or the card says it twice — which it did: Maddened
    /// Marauder printed "Tank When you play me, move a unit…" underneath
    /// the two clean lines that already said exactly that.
    ///
    /// Keywords are *removed* rather than expanded, because they already
    /// have a line above. A sentence mentioning "when" anywhere is a
    /// trigger sentence and belongs to the trigger pass. That last rule
    /// will also drop a static ability that happens to use the word "when"
    /// incidentally; no card in the set does, and losing a line is
    /// recoverable where printing it twice looks broken.
    private static func leftoverSentences(
        in text: String,
        alreadyCoveredBy triggers: [TriggeredAbility]
    ) -> [String] {
        var stripped = text.replacingOccurrences(
            of: #"\([^)]*\)"#, with: " ", options: .regularExpression
        )
        stripped = stripped.replacingOccurrences(
            of: #"\[[^\]]+\]"#, with: " ", options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: "\n", with: ". ")
            .components(separatedBy: ".")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { sentence in
                guard sentence.count > 3 else { return false }
                if sentence.range(of: #"\b(when|whenever)\b"#,
                                  options: [.regularExpression, .caseInsensitive]) != nil { return false }
                return !triggers.contains { $0.effect.localizedCaseInsensitiveContains(sentence) }
            }
            .map { $0.hasSuffix(".") ? $0 : $0 + "." }
    }

    // MARK: - Text helpers

    /// " (Rule 515.1)" is a maintainer's cross-reference to the rulebook.
    /// A player mid-game wants the instruction.
    private static func strippingRuleCitations(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\s\((?:Rule|Rules)\s[0-9][^)]*\)"#,
            with: "",
            options: .regularExpression
        )
    }

    /// Cards talk about themselves in the first person — "play me", "give
    /// me +3 Might", "I must be assigned combat damage first". Read back to
    /// a player that voice is confusing: "me" is the card, but the reader's
    /// instinct is that it's them.
    private static func thirdPerson(_ text: String) -> String {
        var out = text
        let swaps = [
            (#"\bmyself\b"#, "itself"),
            (#"\bme\b"#, "it"),
            (#"\bmy\b"#, "its"),
            (#"\bI\b"#, "it"),
        ]
        for (pattern, replacement) in swaps {
            out = out.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return out
    }

    private static func collapsingSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func lowerFirst(_ text: String) -> String {
        // Only when the word is ordinary prose — a card name or a keyword
        // keeps its capital.
        guard let first = text.first, first.isUppercase,
              text.dropFirst().prefix(1).first?.isUppercase != true else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
