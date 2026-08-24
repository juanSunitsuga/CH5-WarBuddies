import Testing
@testable import RiftboundTextProcessing

/// Every text in here is copied off a card in `CardData`, not invented, so
/// a passing test means the parser handles wording the app will actually
/// meet rather than wording that suits the parser.
struct CardAbilityTriggerTests {

    // MARK: - The trigger the camera can see

    /// Noxian Drummer, the card that motivated this: moving it onto a
    /// battlefield is a zone change, which is precisely what the tracker
    /// reports, so this one can fire on its own.
    @Test("A move-to-battlefield trigger is read, with its effect")
    func movingToABattlefield() {
        let triggers = CardAbilityParser.triggers(
            in: "When I move to a battlefield, play a 1 :rb_might: Recruit unit token here. (It is also at the battlefield.)"
        )

        #expect(triggers.count == 1)
        #expect(triggers.first?.trigger == .movedToBattlefield)
        #expect(triggers.first?.effect == "Play a 1 Might Recruit unit token here.")
    }

    @Test("Play-me triggers are recognised")
    func playedFromHand() {
        let triggers = CardAbilityParser.triggers(in: "When you play me, deal 3 to all units at battlefields.")

        #expect(triggers.first?.trigger == .played)
        #expect(triggers.first?.effect == "Deal 3 to all units at battlefields.")
    }

    // MARK: - The triggers it can't

    /// The point of `unobservable` is that these stay *readable* while never
    /// firing. A camera cannot see an attack declared.
    @Test("Triggers the camera can't witness are kept but marked unobservable")
    func unobservableTriggers() {
        let attack = CardAbilityParser.triggers(
            in: "When I attack, give me +2 :rb_might: this turn if there is a ready enemy unit here."
        )
        #expect(attack.first?.trigger.isObservable == false)
        #expect(attack.first?.effect.contains("+2 Might") == true)

        let conquer = CardAbilityParser.triggers(
            in: "When you conquer, if you have 4+ units at that battlefield, draw 2."
        )
        #expect(conquer.first?.trigger.isObservable == false)
    }

    // MARK: - Markup

    @Test("Energy tokens carry their own value")
    func energyMarkup() {
        #expect(CardAbilityParser.plainMarkup("costs :rb_energy_5: or more") == "costs 5 Energy or more")
    }

    @Test("An unknown icon token is dropped rather than printed raw")
    func unknownMarkup() {
        #expect(CardAbilityParser.plainMarkup("gain :rb_wibble: now") == "gain now")
    }

    // MARK: - Not a trigger

    @Test("Text with no when-clause yields nothing")
    func noTrigger() {
        #expect(CardAbilityParser.triggers(in: "You may play me to an open battlefield.").isEmpty)
        #expect(CardAbilityParser.triggers(in: "").isEmpty)
    }

    /// Reminder text restates a keyword the card already has; firing on it
    /// would tell the player the same thing twice.
    @Test("Bracketed reminder text doesn't produce a second trigger")
    func remindersIgnored() {
        let triggers = CardAbilityParser.triggers(
            in: "[Vision] (When you play me, look at the top card of your Main Deck.)You may play me to an open battlefield."
        )
        #expect(triggers.isEmpty)
    }
}
