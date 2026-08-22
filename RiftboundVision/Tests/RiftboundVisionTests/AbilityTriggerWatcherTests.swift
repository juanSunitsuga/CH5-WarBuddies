import Testing
import CoreGraphics
@testable import RiftboundVision

/// Deciding whether a real player action fired a real ability.
///
/// This lived in `CameraPipelineController` and was flagged as unverifiable
/// there: the app target has no tests, so it could only be read. It needs no
/// camera and no SwiftUI — tracked objects in, fired abilities out — so the
/// only thing that ever made it untestable was where it sat.
@Suite("Ability Trigger Watcher")
struct AbilityTriggerWatcherTests {

    private static func track(
        id: TrackedObjectID = 1,
        zone: Zone,
        label: String? = "Noxian Drummer",
        committed: Bool = true
    ) -> TrackedObject {
        var object = TrackedObject(
            id: id,
            type: .card,
            center: CGPoint(x: 100, y: 100),
            boundingBox: CGRect(x: 60, y: 45, width: 80, height: 110),
            rotation: 0,
            previousZone: zone,
            currentZone: zone,
            velocity: .zero,
            confidence: 0.9,
            isVisible: true,
            lastSeenFrame: 1,
            recognizedLabel: label,
            isIdentityCommitted: committed
        )
        object.currentZone = zone
        return object
    }

    /// A card whose text fires on reaching a battlefield.
    private static func movedToBattlefield(
        _ watcher: AbilityTriggerWatcher
    ) -> (TrackedObject) -> [(fires: (Zone, Zone) -> Bool, effect: String)] {
        { _ in [(fires: { _, zone in zone == .battlefield }, effect: "Play a 1 Might Recruit unit token here.")] }
    }

    private static func run(
        _ watcher: AbilityTriggerWatcher,
        _ objects: [TrackedObject],
        card: @escaping (TrackedObject) -> (name: String, text: String)? = { _ in ("Noxian Drummer", "text") },
        fires: @escaping (Zone, Zone) -> Bool = { _, zone in zone == .battlefield }
    ) -> [AbilityTriggerWatcher.Fired] {
        watcher.fired(
            in: objects,
            card: card,
            triggers: { _ in [(fires: fires, effect: "Play a 1 Might Recruit unit token here.")] }
        )
    }

    /// First sighting isn't a move. A card the tracker picks up already
    /// lying on a battlefield was not *moved* there while anyone watched.
    @Test("A first sighting fires nothing, even in the triggering zone")
    func firstSightingIsSilent() {
        let watcher = AbilityTriggerWatcher()
        #expect(Self.run(watcher, [Self.track(zone: .battlefield)]).isEmpty)
    }

    @Test("Moving into the triggering zone fires once")
    func moveFires() {
        let watcher = AbilityTriggerWatcher()
        _ = Self.run(watcher, [Self.track(zone: .base)])          // establish where it was

        let fired = Self.run(watcher, [Self.track(zone: .battlefield)])

        #expect(fired.count == 1)
        #expect(fired.first?.cardName == "Noxian Drummer")
        #expect(fired.first?.effects == ["Play a 1 Might Recruit unit token here."])
    }

    /// The bug the announced-zone memory exists to prevent: a card sitting
    /// still re-announcing itself several times a second.
    @Test("A card that stays put doesn't fire again")
    func stayingPutIsSilent() {
        let watcher = AbilityTriggerWatcher()
        _ = Self.run(watcher, [Self.track(zone: .base)])
        #expect(Self.run(watcher, [Self.track(zone: .battlefield)]).count == 1)

        #expect(Self.run(watcher, [Self.track(zone: .battlefield)]).isEmpty)
        #expect(Self.run(watcher, [Self.track(zone: .battlefield)]).isEmpty)
    }

    /// Naming the wrong card's ability is worse than naming none — the
    /// player resolves an effect that isn't on the table.
    @Test("An uncommitted identity fires nothing")
    func uncommittedIsSilent() {
        let watcher = AbilityTriggerWatcher()
        _ = Self.run(watcher, [Self.track(zone: .base, committed: false)])

        #expect(Self.run(watcher, [Self.track(zone: .battlefield, committed: false)]).isEmpty)
    }

    /// Deck scope rejecting the label arrives here as "no card".
    @Test("A card the resolver won't name fires nothing")
    func unresolvedCardIsSilent() {
        let watcher = AbilityTriggerWatcher()
        _ = Self.run(watcher, [Self.track(zone: .base)], card: { _ in nil })

        #expect(Self.run(watcher, [Self.track(zone: .battlefield)], card: { _ in nil }).isEmpty)
    }

    @Test("A move the card's text doesn't care about fires nothing")
    func wrongZoneIsSilent() {
        let watcher = AbilityTriggerWatcher()
        _ = Self.run(watcher, [Self.track(zone: .base)])

        #expect(Self.run(watcher, [Self.track(zone: .trash)]).isEmpty)
    }

    /// "When you play me" is a move out of the hand specifically, not any
    /// arrival — otherwise tidying the mat would trigger it.
    @Test("Play-from-hand means out of the hand, not any arrival")
    func playFromHandIsSpecific() {
        let watcher = AbilityTriggerWatcher(seat: .player1)

        #expect(watcher.isPlayFromHand(from: .player1Hand, to: .base))
        #expect(watcher.isPlayFromHand(from: .base, to: .battlefield) == false)
        #expect(watcher.isPlayFromHand(from: .player1Hand, to: .unknown) == false)
    }

    /// Per-track memory must not grow for the length of a session.
    @Test("A track that disappears is forgotten, and returns as a fresh arrival")
    func vanishedTracksAreForgotten() {
        let watcher = AbilityTriggerWatcher()
        _ = Self.run(watcher, [Self.track(zone: .base)])
        _ = Self.run(watcher, [])                                  // taken off the table

        // Back on a battlefield: a first sighting again, so silent.
        #expect(Self.run(watcher, [Self.track(zone: .battlefield)]).isEmpty)
    }

    @Test("Resetting clears the memory")
    func resetClears() {
        let watcher = AbilityTriggerWatcher()
        _ = Self.run(watcher, [Self.track(zone: .base)])

        watcher.reset()

        #expect(Self.run(watcher, [Self.track(zone: .battlefield)]).isEmpty)
    }
}
