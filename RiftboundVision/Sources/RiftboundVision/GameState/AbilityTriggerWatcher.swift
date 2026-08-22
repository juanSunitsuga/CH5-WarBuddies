import Foundation

/// Watches tracked cards for the zone changes that fire a card's printed
/// "when …" text.
///
/// Extracted from `CameraPipelineController` for one concrete reason: it was
/// untestable there. The app target has no test target, so this — the part
/// that decides whether a real player action fired a real ability — was
/// verified by reading it. It needs no camera and no SwiftUI: tracked
/// objects in, fired abilities out.
///
/// What a card's text *says* stays in the NLP package, which this module
/// can't depend on. So the caller injects the lookup, and this owns the
/// watching: which zone each track was last announced in, and which
/// transitions count.
public final class AbilityTriggerWatcher {

    /// One ability that just fired, ready to be shown.
    public struct Fired: Sendable, Equatable {
        public let cardName: String
        /// The card's own effect sentences, most relevant first.
        public let effects: [String]
        /// Where the card ended up.
        public let zone: Zone
    }

    /// Which zone each track was last *announced* in.
    ///
    /// `TrackedObject.previousZone` keeps naming the old zone for as long as
    /// a card sits still, so firing off that alone re-announces the same
    /// arrival several times a second. This records what the player has
    /// already been told.
    private var announcedZones: [TrackedObjectID: Zone] = [:]

    /// Whose hand counts as "played from hand".
    private let seat: Player

    public init(seat: Player = .player1) {
        self.seat = seat
    }

    /// Abilities fired by this poll's movements.
    ///
    /// - Parameters:
    ///   - objects: the resolved tracks for this poll.
    ///   - card: identity for a track, already deck-scoped. `nil` means the
    ///     label can't be trusted here, and nothing fires.
    ///   - triggers: the card's parsed "when …, do …" clauses, from the NLP
    ///     layer. Each entry is a matcher plus the sentence to show.
    public func fired(
        in objects: [TrackedObject],
        card: (TrackedObject) -> (name: String, text: String)?,
        triggers: (String) -> [(fires: (Zone, Zone) -> Bool, effect: String)]
    ) -> [Fired] {
        var results: [Fired] = []
        var seen: Set<TrackedObjectID> = []

        for object in objects where object.type == .card {
            seen.insert(object.id)
            let zone = object.currentZone
            let previous = announcedZones[object.id]
            announcedZones[object.id] = zone

            // First sighting isn't a move. A card the tracker picks up
            // already lying on a battlefield was not *moved* there while
            // anyone was watching, and announcing it would fire every
            // ability on the table the moment the pipeline starts.
            guard let previous, previous != zone else { continue }

            // Don't act on a card still being identified. Naming the wrong
            // card's ability is worse than naming none: the player resolves
            // an effect that isn't on the table, and nothing corrects it.
            guard object.isIdentityCommitted else { continue }
            guard let card = card(object) else { continue }

            let effects = triggers(card.text)
                .filter { $0.fires(previous, zone) }
                .map(\.effect)
            guard !effects.isEmpty else { continue }

            results.append(Fired(cardName: card.name, effects: effects, zone: zone))
        }

        // Forget tracks that are gone, so a card that leaves the table and
        // comes back is a fresh arrival rather than a stale comparison —
        // and so this can't grow for the length of a session.
        announcedZones = announcedZones.filter { seen.contains($0.key) }
        return results
    }

    /// Whether a move out of the hand and onto the board counts as "played".
    ///
    /// "When you play me" is a card arriving from hand specifically — not
    /// any arrival, or tidying the mat would trigger it.
    public func isPlayFromHand(from previous: Zone, to zone: Zone) -> Bool {
        previous.isHand(for: seat) && zone != .unknown
    }

    /// Drops all memory — a new match, or the pipeline stopping.
    public func reset() { announcedZones.removeAll() }
}
