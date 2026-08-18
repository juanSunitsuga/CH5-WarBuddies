import Testing
import RiftboundExpertSystem
@testable import RiftboundVision

/// Auto-detect: watching the table during the four fixed phases (515) and
/// deciding when the player has finished the step.
@Suite("Phase Auto Detector")
struct PhaseAutoDetectorTests {

    private func card(
        _ id: TrackedObjectID,
        _ name: String,
        zone: Zone,
        stance: CardStance = .ready,
        slot: Int? = nil,
        owner: Player? = .player1,
        kind: CardKind = .unit
    ) -> ObservedCard {
        ObservedCard(id: id, name: name, zone: zone, battlefieldSlot: slot,
                     owner: owner, stance: stance, kind: kind)
    }

    // MARK: - Awaken (515.1)

    @Test("Awaken is incomplete while any of the player's cards is exhausted")
    func awakenWaitsForExhaustedCards() {
        let progress = PhaseAutoDetector().progress(for: .awaken, cards: [
            card(1, "Tibbers", zone: .base, stance: .exhausted),
            card(2, "Mystic Poro", zone: .base)
        ])

        #expect(!progress.isComplete)
        #expect(progress.headline == "1 card is still exhausted.")
    }

    @Test("Awaken completes once everything is upright")
    func awakenCompletesWhenAllReady() {
        let progress = PhaseAutoDetector().progress(for: .awaken, cards: [
            card(1, "Tibbers", zone: .base),
            card(2, "Fury Rune", zone: .runeArea, kind: .rune)
        ])

        #expect(progress.isComplete)
    }

    /// A hand is a fan of overlapping cards, and a deck is a stack — their
    /// bounding boxes read landscape often enough that counting them would
    /// make Awaken impossible to finish. The player can't "ready" a card in
    /// their hand anyway; 515.1 is about Game Objects they control on the
    /// board.
    @Test("A sideways-looking card in hand or a deck doesn't block Awaken")
    func awakenIgnoresNonBoardZones() {
        let progress = PhaseAutoDetector().progress(for: .awaken, cards: [
            card(1, "Gust", zone: .player1Hand, stance: .exhausted),
            card(2, "Deck", zone: .mainDeck, stance: .exhausted),
            card(3, "Trashed", zone: .trash, stance: .exhausted)
        ])

        #expect(progress.isComplete)
    }

    /// 515.1 is the *Turn Player's* Awaken — the opponent's exhausted cards
    /// stay exhausted and must not hold up the turn.
    @Test("The opponent's exhausted cards don't block your Awaken")
    func awakenIgnoresOpponentsCards() {
        let progress = PhaseAutoDetector().progress(for: .awaken, cards: [
            card(1, "Their Unit", zone: .base, stance: .exhausted, owner: .player2)
        ])

        #expect(progress.isComplete)
    }

    // MARK: - Beginning (630.2)

    @Test("Holding two battlefields scores two points")
    func holdingTwoBattlefieldsScoresTwo() {
        let progress = PhaseAutoDetector().progress(for: .beginning, cards: [
            card(1, "Tibbers", zone: .battlefield, slot: 0),
            card(2, "Mystic Poro", zone: .battlefield, slot: 1)
        ])

        #expect(progress.pointsToAward == 2)
        #expect(progress.isComplete)
    }

    /// 631: once per Battlefield per turn — two of your units on the *same*
    /// battlefield is one hold, not two.
    @Test("Two units on one battlefield is still one point")
    func twoUnitsOnOneBattlefieldScoreOnce() {
        let progress = PhaseAutoDetector().progress(for: .beginning, cards: [
            card(1, "Tibbers", zone: .battlefield, slot: 0),
            card(2, "Mystic Poro", zone: .battlefield, slot: 0)
        ])

        #expect(progress.pointsToAward == 1)
    }

    /// 181.4.b keeps a contested Battlefield with whoever already held it,
    /// and the camera can't see who that was — so claiming the point either
    /// way would be a guess. It says so instead.
    @Test("A contested battlefield scores nobody")
    func contestedBattlefieldScoresNobody() {
        let progress = PhaseAutoDetector().progress(for: .beginning, cards: [
            card(1, "Mine", zone: .battlefield, slot: 0, owner: .player1),
            card(2, "Theirs", zone: .battlefield, slot: 0, owner: .player2)
        ])

        #expect(progress.pointsToAward == 0)
        #expect(progress.detail?.contains("contested") == true)
    }

