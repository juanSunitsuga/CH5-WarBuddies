import Foundation

/// The single place a detector label becomes a card.
///
/// Every consumer that turns "Annie Fiery" into a `CardPrinting` goes
/// through here, which is the point: the app had two routes doing it
/// differently. The UI applied deck scope and the engine's `resolveLabel`
/// didn't, so an out-of-deck card vanished from the card strip while the
/// engine went on tracking it and proposing plays for it. Screen and engine
/// disagreeing about the same physical card is the failure CLAUDE.md's
/// "one source of truth per fact" rule exists to prevent.
///
/// Lives in `RiftboundVision` rather than the app because everything it
/// needs — the card database, deck scope, zones — is here, and the app
/// target has no tests. Ability *text* still belongs to the NLP package;
/// this resolves identity only.
/// **Thread safety.** `@unchecked Sendable` with a lock, because it is read
/// from two places that don't share an actor: the UI on the main actor, and
/// the translator's `resolveLabel` closure, which the engine calls from its
/// own context. Both only ever read the database and consult the scope; the
/// two mutable pieces — the kind memo and the adopted deck — are guarded.
/// A snapshot instead of a lock would freeze the scope at pipeline start,
/// before any Legend has been seen, which is the very behaviour being fixed.
public final class CardIdentityResolver: @unchecked Sendable {
    public let database: CardDatabase

    private let lock = NSLock()
    private var _scope: DeckScope

    public var scope: DeckScope {
        lock.lock(); defer { lock.unlock() }
        return _scope
    }

    /// `CardKind` per label, resolved once.
    ///
    /// `printing(approximatelyNamed:)` normalizes and scans the whole
    /// catalogue, and this sits on the per-poll path. A label's card kind
    /// can't change between polls, so re-deriving it every time was pure
    /// repetition. A label resolving to nothing caches as `.unknown`.
    private var kindByLabel: [String: CardKind] = [:]

    public init(database: CardDatabase) {
        self.database = database
        self._scope = DeckScope(rosters: database.decks)
    }

    // MARK: - Identity

    /// The card behind a label, or `nil` when deck scope says that label
    /// can't be right here.
    ///
    /// A rejected label leaves the object tracked and drawn — it simply
    /// isn't claimed to be a card it can't be.
    public func printing(forLabel label: String?, in zone: Zone) -> CardPrinting? {
        guard let label, let printing = database.printing(approximatelyNamed: label) else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard _scope.allows(printing.riftboundID, in: zone) else { return nil }
        return printing
    }

    /// What kind of card a label names, cached. Deliberately *not* scoped:
    /// placement rules need to know a battlefield is a battlefield whoever
    /// brought it, and an unknown kind is permitted everywhere, so scoping
    /// this would loosen the rules rather than tighten them.
    public func kind(forLabel label: String) -> CardKind {
        lock.lock(); defer { lock.unlock() }
        if let cached = kindByLabel[label] { return cached }
        let resolved = database.printing(approximatelyNamed: label).map {
            CardKind.from(type: $0.classification.type, supertype: $0.classification.supertype)
        } ?? .unknown
        kindByLabel[label] = resolved
        return resolved
    }

    // MARK: - Deck

    public var activeDeckName: String? { scope.activeDeckName }
    public var hasIdentifiedDeck: Bool { scope.hasIdentifiedDeck }

    /// Adopts the deck as soon as a committed Legend is on the table.
    ///
    /// Waits for `isIdentityCommitted`: the whole deck is chosen off one
    /// label, so choosing it from a reading still wobbling would scope
    /// everything else to the wrong deck.
    ///
    /// Returns whether a deck was adopted, so a caller can react once.
    @discardableResult
    public func adoptDeckIfLegendSeen(in objects: [TrackedObject]) -> Bool {
        guard !hasIdentifiedDeck else { return false }

        for object in objects where object.isIdentityCommitted {
            guard let label = object.recognizedLabel,
                  let printing = database.printing(approximatelyNamed: label),
                  // Outside the lock: `kind(forLabel:)` takes it itself.
                  kind(forLabel: label) == .legend
            else { continue }

            lock.lock(); defer { lock.unlock() }
            if _scope.identifyDeck(fromLegend: printing.riftboundID) { return true }
        }
        return false
    }

    /// Forgets the deck — a new match.
    public func resetDeck() {
        lock.lock(); defer { lock.unlock() }
        _scope.reset()
    }
}
