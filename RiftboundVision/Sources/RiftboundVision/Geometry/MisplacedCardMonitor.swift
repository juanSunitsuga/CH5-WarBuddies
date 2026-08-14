import Foundation

/// A card sitting somewhere its kind can't be, with where to put it back.
public struct MisplacedCard: Sendable, Equatable, Identifiable {
    public let id: TrackedObjectID
    public let label: String
    public let kind: CardKind
    /// Where the card is now.
    public let currentZone: Zone
    /// Where it should go. The zone it came from when that was legitimate,
    /// otherwise the most sensible home for its kind — a player putting a
    /// card back wants to be told a place, not a list.
    public let suggestedZone: Zone

    public init(id: TrackedObjectID, label: String, kind: CardKind, currentZone: Zone, suggestedZone: Zone) {
        self.id = id
        self.label = label
        self.kind = kind
        self.currentZone = currentZone
        self.suggestedZone = suggestedZone
    }
}

/// Watches tracked cards for placements their kind doesn't allow, and says
/// where to put them back.
///
/// Deliberately reports rather than filters. Dropping an implausible
/// detection hides the problem: the card is still physically on the mat,
/// the player can't see that the app has stopped believing in it, and the
/// board silently diverges from what the engine thinks. Naming the mistake
/// and asking for it back is the useful behaviour.
///
/// A violation has to hold for `confirmationPolls` consecutive polls before
/// it's reported. The detector occasionally misreads one card as another,
/// and a single bad frame shouldn't tell a player to move a card that's
/// exactly where it belongs.
public final class MisplacedCardMonitor: @unchecked Sendable {
    private let rules: CardPlacementRules
    private let confirmationPolls: Int

    /// Consecutive polls each track has been somewhere it shouldn't be.
    private var streaks: [TrackedObjectID: Int] = [:]
    /// The last zone each track was legitimately in, which is the most
    /// useful place to send a card back to.
    private var lastValidZone: [TrackedObjectID: Zone] = [:]

    public init(rules: CardPlacementRules = CardPlacementRules(), confirmationPolls: Int = 3) {
        self.rules = rules
        self.confirmationPolls = confirmationPolls
    }

    /// - Parameters:
    ///   - objects: this poll's tracked objects.
    ///   - kind: resolves a recognizer label to a card kind. Injected
    ///     because the card catalogue lives in the app layer.
    /// - Returns: confirmed misplacements, stable across polls so the UI
    ///   doesn't flicker while a card stays where it shouldn't be.
    public func update(objects: [TrackedObject], kind: (String) -> CardKind) -> [MisplacedCard] {
        var misplaced: [MisplacedCard] = []
        var seen: Set<TrackedObjectID> = []

        for object in objects {
            seen.insert(object.id)
            guard let label = object.recognizedLabel else { continue }
            let cardKind = kind(label)

            guard !rules.isPlausible(kind: cardKind, in: object.currentZone) else {
                // Somewhere legitimate: remember it as the place to send
                // the card back to if it later wanders.
                if object.currentZone != .unknown {
                    lastValidZone[object.id] = object.currentZone
                }
                streaks[object.id] = nil
                continue
            }

            let streak = (streaks[object.id] ?? 0) + 1
            streaks[object.id] = streak
            guard streak >= confirmationPolls else { continue }

            misplaced.append(MisplacedCard(
                id: object.id,
                label: label,
                kind: cardKind,
                currentZone: object.currentZone,
                suggestedZone: suggestedZone(for: cardKind, trackID: object.id)
            ))
        }

        // Release bookkeeping for tracks that are gone.
        streaks = streaks.filter { seen.contains($0.key) }
        lastValidZone = lastValidZone.filter { seen.contains($0.key) }
        return misplaced
    }

    public func reset() {
        streaks = [:]
        lastValidZone = [:]
    }

    /// Where the card came from, if that was a legitimate spot; otherwise
    /// the canonical home for its kind.
    private func suggestedZone(for kind: CardKind, trackID: TrackedObjectID) -> Zone {
        if let previous = lastValidZone[trackID], rules.isPlausible(kind: kind, in: previous) {
            return previous
        }
        return Self.home(for: kind)
    }

    /// One zone per kind, for when there's no history to fall back on.
    /// Picked as the place a player would naturally return the card to.
    private static func home(for kind: CardKind) -> Zone {
        switch kind {
        case .rune: return .runeArea
        case .unit, .spell, .gear: return .player1Hand
        case .champion: return .champion
        case .legend: return .legend
        case .battlefield: return .battlefield
        case .unknown: return .unknown
        }
    }
}
