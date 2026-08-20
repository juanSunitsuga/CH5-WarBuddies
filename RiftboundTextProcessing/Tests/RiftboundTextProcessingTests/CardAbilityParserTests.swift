import Testing
import RiftboundExpertSystem
@testable import RiftboundTextProcessing

/// Card text → the closed set of Game Actions (586–607). This is the parse
/// step `parseAbility` returned `[]` for, so no card ability ever reached
/// the player or the engine.
@Suite("Card Ability Parser")
struct CardAbilityParserTests {

    @Test("Draw is read as a Draw action with its count")
    func readsDraw() {
        let reading = CardAbilityParser.read("Draw 2 cards.")

        #expect(reading.abilities.count == 1)
        #expect(reading.abilities.first?.action == "Draw")
        #expect(reading.abilities.first?.summary == "Draw 2 cards.")
    }

    @Test("Channel is read with its count and whether the rune enters exhausted")
    func readsChannelExhausted() {
        let reading = CardAbilityParser.read("Channel 1 rune exhausted.")

        #expect(reading.abilities.first?.action == "Channel")
        #expect(reading.abilities.first?.summary.contains("exhausted") == true)
    }

    @Test("Several sentences produce several abilities")
    func readsMultipleSentences() {
        let reading = CardAbilityParser.read("Deal 2 damage. Draw 1 card.")

        #expect(reading.abilities.count == 2)
        #expect(reading.abilities.map(\.action).contains("Deal damage"))
        #expect(reading.abilities.map(\.action).contains("Draw"))
    }

    /// Rules 718/725: the keyword decides *when* the card can be played,
    /// which is the difference between "I can do this now" and "only during
    /// a showdown."
    @Test("Action and Reaction are carried as timing, not as separate abilities")
    func readsTiming() {
        let reaction = CardAbilityParser.read("[Reaction] Draw 1 card.")
        #expect(reaction.abilities.first?.timing?.contains("Reaction") == true)

        let action = CardAbilityParser.read("[Action] Draw 1 card.")
        #expect(action.abilities.first?.timing?.contains("Action") == true)
    }

    /// Keywords are abilities even though their text is one word — a Tank
    /// unit genuinely does something (626.1.d.1).
    @Test("Keywords are read as abilities in their own right")
    func readsKeywords() {
        let reading = CardAbilityParser.read("[Tank] [Assault 2]")
        let summaries = reading.abilities.map(\.summary)

        #expect(summaries.contains { $0.contains("Tank") })
        #expect(summaries.contains { $0.contains("Assault 2") })
    }

    /// CLAUDE.md point 4: text that doesn't map onto a Game Action is a
    /// parse failure to surface, not a primitive to invent. A card whose
    /// ability shows as unread is a gap someone can fix; one that's
    /// silently invented is a wrong game state nobody can trace.
    @Test("Text with a game verb but no known shape is reported, not invented")
    func unparsedTextIsSurfaced() {
        let reading = CardAbilityParser.read("Whenever you draw your third card in a turn, something happens")

        #expect(reading.abilities.isEmpty)
        #expect(!reading.unparsed.isEmpty)
    }

    @Test("Flavourless text produces nothing at all")
    func emptyTextProducesNothing() {
        #expect(CardAbilityParser.read("").isEmpty)
        #expect(CardAbilityParser.read("   ").isEmpty)
    }

    // MARK: - The bridge into the engine

    /// The untargeted cases are the ones the engine can already apply, so
    /// they're the ones worth producing today.
    @Test("Draw becomes an EffectInstruction the engine can act on")
    func drawBecomesAnInstruction() {
        let instructions = CardAbilityParser.instructions(for: "Draw 2 cards.")

        guard case .draw(let count)? = instructions.first else {
            Issue.record("Expected a .draw instruction, got \(instructions)")
            return
        }
        #expect(count == 2)
    }

