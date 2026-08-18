import Testing
import RiftboundExpertSystem
@testable import RiftboundVision

/// Playing a card is a sequence, not a moment: the card lands, the player
/// turns it sideways (139.4), turns runes sideways for its Energy
/// (157.2.a), and returns runes to the deck for its Power (157.2.b).
///
/// The app used to accept the first step and say nothing about the rest, so
/// a unit could sit upright in the Base with its cost unpaid while the game
/// carried on as if that were legal.
@Suite("Pending Play")
struct PendingPlayTests {

    /// Annie: 2 energy, played with 3 runes in the area, none exhausted.
    private func annie(
        mustExhaustCard: Bool = true,
        energy: Int = 2,
        power: Int = 0,
        domains: [Domain] = [],
        exhaustedAtPlay: Int = 0,
        inAreaAtPlay: Int = 3
    ) -> PendingPlay {
        PendingPlay(
            name: "Annie", mustExhaustCard: mustExhaustCard,
            energyCost: energy, powerCost: power, eligibleDomains: domains,
            exhaustedRunesAtPlay: exhaustedAtPlay, runesInAreaAtPlay: inAreaAtPlay
        )
    }

    private func seen(
        _ stance: CardStance?,
        exhausted: Int = 0,
        inArea: Int = 3
    ) -> PendingPlay.Observation {
        PendingPlay.Observation(cardStance: stance, exhaustedRunesNow: exhausted, runesInAreaNow: inArea)
    }

    /// The state the app previously accepted in silence.
    @Test("A unit sitting upright with nothing paid is not settled")
    func freshlyPlayedUnitOwesEverything() {
        let play = annie()
        let owed = play.outstanding(seen(.ready))

        #expect(!play.isSettled(seen(.ready)))
        #expect(owed.contains("turn Annie sideways"))
        #expect(owed.contains("exhaust 2 more runes"))
    }

    @Test("Turning the unit sideways settles that step but not the cost")
    func exhaustingTheUnitIsOnlyHalfOfIt() {
        let play = annie()
        let owed = play.outstanding(seen(.exhausted))

        #expect(!owed.contains { $0.contains("sideways") })
        #expect(owed.contains("exhaust 2 more runes"))
    }

    @Test("A play is settled once the unit and its runes are all turned")
    func settledWhenEverythingIsTurned() {
        let play = annie()
        #expect(play.isSettled(seen(.exhausted, exhausted: 2)))
    }

    /// The count that matters is what changed since the card landed. A
    /// player who already had runes exhausted from an earlier play must not
    /// have those counted twice.
    @Test("Energy is measured from the runes exhausted when the card landed")
    func energyIsRelativeToTheBaseline() {
        // Two runes were already sideways when Annie hit the table.
        let play = annie(exhaustedAtPlay: 2)

        // Still two — nothing has been paid.
        #expect(!play.isSettled(seen(.exhausted, exhausted: 2)))
        #expect(play.outstanding(seen(.exhausted, exhausted: 2)).contains("exhaust 2 more runes"))

        // Four now: two more than at play, so the cost is met.
        #expect(play.isSettled(seen(.exhausted, exhausted: 4)))
    }

    /// Recycling takes the rune off the board (594.1.b), so power shows up
    /// as the rune area shrinking rather than as a stance change.
    @Test("Power is paid by runes leaving the rune area")
    func powerIsPaidByRunesLeaving() {
        let play = annie(energy: 0, power: 1, domains: [.chaos], inAreaAtPlay: 3)

        #expect(!play.isSettled(seen(.exhausted, inArea: 3)))
        #expect(play.outstanding(seen(.exhausted, inArea: 3)).contains("recycle 1 Chaos rune"))
        #expect(play.isSettled(seen(.exhausted, inArea: 2)))
    }

    @Test("Partial payment still names what's left")
    func partialPaymentNamesTheRemainder() {
        let play = annie(energy: 3)
        let owed = play.outstanding(seen(.exhausted, exhausted: 1))

        #expect(owed == ["exhaust 2 more runes"])
    }

    /// Rule 717: a unit with Accelerate enters ready, so nothing is owed
    /// for the card itself.
    @Test("A card that enters ready owes nothing for its own stance")
    func acceleratedCardOwesNoExhaust() {
        let play = annie(mustExhaustCard: false, energy: 0)

        #expect(play.isSettled(seen(.ready)))
    }

    /// Losing sight of the card must not settle the play. Treating "I can't
    /// see it" as "it's been turned" would let a hand passing over the
    /// table pay a cost.
    @Test("A card the camera can't find is not treated as exhausted")
    func unseenCardDoesNotSettleItself() {
        let play = annie(energy: 0)

        #expect(!play.isSettled(seen(nil)))
        #expect(play.outstanding(seen(nil)).contains("turn Annie sideways"))
    }

    /// Runes coming *back* — a miscount, or the player putting one back —
    /// must not read as negative payment and quietly reduce what's owed.
    @Test("Runes reappearing don't count as negative payment")
    func reappearingRunesDoNotUnderflow() {
        let play = annie(energy: 1, exhaustedAtPlay: 2)

        // Fewer exhausted than at play: nothing has been paid, not -1.
        #expect(play.energyPaid(seen(.exhausted, exhausted: 1)) == 0)
        #expect(!play.isSettled(seen(.exhausted, exhausted: 1)))
    }

    // MARK: - How it reads on the bar

    @Test("An unsettled play blocks the phase and says what's left")
    func unsettledPlayBlocksTheActionPhase() {
        let progress = PhaseAutoDetector().settlement(of: annie(), observing: seen(.ready))

        #expect(progress.needsCorrection)
        #expect(!progress.isComplete)
        #expect(progress.headline.contains("turn Annie sideways and exhaust 2 more runes"))
    }

    @Test("A settled play releases the phase")
    func settledPlayReleasesThePhase() {
        let progress = PhaseAutoDetector().settlement(
            of: annie(), observing: seen(.exhausted, exhausted: 2)
        )

        #expect(progress.isComplete)
        #expect(!progress.needsCorrection)
        #expect(progress.headline.contains("paid for"))
    }
}
