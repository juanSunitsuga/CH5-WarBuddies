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
    /// Rule 139.4: Units enter the board **exhausted**. 717's Accelerate is
    /// the exception, and some card text says so in words rather than the
    /// keyword — either way the caller decides, since it's reading the
    /// printed text and this type isn't.
    public let entersReady: Bool
    /// What this card's text does, already translated to Game Actions by
    /// the NLP layer. Shown to the player when the card is played, so they
    /// know what they're meant to resolve.
    public let abilities: [String]

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
        eligibleDomains: [Domain] = [],
        entersReady: Bool = false,
        abilities: [String] = []
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
        self.entersReady = entersReady
        self.abilities = abilities
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
        /// Rule 630.2: points the player has earned by Holding, for the
        /// Beginning Phase. Advisory only — this is a number to *tell* them,
        /// not one anything adds for them. The app reads a camera, so it can
        /// be wrong about who holds what; a score it moves on its own is a
        /// score the player has to audit before they can trust it. They add
        /// it on the Score tracker, and the count here is the reminder.
        public var pointsToClaim: Int
        /// Something on the table contradicts the rules and the player has
        /// to undo it — currently only an unaffordable Play. Never
        /// auto-advances.
        public var needsCorrection: Bool
        /// Every ability currently in play, one line each, ready to work
        /// through in order. See `abilitySteps(cards:seat:)`.
        public var steps: [String]

        public init(
            headline: String,
            detail: String? = nil,
            isComplete: Bool = false,
            pointsToClaim: Int = 0,
            needsCorrection: Bool = false,
            steps: [String] = []
        ) {
            self.headline = headline
            self.detail = detail
            self.isComplete = isComplete
            self.pointsToClaim = pointsToClaim
            self.needsCorrection = needsCorrection
            self.steps = steps
        }
    }

    /// How many Runes were in the Rune Area when the Channel Phase began.
    /// The phase asks for 2 *new* ones (515.3.b), so the target is relative
    /// — an absolute "2 runes on the table" would be satisfied on turn one
    /// and never again.
    /// Hand size when the Draw Phase began. 515.4.b draws exactly 1, so
    /// the phase is done when the hand has grown by one — the same
    /// relative-to-baseline trick the Channel Phase uses, and for the same
    /// reason: an absolute hand size means nothing.
    public var handBaseline: Int
    public var channelBaseline: Int
    /// Rule 515.3.b: 2, or 3 on the first turn of the player going last
    /// (645.7). Passed in rather than derived, since whose first turn it is
    /// is exactly the thing this package can't see.
    public var runesToChannel: Int

    public init(channelBaseline: Int = 0, runesToChannel: Int = 2, handBaseline: Int = 0) {
        self.channelBaseline = channelBaseline
        self.runesToChannel = runesToChannel
        self.handBaseline = handBaseline
    }

    public func progress(for phase: GamePhase, cards: [ObservedCard], seat: Player = .player1) -> Progress {
        var progress: Progress
        switch phase {
        case .awaken:   progress = awaken(cards: cards, seat: seat)
        case .beginning: progress = beginning(cards: cards, seat: seat)
        case .channel:  progress = channel(cards: cards, seat: seat)
        case .draw:     progress = draw(cards: cards, seat: seat)
        case .action:   progress = action()
        case .done:     progress = done()
        }
        // Carried on every phase, not just Action: a "at the start of your
        // beginning phase" ability is exactly the kind a player forgets,
        // and it's live during the phase it names.
        progress.steps = abilitySteps(cards: cards, seat: seat)
        return progress
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
                && Self.isReadyable($0.kind)
                && ($0.owner == nil || $0.owner == seat)
        }

        guard !exhausted.isEmpty else {
            return Progress(
                headline: "All upright.",
                detail: "Nothing left to turn — moving on.",
                isComplete: true
            )
        }

        let names = exhausted.prefix(3).map(\.name).joined(separator: ", ")
        return Progress(
            // The headline is the thing to do, not the state of play. It is
            // set at display size and read from across a table, so "3 cards
            // are still exhausted" spends that space describing rather than
            // instructing — and spends it on a word ("exhausted") the
            // player then needs explained. "Turn 3 cards upright" says the
            // same thing, as an action, in words nobody has to look up.
            headline: exhausted.count == 1
                ? "Turn 1 card upright."
                : "Turn \(exhausted.count) cards upright.",
            detail: "\(names)\(exhausted.count > 3 ? " and others" : "") \(exhausted.count == 1 ? "is" : "are") still sideways (Rule 515.1)."
        )
    }

    private static let readyableZones: Set<Zone> = [.base, .battlefield, .runeArea, .champion]

    /// 515.1 readies Game Objects "that are able to be readied", which is
    /// not all of them.
    ///
    /// A Battlefield is never exhausted in play — it's a place, not a
    /// participant — and it is the one card type printed **landscape**, so
    /// it sits in the battlefield zone looking permanently sideways. Left
    /// in, it made the Awaken phase impossible to finish from the first
    /// turn onward: the phase waits for nothing to be exhausted, and a
    /// battlefield card is always on the mat.
    private static func isReadyable(_ kind: CardKind) -> Bool {
        kind != .battlefield
    }

    /// "a", "a and b", "a, b and c" — a list a player reads as a single
    /// instruction rather than three stacked ones.
    private func sentence(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
    }

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
                headline: "No points this turn.",
                detail: contested > 0
                    ? "\(contested) battlefield\(contested == 1 ? " is" : "s are") contested — no hold point for those (Rule 630.2)."
                    : "You hold no battlefields this turn, so there's nothing to score (Rule 630.2).",
                isComplete: true
            )
        }

        return Progress(
            headline: held == 1 ? "Add 1 point." : "Add \(held) points.",
            detail: "Tap + on Player. You're holding \(held == 1 ? "a battlefield" : "\(held) battlefields") at the start of your turn (Rule 630.2).",
            isComplete: true,
            pointsToClaim: held
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
                headline: "Runes are out.",
                detail: "They arrive upright — turn one sideways when you need energy (Rule 157.2.a).",
                isComplete: true
            )
        }

        return Progress(
            // Same rule as Awaken: the count belongs in the detail, and
            // "channel" is the jargon this phase is named after — the
            // headline can just say what the hands do.
            headline: runesToChannel - added == 1
                ? "Put out 1 more rune."
                : "Put out \(runesToChannel - added) more runes.",
            detail: "\(added) of \(runesToChannel) done. Take them off the top of your rune deck into your rune area (Rule 515.3)."
        )
    }

    // MARK: - Draw (515.4)

    /// 515.4.b: the Turn Player draws 1. A card arriving in the hand zone
    /// is the whole signature — Main Deck → Hand is the only way a card
    /// gets there during this phase, so the hand growing by one is the
    /// draw.
    ///
    /// Measured against a baseline taken as the phase began, for the same
    /// reason Channel is: hand size is whatever it is, only the change
    /// means anything.
    private func draw(cards: [ObservedCard], seat: Player) -> Progress {
        let inHand = cards.filter { $0.zone.isHand(for: seat) }.count
        let drawn = inHand - handBaseline

        guard drawn < 1 else {
            return Progress(
                headline: "Card drawn.",
                detail: "Unspent energy and power is lost as this step ends (Rule 515.4.d).",
                isComplete: true
            )
        }

        return Progress(
            headline: "Draw 1 card.",
            detail: "Take the top card of your main deck into your hand (Rule 515.4.b)."
        )
    }

    // MARK: - Action (516)

    private func action() -> Progress {
        Progress(
            headline: "Your move.",
            detail: "Play cards, move units, attack — in any order. Press Done when you've finished (Rule 516.6)."
        )
    }

    /// The player has said they're finished playing but hasn't handed the
    /// turn over. Nothing here is auto-detectable — no card movement
    /// confirms a declaration — so this reports the state rather than
    /// checking for it.
    private func done() -> Progress {
        Progress(
            headline: "Phase complete.",
            detail: "Press End Turn to hand over, or Back if there's still a move you want to make (Rule 516.6)."
        )
    }

    // MARK: - What's in play, and what it does

    /// Every ability on the board right now, as a list of steps to work
    /// through — the cards in the player's Base, their units on
    /// Battlefields, and their Legend.
    ///
    /// Those three zones and no others because they're where a card's text
    /// is *live*: a permanent in the Base or at a Battlefield is a Game
    /// Object with its abilities available (137–145), and the Legend's
    /// effect applies for the whole game (166–169). A card in hand, a deck
    /// or the trash does nothing, and listing it would bury the ones that
    /// matter.
    ///
    /// Prefixed with the card's name because the player is looking at a
    /// table, not a list — "Annie: Deal 2 damage" is findable, "Deal 2
    /// damage" is a puzzle.
    public func abilitySteps(cards: [ObservedCard], seat: Player = .player1) -> [String] {
        cards
            .filter { Self.abilityZones.contains($0.zone) }
            .filter { $0.owner == nil || $0.owner == seat }
            // A Battlefield's own card text applies to whoever fights
            // there, not to its abilities being "yours to resolve" — and
            // it's the one card in these zones that isn't a permanent the
            // player controls.
            .filter { $0.kind != .battlefield }
            .filter { !$0.abilities.isEmpty }
            .sorted { $0.name < $1.name }
            .flatMap { card in card.abilities.map { "\(card.name): \($0)" } }
    }

    private static let abilityZones: Set<Zone> = [.base, .battlefield, .legend, .champion]

    // MARK: - Holding a play open until it's paid for

    /// The Action Phase while a play is still being paid for.
    ///
    /// Everything else the player might do is blocked until this settles.
    /// Not because two actions can't overlap in the rules, but because a
    /// half-paid play is a board the engine and the table disagree about,
    /// and every action stacked on top inherits that disagreement — by the
    /// time it surfaces, there's no telling which move went wrong.
    public func settlement(of play: PendingPlay, observing observation: PendingPlay.Observation) -> Progress {
        let owed = play.outstanding(observation)

        guard !owed.isEmpty else {
            return Progress(
                headline: "\(play.name) is paid for.",
                detail: "Your move — play another card, move a unit, or end your turn.",
                isComplete: true
            )
        }

        return Progress(
            headline: "You've played \(play.name).",
            detail: "Still to do: \(sentence(owed)). Nothing else counts until it's paid for (Rules 139.4, 157.2).",
            needsCorrection: true
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

            // Rule 139.4: a Unit enters the board exhausted. That's a
            // physical thing the player has to do — turn the card they just
            // put down sideways — and it's the step most often forgotten,
            // because the card is already on the table and looks finished.
            // 717's Accelerate (and text that says so in words) is the
            // exception, and is worth calling out rather than staying
            // silent about, since "why isn't it asking me to turn this one"
            // is otherwise a puzzle.
            let entersExhausted = card.kind == .unit || card.kind == .champion
            if entersExhausted, !card.entersReady {
                // "it", not the card's name: the headline right above this
                // already says which card was played, and repeating the
                // name inside the same sentence reads like a second card.
                parts.append("turn it sideways")
            }

            if card.energyCost > 0 {
                parts.append("exhaust \(card.energyCost) rune\(card.energyCost == 1 ? "" : "s")")
            }
            if card.powerCost > 0 {
                let domains = card.eligibleDomains.map { $0.rawValue.capitalized }.joined(separator: " or ")
                // Naming the destination, not just the verb — see
                // `PendingPlay.outstanding`.
                parts.append("return \(card.powerCost) \(domains.isEmpty ? "" : domains + " ")rune\(card.powerCost == 1 ? "" : "s") to your rune deck")
            }

            let abilityLine = card.abilities.isEmpty ? nil : card.abilities.joined(separator: "  ·  ")

            guard !parts.isEmpty else {
                return Progress(
                    headline: entersExhausted && card.entersReady
                        ? "\(card.name) enters ready — leave it upright."
                        : "\(card.name) costs nothing to play.",
                    detail: abilityLine
                )
            }

            // Split across the strip's two lines: what happened on top,
            // what's owed for it underneath. One sentence carrying both was
            // the card's name, a colon and a list, which reads as a label
            // rather than as something to act on.
            return Progress(
                headline: "You've played \(card.name).",
                detail: sentence(parts).capitalizedFirst + "."
                    + (abilityLine.map { "  ·  \($0)" } ?? "")
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
                detail: "It needs \(required) \(named.isEmpty ? "" : named + " ")power, and you have \(available) rune\(available == 1 ? "" : "s") you could return to your rune deck for it (Rule 130.3).",
                needsCorrection: true
            )
        }
    }
}

private extension String {
    /// Uppercases only the first character, leaving the rest alone —
    /// unlike `capitalized`, which would also retitle "rune deck" and every
    /// other word in the sentence.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
