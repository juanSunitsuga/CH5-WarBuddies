import Foundation

/// One deck's card list, kept so identification can be narrowed to it.
public struct DeckRoster: Sendable, Equatable {
    /// As the deck export names it — "Annie, Dark Child".
    public let name: String
    /// Rule 166: a deck has exactly one Legend, and it is on the table from
    /// setup. That makes it the one card that identifies the whole deck.
    public let legendIDs: Set<String>
    /// Battlefields are placed during setup and belong to the match rather
    /// than to a player's play sequence, so they stay identifiable whoever
    /// brought them.
    public let battlefieldIDs: Set<String>
    /// Every printing in the deck — legend, runes, battlefields, main deck.
    public let memberIDs: Set<String>

    public init(name: String, legendIDs: Set<String>, battlefieldIDs: Set<String>, memberIDs: Set<String>) {
        self.name = name
        self.legendIDs = legendIDs
        self.battlefieldIDs = battlefieldIDs
        self.memberIDs = memberIDs
    }

    public func containsLegend(_ riftboundID: String) -> Bool { legendIDs.contains(riftboundID) }
}

/// Narrows card identification to the deck actually on the table.
///
/// The detector will happily offer any label it was trained on, so a Garen
/// deck's cards get read against a label space containing every Annie, Lux
/// and Master Yi card too. Most misidentifications are between cards that
/// were never both going to be in play — which is a constraint the app has
/// and wasn't using.
///
/// The Legend is what unlocks it. Rule 166 puts exactly one Legend on the
/// table from setup and it stays there all game, so seeing it names the
/// deck, and from then on a label outside that deck can be rejected as the
/// misread it almost certainly is.
///
/// **Two things stay identifiable regardless**, because they're the cases
/// where an out-of-deck card is real rather than a misread:
///
/// - **Anything at a Battlefield.** That's where an opponent's cards
///   legitimately arrive, and the engine has to know what it's looking at
///   to track combat at all.
/// - **Battlefield cards themselves**, which are placed during setup and
///   belong to the match rather than to one player's deck.
///
/// Everything else — a card in the player's own base, hand, rune area or
/// decks — is theirs, so a label from another deck there is wrong by
/// construction and is better dropped than believed.
public struct DeckScope: Sendable, Equatable {
    public let rosters: [DeckRoster]
    /// `nil` until a Legend has been seen. While it is nil nothing is
    /// narrowed: the app must not start hiding cards before it knows which
    /// deck it's hiding them for.
    public private(set) var activeDeck: DeckRoster?

    public init(rosters: [DeckRoster], activeDeck: DeckRoster? = nil) {
        self.rosters = rosters
        self.activeDeck = activeDeck
    }

    public var activeDeckName: String? { activeDeck?.name }
    public var hasIdentifiedDeck: Bool { activeDeck != nil }

    /// Adopts the deck that owns this Legend printing.
    ///
    /// Returns whether the active deck changed, so a caller can react to it
    /// once rather than on every poll that re-sees the same Legend.
    @discardableResult
    public mutating func identifyDeck(fromLegend riftboundID: String) -> Bool {
        guard let roster = rosters.first(where: { $0.containsLegend(riftboundID) }) else { return false }
        guard roster != activeDeck else { return false }
        activeDeck = roster
        return true
    }

    /// Forgets the deck — a new match, or the Legend leaving the table.
    public mutating func reset() { activeDeck = nil }

    /// Whether a card identified as `riftboundID`, seen in `zone`, should be
    /// believed.
    public func allows(_ riftboundID: String, in zone: Zone) -> Bool {
        // Nothing is narrowed until the deck is known.
        guard let activeDeck else { return true }
        // An opponent's card arriving at a battlefield is the one place an
        // out-of-deck card is genuinely expected.
        if zone == .battlefield { return true }
        // Battlefields belong to the match, not to a deck.
        if activeDeck.battlefieldIDs.contains(riftboundID) { return true }
        return activeDeck.memberIDs.contains(riftboundID)
    }
}