    @Test("Channel becomes an EffectInstruction carrying its stance")
    func channelBecomesAnInstruction() {
        guard case .channelRune(let count, let exhausted)? =
                CardAbilityParser.instructions(for: "Channel 1 rune exhausted.").first else {
            Issue.record("Expected a .channelRune instruction")
            return
        }
        #expect(count == 1)
        #expect(exhausted)
    }

    @Test("A generic 'a unit' target resolves to chosenUnit(.any)")
    func genericUnitTargetResolves() {
        guard case .killUnit(let target)? = CardAbilityParser.instructions(for: "Kill a unit.").first else {
            Issue.record("Expected a .killUnit instruction")
            return
        }
        #expect(target == .chosenUnit())
    }

    // MARK: - Real printed-text patterns (pressure-tested against the
    // bundled card sample, not invented shapes)

    /// "Deal 6 to a unit at a battlefield." — Falling Comet's actual
    /// printed text. The literal word "damage" never appears; an earlier
    /// version of this pattern required it and so never actually matched
    /// real Riftbound text at all.
    @Test("Deal N to a unit is read as damage with no literal 'damage' required")
    func damageWithoutTheWordDamage() {
        guard case .dealDamage(let amount, let target)? =
                CardAbilityParser.instructions(for: "Deal 6 to a unit at a battlefield.").first else {
            Issue.record("Expected a .dealDamage instruction")
            return
        }
        #expect(amount == 6)
        #expect(target == .chosenUnit())
    }

    /// "Deal 3 to all enemy units at a battlefield." — Firestorm's text.
    @Test("'all enemy units' resolves to allUnits(.enemy)")
    func allEnemyUnitsTarget() {
        guard case .dealDamage(_, let target)? =
                CardAbilityParser.instructions(for: "Deal 3 to all enemy units at a battlefield.").first else {
            Issue.record("Expected a .dealDamage instruction")
            return
        }
        #expect(target == .allUnits(.enemy))
    }

    /// "When you play a spell, give me +1 Might this turn." — Ravenbloom
    /// Student's text. "give me" is the self-reference this reads.
    @Test("'give me' resolves to .source")
    func selfReferenceResolvesToSource() {
        guard case .buff(let target)? = CardAbilityParser.instructions(for: "Give me +1 Might this turn.").first else {
            Issue.record("Expected a .buff instruction")
            return
        }
        #expect(target == .source)
    }

    /// "Give two friendly units each +2 Might this turn." — Back to
    /// Back's text. This reader doesn't disambiguate "N units, each..."
    /// (a bounded count) from "each enemy unit" (unbounded) — both share
    /// the word "each" — so it reads as the broader `.allUnits(.friendly)`
    /// rather than the exact count of 2. Flagged here as a known
    /// imprecision (could over-apply on a board with more than 2 friendly
    /// units) rather than silently assumed correct.
    @Test("'N units, each ...' is read as allUnits — a known imprecision, not a crash or a guess at the exact count")
    func countedEachPhrasingReadsAsAllUnits() {
        guard case .buff(let target)? = CardAbilityParser.instructions(for: "Give two friendly units each +2 Might this turn.").first else {
            Issue.record("Expected a .buff instruction")
            return
        }
        #expect(target == .allUnits(.friendly))
    }

    /// "up to two units" — Singularity's text — spells the count out
    /// rather than using a digit, which `number(after:in:)` alone can't
    /// read; this is the pattern `number(afterSpelledOutOrDigit:in:)`
    /// exists for.
    @Test("'up to N units' resolves to upToUnits(maximum:), including a spelled-out N")
    func upToNUnitsResolvesSpelledOut() {
        guard case .dealDamage(_, let target)? =
                CardAbilityParser.instructions(for: "Deal 6 to each of up to two units.").first else {
            Issue.record("Expected a .dealDamage instruction")
            return
        }
        #expect(target == .upToUnits(maximum: 2))
    }
}
