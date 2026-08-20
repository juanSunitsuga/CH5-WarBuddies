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
        zone: Zone? = .base,
        exhausted: Int = 0,
        inArea: Int = 3
    ) -> PendingPlay.Observation {
        PendingPlay.Observation(
            cardStance: stance, cardZone: zone,
            exhaustedRunesNow: exhausted, runesInAreaNow: inArea
        )
    }

    /// The state the app previously accepted in silence.
    @Test("A unit sitting upright with nothing paid is not settled")
    func freshlyPlayedUnitOwesEverything() {
        let play = annie()
        let owed = play.outstanding(seen(.ready))

        #expect(!play.isSettled(seen(.ready)))
        #expect(owed.contains("turn it sideways"))
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
        // Names the destination: "recycle" is rules vocabulary that reads
        // as "discard" to anyone who hasn't memorised 594.
        #expect(play.outstanding(seen(.exhausted, inArea: 3))
            .contains("return 1 Chaos rune to your rune deck"))
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
        #expect(play.outstanding(seen(nil)).contains("turn it sideways"))
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

    // MARK: - Spells (150 / 556.2)

    private func spell(energy: Int = 1) -> PendingPlay {
        PendingPlay(
            name: "Gust", mustExhaustCard: false, mustGoToTrash: true,
            energyCost: energy, powerCost: 0, eligibleDomains: [],
            exhaustedRunesAtPlay: 0, runesInAreaAtPlay: 3
        )
    }

    /// 150: a Spell "creates a game effect according to its instructions
    /// and is then placed in the Trash." The trash step comes **after** the
    /// cost, not alongside it — asking for both at once would have the
    /// player sweep the card away before turning the runes that paid for
    /// it, leaving nothing on the table to say what the runes were for.
    @Test("A spell is paid for before it's asked to go to the trash")
    func spellIsPaidBeforeItIsBinned() {
        let gust = spell(energy: 1)

        let unpaid = gust.outstanding(seen(.ready, zone: .base, exhausted: 0))
        #expect(unpaid == ["exhaust 1 more rune"])
        #expect(!unpaid.contains { $0.contains("trash") })
    }

    @Test("Once paid, the spell is asked for the trash")
    func paidSpellIsAskedForTheTrash() {
        let gust = spell(energy: 1)
        let owed = gust.outstanding(seen(.ready, zone: .base, exhausted: 1))

        #expect(owed == ["put Gust in your trash"])
    }

    @Test("A spell in the trash with its cost paid is settled")
    func binnedSpellIsSettled() {
        let gust = spell(energy: 1)

        #expect(gust.isSettled(seen(.ready, zone: .trash, exhausted: 1)))
    }

    /// A Spell is never turned sideways — it has no board form to exhaust.
    @Test("A spell is never asked to be turned sideways")
    func spellIsNeverExhausted() {
        let owed = spell(energy: 0).outstanding(seen(.ready, zone: .base))

        #expect(!owed.contains { $0.contains("sideways") })
    }

    /// A free spell still has to reach the trash — payment isn't what makes
    /// the step apply.
    @Test("A free spell still has to reach the trash")
    func freeSpellStillGoesToTrash() {
        let free = spell(energy: 0)

        #expect(!free.isSettled(seen(.ready, zone: .base)))
        #expect(free.isSettled(seen(.ready, zone: .trash)))
    }

    // MARK: - How it reads on the bar

    @Test("An unsettled play blocks the phase and says what's left")
    func unsettledPlayBlocksTheActionPhase() {
        let progress = PhaseAutoDetector().settlement(of: annie(), observing: seen(.ready))

        #expect(progress.needsCorrection)
        #expect(!progress.isComplete)
        #expect(progress.headline == "You've played Annie.")
        #expect(progress.detail?.contains("turn it sideways and exhaust 2 more runes") == true)
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
