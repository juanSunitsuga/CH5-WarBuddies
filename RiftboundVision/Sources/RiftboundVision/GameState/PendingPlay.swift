import RiftboundExpertSystem

/// A card that has been put on the board but not yet paid for.
///
/// Playing a card is not one moment, it's a short sequence: the card lands,
/// then the player turns it sideways (139.4), then turns runes sideways for
/// its Energy (157.2.a), then returns runes to the deck for its Power
/// (157.2.b). The app used to accept the first step and say nothing about
/// the rest, so a unit could sit upright in the Base with its cost unpaid
/// and the game would carry on as if it were legal.
///
/// This holds the play open until every obligation is met. While one is
/// outstanding the Action Phase is blocked — not because the rules forbid
/// doing two things at once, but because a half-paid play is a board the
/// engine and the table disagree about, and every action taken on top of it
/// inherits that disagreement.
///
/// Progress is measured against **baselines taken as the card landed**, not
/// absolute counts. "Two runes are exhausted" is meaningless — a player may
/// have had runes exhausted already from an earlier play. "Two *more* runes
/// are exhausted than when this card hit the table" is the actual payment.
public struct PendingPlay: Sendable, Equatable {
    /// Matched by name rather than track ID: the played card arrives as a
    /// *new* track (picking it up ended the old one), and `ObservedTableEvent`
    /// carries a `CardDefID`, not a `TrackedObjectID`.
    public let name: String
    /// Rule 139.4: Units enter the board exhausted. False for Spells, Gear,
    /// and anything with Accelerate (717).
    public let mustExhaustCard: Bool
    /// Rule 150/556.2: a Spell "creates a game effect according to its
    /// instructions and is then placed in the Trash." It has no board form
    /// to leave behind — but it is physically laid down in the Base while
    /// it's being paid for and resolved, which is how it's played at a
    /// table, so the app follows the card rather than skipping to the end.
    public let mustGoToTrash: Bool
    public let energyCost: Int
    public let powerCost: Int
    public let eligibleDomains: [Domain]

    /// How many of the player's runes were already exhausted when this card
    /// landed. Energy paid = however many more are exhausted now.
    public let exhaustedRunesAtPlay: Int
    /// How many runes were in the rune area when this card landed.
    ///
    /// Recycling a rune returns it **to the rune deck** (154.2.b/594.1.b),
    /// so it leaves the rune area — Power paid is however many fewer are
    /// there now.
    ///
    /// Measured by the area shrinking rather than the deck growing, which
    /// would be the more direct evidence, because a deck is a *stack*: the
    /// detector sees one object on top of it however many cards are
    /// underneath, so runes arriving there are invisible. The rune area
    /// lays its runes out individually, which is the only place this is
    /// countable.
    public let runesInAreaAtPlay: Int

    public init(
        name: String,
        mustExhaustCard: Bool,
        mustGoToTrash: Bool = false,
        energyCost: Int,
        powerCost: Int,
        eligibleDomains: [Domain],
        exhaustedRunesAtPlay: Int,
        runesInAreaAtPlay: Int
    ) {
        self.name = name
        self.mustExhaustCard = mustExhaustCard
        self.mustGoToTrash = mustGoToTrash
        self.energyCost = energyCost
        self.powerCost = powerCost
        self.eligibleDomains = eligibleDomains
        self.exhaustedRunesAtPlay = exhaustedRunesAtPlay
        self.runesInAreaAtPlay = runesInAreaAtPlay
    }

    /// What the table looks like right now, as far as this play cares.
    public struct Observation: Sendable, Equatable {
        /// The played card's current stance, or `nil` if it can't be found
        /// on the table this frame.
        public let cardStance: CardStance?
        /// Where the played card is now — how a Spell reaching the Trash is
        /// confirmed.
        public let cardZone: Zone?
        public let exhaustedRunesNow: Int
        public let runesInAreaNow: Int

        public init(
            cardStance: CardStance?,
            cardZone: Zone? = nil,
            exhaustedRunesNow: Int,
            runesInAreaNow: Int
        ) {
            self.cardStance = cardStance
            self.cardZone = cardZone
            self.exhaustedRunesNow = exhaustedRunesNow
            self.runesInAreaNow = runesInAreaNow
        }
    }

    /// Runes turned sideways since this card landed (157.2.a).
    public func energyPaid(_ observation: Observation) -> Int {
        max(0, observation.exhaustedRunesNow - exhaustedRunesAtPlay)
    }

    /// Runes that have left the rune area since this card landed — i.e.
    /// been Recycled to the rune deck (157.2.b/594.1.b).
    public func powerPaid(_ observation: Observation) -> Int {
        max(0, runesInAreaAtPlay - observation.runesInAreaNow)
    }

    /// Whether the played card itself has been turned sideways yet.
    ///
    /// A card the camera can't currently see counts as *not* done. Treating
    /// "I lost sight of it" as "it's been exhausted" would let a play settle
    /// itself by the player's hand passing over the card.
    public func cardExhausted(_ observation: Observation) -> Bool {
        guard mustExhaustCard else { return true }
        return observation.cardStance == .exhausted
    }

    /// Everything still owed, in the order a player would do it, phrased as
    /// instructions. Empty means the play is settled.
    public func outstanding(_ observation: Observation) -> [String] {
        var steps: [String] = []

        if !cardExhausted(observation) {
            steps.append("turn \(name) sideways")
        }

        let energyLeft = energyCost - energyPaid(observation)
        if energyLeft > 0 {
            steps.append("exhaust \(energyLeft) more rune\(energyLeft == 1 ? "" : "s")")
        }

        var costOutstanding = false

        let powerLeft = powerCost - powerPaid(observation)
        if powerLeft > 0 {
            costOutstanding = true
            let named = eligibleDomains.map { $0.rawValue.capitalized }.joined(separator: " or ")
            // Says where the rune goes, not just the verb. "Recycle" is
            // rules vocabulary (594) that reads as "discard" to anyone who
            // hasn't memorised it; the rune goes back to the rune deck, and
            // a player following an instruction needs the destination.
            steps.append("return \(powerLeft) \(named.isEmpty ? "" : named + " ")rune\(powerLeft == 1 ? "" : "s") to your rune deck")
        }

        if energyLeft > 0 { costOutstanding = true }

        // 150: the Spell goes to the Trash once it has resolved — which is
        // *after* it's paid for, not instead of. Asking for both at once
        // would have the player sweep the card away before they've turned
        // the runes that paid for it, and then there's nothing on the table
        // to say what the runes were for.
        if mustGoToTrash, !costOutstanding, observation.cardZone != .trash {
            steps.append("put \(name) in your trash")
        }

        return steps
    }

    public func isSettled(_ observation: Observation) -> Bool {
        outstanding(observation).isEmpty
    }
}
