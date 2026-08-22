import Testing
@testable import RiftboundTextProcessing

/// Card text here is copied out of `CardData`, so passing means the plain
/// wording holds for cards the app will actually meet.
struct CardPlainLanguageTests {

    @Test("A triggered ability splits its condition from its effect")
    func triggerReadsAsWhenThen() {
        let out = CardPlainLanguage.explain(
            "When I move to a battlefield, play a 1 :rb_might: Recruit unit token here. (It is also at the battlefield.)"
        )

        #expect(out.lines.contains { $0.hasPrefix("When you move it to a battlefield:") })
        // The icon markup is gone and the jargon is explained once.
        #expect(out.lines.contains { $0.contains("1 Might Recruit unit token") })
        #expect(out.lines.contains { $0.hasSuffix("A token is a unit created during play.") })
        #expect(out.unexplained.isEmpty)
    }

    @Test("Keywords are explained from the rulebook, ahead of the card's own text")
    func keywordsExplained() {
        let out = CardPlainLanguage.explain(
            "[Tank] (I must be assigned combat damage first.)When you play me, move a unit from a battlefield to its base."
        )

        #expect(out.lines.first == "Tank — this unit takes combat damage first.")
        #expect(out.lines.contains { $0.hasPrefix("When you play it:") })
    }

    @Test("Shield and Assault carry their number through")
    func valuedKeywords() {
        #expect(CardPlainLanguage.explain("[Shield 2]").lines == ["Shield 2 — it gets +2 Might while defending."])
        #expect(CardPlainLanguage.explain("[Assault 2]").lines == ["Assault 2 — it gets +2 Might while attacking."])
    }

    /// The whole point of the `unexplained` channel: a keyword with no
    /// grounded wording must not be paraphrased from its name.
    @Test("An unknown keyword is reported, not guessed at")
    func unknownKeywordSurfaces() {
        let out = CardPlainLanguage.explain("[Add] something happens.")

        #expect(out.unexplained == ["[Add]"])
        #expect(!out.lines.contains { $0.contains("Add —") })
    }

    // MARK: - Instructions

    @Test("Rule citations are dropped and jargon is explained")
    func instructionsGetPlainer() {
        let out = CardPlainLanguage.simplify(
            "Put 2 runes from your rune deck into your rune area, face up and ready (Rule 515.3)."
        )

        #expect(!out.contains("Rule 515.3"))
        #expect(!out.contains("("))
    }

    // MARK: - Regressions found by reading the real output

    /// The gloss used to be spliced in where the word sat, producing "every
    /// exhausted (turn it sideways) card". A gloss has to be grammatical
    /// where it lands, so it goes at the end as its own sentence.
    @Test("A gloss is appended as a sentence, not spliced mid-clause")
    func glossIsGrammatical() {
        let out = CardPlainLanguage.simplify(
            "Turn every exhausted card you control upright — units, gear and runes (Rule 515.1)."
        )

        #expect(out == "Turn every exhausted card you control upright — units, gear and runes. Exhausted means turned sideways.")
    }

    /// Maddened Marauder printed a third line — "Tank When you play me, move
    /// a unit…" — restating the two clean lines above it.
    @Test("A keyword-prefixed trigger sentence isn't also printed raw")
    func noDuplicateLeftover() {
        let out = CardPlainLanguage.explain(
            "[Tank] (I must be assigned combat damage first.)When you play me, move a unit from a battlefield to its base."
        )

        #expect(out.lines.count == 2)
        #expect(!out.lines.contains { $0.contains("play me") })
    }

    @Test("Cards stop talking about themselves in the first person")
    func thirdPerson() {
        let out = CardPlainLanguage.explain("You may play me to an open battlefield.")

        #expect(out.lines == ["You may play it to an open battlefield."])
    }

    /// The condition half of an unobservable trigger was skipping the
    /// markup pass, so "costs :rb_energy_5: or more" reached the panel raw.
    @Test("An unobservable trigger's condition is cleaned up too")
    func unobservableConditionCleaned() {
        let out = CardPlainLanguage.explain(
            "When you play a spell that costs :rb_energy_5: or more, give me +3 :rb_might: this turn."
        )

        #expect(out.lines == ["When you play a spell that costs 5 Energy or more: give it +3 Might this turn."])
    }

    @Test("A jargon term is explained once, not every time it appears")
    func glossedOnce() {
        let out = CardPlainLanguage.simplify("Exhaust a rune, then exhaust another rune.")

        // Twice would read as a malfunction.
        #expect(out.components(separatedBy: "Exhausted means turned sideways.").count == 2)
    }

    @Test("Text with nothing to explain is left alone")
    func nothingToDo() {
        #expect(CardPlainLanguage.explain("").isEmpty)
        #expect(CardPlainLanguage.simplify("Draw 1 card.") == "Draw 1 card.")
    }
}

/// Tapping a card asks "what is this?". These cover the answer.
struct CardSummaryTests {

