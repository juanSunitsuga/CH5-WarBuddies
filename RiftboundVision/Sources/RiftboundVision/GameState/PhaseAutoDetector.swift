import RiftboundExpertSystem

/// One card on the table, resolved far enough for the auto-detector to
/// reason about it. Built by the app from a `TrackedObject` plus whatever
/// the `CardDatabase` knows about its label — assembled by the caller so
/// this type stays a pure function of what was seen, and stays testable
/// without a camera.
public struct ObservedCard: Sendable, Equatable {
    public let id: TrackedObjectID
    public let name: String
    public let zone: Zone
    /// Which Battlefield, when `zone == .battlefield`. `Zone` collapses all
    /// Battlefields into one case, but Holding scores *per Battlefield*
    /// (630.2/631), so the slot has to survive.
    public let battlefieldSlot: Int?
    /// Whose calibrated region this is, when the region has an owner.
    public let owner: Player?
    public let stance: CardStance
    public let kind: CardKind
    /// Runes only.
    public let domain: Domain?
    public let energyCost: Int
    public let powerCost: Int
    public let eligibleDomains: [Domain]

    public init(
        id: TrackedObjectID,
        name: String,
        zone: Zone,
        battlefieldSlot: Int? = nil,
        owner: Player? = nil,
        stance: CardStance = .ready,
        kind: CardKind = .unknown,
        domain: Domain? = nil,
        energyCost: Int = 0,
        powerCost: Int = 0,
        eligibleDomains: [Domain] = []
    ) {
        self.id = id
        self.name = name
        self.zone = zone
        self.battlefieldSlot = battlefieldSlot
        self.owner = owner
        self.stance = stance
        self.kind = kind
        self.domain = domain
        self.energyCost = energyCost
        self.powerCost = powerCost
        self.eligibleDomains = eligibleDomains
    }
}

/// Watches the table during the four fixed phases (515) and says whether
/// the player has finished the step, so Auto-detect can move the turn on
/// without them reaching for a button.
///
/// Deliberately a pure function of one frame's worth of observation plus a
/// small baseline, rather than something that accumulates its own history.
/// The tracker already owns "what is on the table"; duplicating that here
/// would be the second-source-of-truth mistake CLAUDE.md warns about, and
/// a detector with private state can disagree with the overlay the player
/// is looking at.
///
/// **It never advances the Action Phase.** 516.2 gives that phase no
/// completion condition at all — it ends when the player says so (516.6),
/// and no amount of watching the table can tell you someone is *done*.
public struct PhaseAutoDetector: Sendable {

    /// What the bar should say, and whether the phase is finished.
    public struct Progress: Sendable, Equatable {
        public var headline: String
        public var detail: String?
        /// Auto-detect may advance to the next phase.
        public var isComplete: Bool
        /// Rule 630.2: points earned by Holding, for the Beginning Phase.
        public var pointsToAward: Int
        /// Something on the table contradicts the rules and the player has
        /// to undo it — currently only an unaffordable Play. Never
        /// auto-advances.
        public var needsCorrection: Bool

        public init(
            headline: String,
            detail: String? = nil,
            isComplete: Bool = false,
            pointsToAward: Int = 0,
            needsCorrection: Bool = false
        ) {
            self.headline = headline
            self.detail = detail
            self.isComplete = isComplete
            self.pointsToAward = pointsToAward
            self.needsCorrection = needsCorrection
        }
    }

    /// How many Runes were in the Rune Area when the Channel Phase began.
    /// The phase asks for 2 *new* ones (515.3.b), so the target is relative
    /// — an absolute "2 runes on the table" would be satisfied on turn one
    /// and never again.
    public var channelBaseline: Int
    /// Rule 515.3.b: 2, or 3 on the first turn of the player going last
    /// (645.7). Passed in rather than derived, since whose first turn it is
    /// is exactly the thing this package can't see.
    public var runesToChannel: Int

    public init(channelBaseline: Int = 0, runesToChannel: Int = 2) {
        self.channelBaseline = channelBaseline
        self.runesToChannel = runesToChannel
    }

    public func progress(for phase: GamePhase, cards: [ObservedCard], seat: Player = .player1) -> Progress {
        switch phase {
        case .awaken:   return awaken(cards: cards, seat: seat)
        case .beginning: return beginning(cards: cards, seat: seat)
        case .channel:  return channel(cards: cards, seat: seat)
        case .draw:     return draw()
        case .action:   return action()
        }
    }

    // MARK: - Awaken (515.1)

    /// "The Turn Player readies all Game Objects they control that are able
    /// to be readied." Done when nothing of theirs is still sideways.
    ///
    /// Only looks at zones where a card can meaningfully be Exhausted —
    /// the Base, Battlefields, the Rune Area and the Champion zone. A
    /// sideways-looking card in the hand or a deck is a misread of a
    /// stack's bounding box, not something the player has to fix, and
    /// counting it would make the phase impossible to complete.
    private func awaken(cards: [ObservedCard], seat: Player) -> Progress {
        let exhausted = cards.filter {
            $0.stance == .exhausted
                && Self.readyableZones.contains($0.zone)
                && ($0.owner == nil || $0.owner == seat)
        }

        guard !exhausted.isEmpty else {
            return Progress(
                headline: "Everything is upright.",
                detail: "Nothing left to ready — moving on.",
                isComplete: true
            )
        }

        let names = exhausted.prefix(3).map(\.name).joined(separator: ", ")
        return Progress(
            headline: exhausted.count == 1
                ? "1 card is still exhausted."
                : "\(exhausted.count) cards are still exhausted.",
            detail: "Turn \(names)\(exhausted.count > 3 ? " and others" : "") upright (Rule 515.1)."
        )
    }

    private static let readyableZones: Set<Zone> = [.base, .battlefield, .runeArea, .champion]