    @Test("Holding nothing scores nothing and still moves on")
    func holdingNothingCompletes() {
        let progress = PhaseAutoDetector().progress(for: .beginning, cards: [
            card(1, "Tibbers", zone: .base)
        ])

        #expect(progress.pointsToAward == 0)
        #expect(progress.isComplete)
    }

    // MARK: - Channel (515.3)

    /// The target is 2 *new* runes. An absolute count would be satisfied
    /// permanently after turn one, since the Rune Area only fills up.
    @Test("Channel counts new runes against the baseline, not the total")
    func channelCountsNewRunesOnly() {
        let detector = PhaseAutoDetector(channelBaseline: 4)
        let runes = (1...5).map { card($0, "Rune \($0)", zone: .runeArea, kind: .rune) }

        let progress = detector.progress(for: .channel, cards: runes)

        #expect(!progress.isComplete)
        #expect(progress.headline == "1 of 2 runes channeled.")
    }

    @Test("Channel completes once both new runes are in the rune area")
    func channelCompletesAtTwo() {
        let detector = PhaseAutoDetector(channelBaseline: 4)
        let runes = (1...6).map { card($0, "Rune \($0)", zone: .runeArea, kind: .rune) }

        #expect(detector.progress(for: .channel, cards: runes).isComplete)
    }

    /// 645.7: the player going last channels an extra rune on their first
    /// turn, so the target isn't always 2.
    @Test("A three-rune first turn isn't complete at two")
    func firstTurnBonusRequiresThree() {
        let detector = PhaseAutoDetector(channelBaseline: 0, runesToChannel: 3)
        let runes = (1...2).map { card($0, "Rune \($0)", zone: .runeArea, kind: .rune) }

        #expect(!detector.progress(for: .channel, cards: runes).isComplete)
    }

    // MARK: - Draw and Action never auto-complete

    /// A drawn card lands in a fanned hand, where "the hand grew" is not
    /// reliably distinguishable from a card being fanned into view. Guessing
    /// wrong desyncs the deck count silently, so this one stays manual.
    @Test("Draw does not auto-complete")
    func drawStaysManual() {
        #expect(!PhaseAutoDetector().progress(for: .draw, cards: []).isComplete)
    }

    /// 516.2: the Action Phase has no completion condition — it ends when
    /// the player says so (516.6), and no amount of watching the table can
    /// tell you someone is finished.
    @Test("Action never auto-completes")
    func actionNeverAutoCompletes() {
        #expect(!PhaseAutoDetector().progress(for: .action, cards: []).isComplete)
    }

    // MARK: - Paying for a play

    @Test("An affordable card is announced as a cost to pay, not a problem")
    func affordablePlayTellsYouWhatToPay() {
        let annie = ObservedCard(id: 1, name: "Annie", zone: .base, energyCost: 2)
        let progress = PhaseAutoDetector().paymentProgress(for: annie, runes: [
            ObservedRune(domain: .fury, stance: .ready),
            ObservedRune(domain: .fury, stance: .ready)
        ])

        #expect(!progress.needsCorrection)
        #expect(progress.headline.contains("exhaust 2 runes"))
    }

    @Test("An unaffordable card tells the player to put it back in hand")
    func unaffordablePlayAsksForTheCardBack() {
        let annie = ObservedCard(id: 1, name: "Annie", zone: .base, energyCost: 3)
        let progress = PhaseAutoDetector().paymentProgress(for: annie, runes: [
            ObservedRune(domain: .fury, stance: .ready)
        ])

        #expect(progress.needsCorrection)
        #expect(progress.headline == "Put Annie back in your hand.")
        #expect(progress.detail?.contains("3 energy") == true)
    }

    @Test("A missing domain names the domain the player needs")
    func missingDomainIsNamed() {
        let card = ObservedCard(id: 1, name: "Final Spark", zone: .base,
                                powerCost: 1, eligibleDomains: [.mind])
        let progress = PhaseAutoDetector().paymentProgress(for: card, runes: [
            ObservedRune(domain: .fury, stance: .ready)
        ])

        #expect(progress.needsCorrection)
        #expect(progress.detail?.contains("Mind") == true)
    }
}