    @Test("Name and type lead, then cost, then what it does")
    func fullCard() {
        let out = CardPlainLanguage.describeCard(
            name: "Noxian Drummer",
            type: "Unit",
            energyCost: 2,
            powerCost: 1,
            printedText: "When I move to a battlefield, play a 1 :rb_might: Recruit unit token here. (It is also at the battlefield.)"
        )

        #expect(out.headline == "Noxian Drummer — Unit")
        #expect(out.detail.hasPrefix("To play it, exhaust 2 runes and recycle 1 rune to the bottom of your rune deck."))
        #expect(out.detail.contains("When you move it to a battlefield: play a 1 Might Recruit unit token here."))
    }

    /// A cost is two physical acts, not two numbers. "1 Power" is a symbol
    /// to go and look up; "recycle 1 Fury rune to the bottom of your rune
    /// deck" is something a player can do — and it names the destination,
    /// because read as "discard" the rune goes somewhere it can't return
    /// from (594.1.b).
    @Test("A cost says what to do with the runes, not which symbols to count")
    func costIsAnInstruction() {
        let energyOnly = CardPlainLanguage.describeCard(
            name: "A", type: "Spell", energyCost: 3, powerCost: 0, printedText: ""
        )
        #expect(energyOnly.detail.hasPrefix("To play it, exhaust 3 runes."))

        let powerOnly = CardPlainLanguage.describeCard(
            name: "B", type: "Spell", energyCost: nil, powerCost: 2, printedText: ""
        )
        #expect(powerOnly.detail.hasPrefix("To play it, recycle 2 runes to the bottom of your rune deck."))
    }

    /// 130.3: Power is usually domain-locked, so which rune matters.
    @Test("A domain-locked Power cost names the domain")
    func costNamesTheDomain() {
        let single = CardPlainLanguage.describeCard(
            name: "Annie - Fiery", type: "Unit",
            energyCost: 5, powerCost: 1, powerDomains: ["Fury"], printedText: ""
        )
        #expect(single.detail.contains("recycle 1 Fury rune to the bottom of your rune deck"))

        // Multi-domain cards accept either, and the line has to say so.
        let either = CardPlainLanguage.describeCard(
            name: "Decisive Strike", type: "Spell",
            energyCost: 5, powerCost: 1, powerDomains: ["Body", "Order"], printedText: ""
        )
        #expect(either.detail.contains("recycle 1 Body or Order rune"))
    }

    /// A domain on a card with no Power cost isn't a cost to pay.
    @Test("No Power cost means no recycle clause, domain or not")
    func noPowerNoRecycle() {
        let out = CardPlainLanguage.describeCard(
            name: "Back to Back", type: "Spell",
            energyCost: 3, powerCost: 0, powerDomains: ["Order"], printedText: ""
        )
        #expect(!out.detail.contains("recycle"))
    }

    /// A blank detail would read as a panel that failed to load, and send
    /// the player looking at the card for text that isn't there.
    @Test("A card with no cost and no text still says something")
    func emptyCard() {
        let out = CardPlainLanguage.describeCard(
            name: "Fury Rune", type: "Rune", energyCost: nil, powerCost: 0, printedText: ""
        )

        #expect(out.headline == "Fury Rune — Rune")
        #expect(out.detail == "No printed ability — it does what its type does, nothing more.")
    }

    @Test("A missing type doesn't leave a dangling dash")
    func noType() {
        #expect(CardPlainLanguage.describeCard(name: "Mystery", type: "", energyCost: nil, powerCost: 0, printedText: "")
            .headline == "Mystery")
    }

    /// Same rule as everywhere else: an unglossed keyword is shown as
    /// printed, never paraphrased from its name.
    @Test("An unexplained keyword still reaches the player")
    func unexplainedCarried() {
        let out = CardPlainLanguage.describeCard(
            name: "Odd One", type: "Unit", energyCost: 1, powerCost: 0, printedText: "[Add] something happens."
        )

        #expect(out.detail.contains("[Add]"))
    }
}

/// The tapped-card panel showed "A token is a unit created during play."
/// twice, and explained "exhausted" — a word that came from the app's own
/// cost sentence, not from the card. Both were one bug: the summary was
/// already worded, and the band ran the plain-language pass over it again
/// with a fresh gloss set.
struct DoubleProcessingTests {

    @Test("Running the pass over already-glossed text doesn't repeat the gloss")
    func glossIsNotRepeated() {
        let once = CardPlainLanguage.simplify("Play a 1 Might Recruit unit token here.")
        #expect(once.components(separatedBy: "A token is a unit created during play.").count == 2)

        // What the band was doing to the card summary.
        let twice = CardPlainLanguage.simplify(once)
        #expect(twice.components(separatedBy: "A token is a unit created during play.").count == 2)
    }