    // MARK: - Beginning (515.2.b / 630.2)

    /// Hold: "A player has Control of a Battlefield during their Beginning
    /// Phase," and 181.4.a establishes Control by the presence of that
    /// player's Units. So a Battlefield with your cards on it and nobody
    /// else's scores you 1 point (631: once each).
    ///
    /// A contested Battlefield — both players present — scores nobody.
    /// 181.4.b keeps whoever already held it in control, but the camera
    /// can't see who that was, so claiming a point either way would be a
    /// guess. Reported rather than assumed.
    private func beginning(cards: [ObservedCard], seat: Player) -> Progress {
        let onBattlefields = cards.filter { $0.zone == .battlefield && $0.kind != .battlefield }
        let bySlot = Dictionary(grouping: onBattlefields) { $0.battlefieldSlot ?? 0 }

        var held = 0
        var contested = 0
        for (_, occupants) in bySlot {
            let owners = Set(occupants.compactMap(\.owner))
            if owners == [seat] || (owners.isEmpty && !occupants.isEmpty) {
                held += 1
            } else if owners.contains(seat) {
                contested += 1
            }
        }

        guard held > 0 else {
            return Progress(
                headline: "No battlefields held.",
                detail: contested > 0
                    ? "\(contested) battlefield\(contested == 1 ? " is" : "s are") contested — no hold point for those (Rule 630.2)."
                    : "You hold no battlefields this turn, so there's nothing to score (Rule 630.2).",
                isComplete: true
            )
        }

        return Progress(
            headline: held == 1 ? "Holding 1 battlefield — score 1 point." : "Holding \(held) battlefields — score \(held) points.",
            detail: "You control \(held == 1 ? "it" : "them") at the start of your turn (Rule 630.2).",
            isComplete: true,
            pointsToAward: held
        )
    }

    // MARK: - Channel (515.3)

    /// Counts Runes in the player's Rune Area against the baseline taken
    /// when the phase began. Relative, not absolute — the Rune Area fills
    /// up over the game, so "are there 2 runes" stops meaning anything
    /// after turn one.
    private func channel(cards: [ObservedCard], seat: Player) -> Progress {
        let inArea = cards.filter { $0.zone == .runeArea && ($0.owner == nil || $0.owner == seat) }.count
        let added = max(0, inArea - channelBaseline)

        guard added < runesToChannel else {
            return Progress(
                headline: "\(runesToChannel) runes channeled.",
                detail: "They enter ready — turn one sideways when you need energy (Rule 157.2.a).",
                isComplete: true
            )
        }

        return Progress(
            headline: "\(added) of \(runesToChannel) runes channeled.",
            detail: "Put \(runesToChannel - added) more rune\(runesToChannel - added == 1 ? "" : "s") from your rune deck into your rune area (Rule 515.3)."
        )
    }

    // MARK: - Draw (515.4)

    /// Not auto-completed. A drawn card goes straight into a hand the
    /// camera sees as an unordered fan, so "the hand grew by one" is not
    /// reliably distinguishable from a card being fanned into view — and
    /// wrongly deciding a draw happened desyncs the deck count silently.
    private func draw() -> Progress {
        Progress(
            headline: "Draw 1 card.",
            detail: "Then press Next — a draw into a fanned hand isn't something the camera can confirm (Rule 515.4)."
        )
    }

    // MARK: - Action (516)

    private func action() -> Progress {
        Progress(
            headline: "Your move.",
            detail: "Play cards, move units, attack — in any order. Press End Turn when you're done (Rule 516.6)."
        )
    }

    // MARK: - Paying for a play (130.2/130.3)

    /// Checks a card just put down from hand against the Runes actually in
    /// the Rune Area, and says what to do if it can't be paid for.
    ///
    /// Separate from `progress(for:)` because it's event-driven, not a
    /// per-frame poll: it fires on a specific card leaving the hand, and
    /// the answer must not change just because the next frame arrived.
    public func paymentProgress(for card: ObservedCard, runes: [ObservedRune]) -> Progress {
        switch RunePayment.verdict(
            energy: card.energyCost,
            power: card.powerCost,
            eligibleDomains: card.eligibleDomains,
            runes: runes
        ) {
        case .affordable:
            var parts: [String] = []
            if card.energyCost > 0 {
                parts.append("exhaust \(card.energyCost) rune\(card.energyCost == 1 ? "" : "s")")
            }
            if card.powerCost > 0 {
                let domains = card.eligibleDomains.map { $0.rawValue.capitalized }.joined(separator: " or ")
                parts.append("recycle \(card.powerCost) \(domains.isEmpty ? "" : domains + " ")rune\(card.powerCost == 1 ? "" : "s")")
            }
            guard !parts.isEmpty else {
                return Progress(headline: "\(card.name) is free to play.")
            }
            return Progress(
                headline: "Pay for \(card.name): \(parts.joined(separator: " and ")).",
                detail: "Turn runes sideways for energy; return them to the rune deck for power (Rule 157.2)."
            )

        case .unaffordable(.energy(let required, let available)):
            return Progress(
                headline: "Put \(card.name) back in your hand.",
                detail: "It needs \(required) energy and you have \(available) ready rune\(available == 1 ? "" : "s") left to exhaust (Rule 130.2).",
                needsCorrection: true
            )

        case .unaffordable(.power(let required, let available, let domains)):
            let named = domains.map { $0.rawValue.capitalized }.joined(separator: " or ")
            return Progress(
                headline: "Put \(card.name) back in your hand.",
                detail: "It needs \(required) \(named.isEmpty ? "" : named + " ")power and you have \(available) rune\(available == 1 ? "" : "s") you could recycle for it (Rule 130.3).",
                needsCorrection: true
            )
        }
    }
}