    /// The cost sentence is generated by this file, so glossing it explains
    /// our own wording back to the player.
    @Test("A card summary is final and needs no second pass")
    func summaryIsFinal() {
        let out = CardPlainLanguage.describeCard(
            name: "Noxian Drummer", type: "Unit",
            energyCost: 3, powerCost: 0,
            printedText: "When I move to a battlefield, play a 1 :rb_might: Recruit unit token here."
        )

        #expect(out.detail.hasPrefix("To play it, exhaust 3 runes."))
        // One gloss, for a word the card used — not for one we introduced.
        #expect(out.detail.components(separatedBy: "A token is").count == 2)
        #expect(!out.detail.contains("Exhausted means turned sideways."))
    }
}

/// Damage bonuses granted by cards already on the table.
///
/// Every text here is copied from `CardData`. The bonus is printed on the
/// card granting it, never on the card being played, so this is exactly the
/// arithmetic a player misses — and they find out after the damage is dealt.
struct DamageBonusTests {

    private let annieFiery = "Your spells and abilities deal 1 Bonus Damage. (Each instance of damage the spell deals is increased by 1.)"
    private let voidGate = "Spells and abilities affecting units here each deal 1 Bonus Damage. (Each instance of damage the spell deals is increased by 1.)"
    private let tibbers = "When you play me, deal 3 to all units at battlefields."

    // MARK: - Reading the bonus

    @Test("An unqualified bonus applies anywhere; 'here' scopes it to a battlefield")
    func scopeIsRead() {
        #expect(CardAbilityParser.damageBonus(in: annieFiery) == DamageBonus(amount: 1, scope: .anywhere))
        #expect(CardAbilityParser.damageBonus(in: voidGate) == DamageBonus(amount: 1, scope: .atThisBattlefield))
    }

    /// The misparse this fixes: a standing modifier read as an instruction
    /// told the player to deal 1 damage the card never asks for.
    @Test("A Bonus Damage clause is not an instruction to deal damage")
    func bonusIsNotAnInstruction() {
        #expect(CardAbilityParser.damageDealt(in: annieFiery) == nil)
        #expect(!CardAbilityParser.read(annieFiery).abilities.contains { $0.action == "Deal damage" })

        // A card that really does deal damage still reads as one.
        #expect(CardAbilityParser.damageDealt(in: tibbers) == 3)
    }

    @Test("A card with no bonus grants none")
    func noBonus() {
        #expect(CardAbilityParser.damageBonus(in: tibbers) == nil)
        #expect(CardAbilityParser.damageBonus(in: "") == nil)
    }

    // MARK: - The advice

    @Test("A bonus in play is quoted as the number the card will actually deal")
    func adviceNamesTheNewTotal() {
        let advice = CardPlainLanguage.damageAdvice(
            base: 3,
            bonuses: [ActiveDamageBonus(source: "Annie - Fiery", bonus: DamageBonus(amount: 1, scope: .anywhere))]
        )
        #expect(advice == "Deals 4, not 3 — Annie - Fiery in play.")
    }

    /// A battlefield bonus only applies where that battlefield is, so
    /// folding it into one total would overstate the damage everywhere else.
    @Test("A battlefield bonus is reported separately, not folded into the total")
    func battlefieldBonusIsSeparate() {
        let both = CardPlainLanguage.damageAdvice(
            base: 3,
            bonuses: [
                ActiveDamageBonus(source: "Annie - Fiery", bonus: DamageBonus(amount: 1, scope: .anywhere)),
                ActiveDamageBonus(source: "Void Gate", bonus: DamageBonus(amount: 1, scope: .atThisBattlefield)),
            ]
        )
        #expect(both == "Deals 4, not 3 — Annie - Fiery in play. At Void Gate, 5.")

        let onlyThere = CardPlainLanguage.damageAdvice(
            base: 3,
            bonuses: [ActiveDamageBonus(source: "Void Gate", bonus: DamageBonus(amount: 1, scope: .atThisBattlefield))]
        )
        #expect(onlyThere == "Deals 4, not 3, at Void Gate.")
    }

    @Test("Nothing to say when no bonus is live, or the card deals no damage")
    func silentWhenIrrelevant() {
        #expect(CardPlainLanguage.damageAdvice(base: 3, bonuses: []) == nil)
        #expect(CardPlainLanguage.damageAdvice(base: 0, bonuses: [
            ActiveDamageBonus(source: "Annie - Fiery", bonus: DamageBonus(amount: 1, scope: .anywhere))
        ]) == nil)
    }

    /// End to end: tap Tibbers with Annie - Fiery and Void Gate on the table.
    @Test("Tapping a damage card quotes the real number")
    func tappedCardCarriesTheAdvice() {
        let out = CardPlainLanguage.describeCard(
            name: "Tibbers", type: "Unit", energyCost: 6, powerCost: 1, powerDomains: ["Fury"],
            printedText: tibbers,
            activeBonuses: [
                ActiveDamageBonus(source: "Annie - Fiery", bonus: DamageBonus(amount: 1, scope: .anywhere)),
                ActiveDamageBonus(source: "Void Gate", bonus: DamageBonus(amount: 1, scope: .atThisBattlefield)),
            ]
        )
        #expect(out.detail.hasSuffix("Deals 4, not 3 — Annie - Fiery in play. At Void Gate, 5."))
    }
}
