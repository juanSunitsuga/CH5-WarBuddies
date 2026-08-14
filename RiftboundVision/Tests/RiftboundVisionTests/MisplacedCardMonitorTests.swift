import Testing
import CoreGraphics
@testable import RiftboundVision

/// A card in a zone its kind can't occupy is reported, not filtered away.
/// Dropping the reading hid the problem: the card was still on the mat, the
/// player had no idea the app had stopped believing in it, and the board
/// silently diverged from the engine.
@Suite("Misplaced Card Monitor")
struct MisplacedCardMonitorTests {
    private static let kinds: [String: CardKind] = [
        "Order Rune": .rune,
        "Sai Scout": .unit,
        "Disintegrate": .spell
    ]

    private static func kind(_ label: String) -> CardKind { kinds[label] ?? .unknown }

    private static func object(
        id: TrackedObjectID = 1,
        label: String,
        zone: Zone
    ) -> TrackedObject {
        TrackedObject(
            id: id,
            type: .card,
            center: CGPoint(x: 100, y: 100),
            boundingBox: CGRect(x: 60, y: 45, width: 80, height: 110),
            rotation: 0,
            previousZone: zone,
            currentZone: zone,
            confidence: 0.95,
            isVisible: true,
            lastSeenFrame: 1,
            recognizedLabel: label
        )
    }

    /// Runs the monitor for `polls` and returns the final report.
    private static func run(
        _ objects: [TrackedObject],
        polls: Int,
        monitor: MisplacedCardMonitor = MisplacedCardMonitor()
    ) -> [MisplacedCard] {
        var last: [MisplacedCard] = []
        for _ in 0..<polls { last = monitor.update(objects: objects, kind: kind) }
        return last
    }

    @Test("A Rune left in the Base is reported once it's held there")
    func runeInBaseIsReported() {
        let reported = Self.run([Self.object(label: "Order Rune", zone: .base)], polls: 3)

        #expect(reported.count == 1)
        #expect(reported.first?.label == "Order Rune")
        #expect(reported.first?.currentZone == .base)
        #expect(reported.first?.suggestedZone == .runeArea)
    }

    /// The detector misreads one card as another now and then; a single bad
    /// frame must not tell a player to move a card that's exactly where it
    /// belongs.
    @Test("A one-poll misreading is not reported")
    func singlePollIsNotEnough() {
        #expect(Self.run([Self.object(label: "Order Rune", zone: .base)], polls: 1).isEmpty)
        #expect(Self.run([Self.object(label: "Order Rune", zone: .base)], polls: 2).isEmpty)
    }

    /// Being told to put a card "back" is only useful if it names where it
    /// actually came from.
    @Test("The suggestion is the zone the card was legitimately in")
    func suggestionPrefersWhereItCameFrom() {
        let monitor = MisplacedCardMonitor()
        // Established in the Rune Deck, then moved somewhere it can't be.
        for _ in 0..<3 {
            _ = monitor.update(objects: [Self.object(label: "Order Rune", zone: .runeDeck)], kind: Self.kind)
        }
        let reported = Self.run(
            [Self.object(label: "Order Rune", zone: .battlefield)],
            polls: 3,
            monitor: monitor
        )

        #expect(reported.first?.suggestedZone == .runeDeck)
    }

    @Test("Cards in legitimate zones are never reported")
    func legitimatePlacementsAreSilent() {
        #expect(Self.run([Self.object(label: "Order Rune", zone: .runeArea)], polls: 5).isEmpty)
        #expect(Self.run([Self.object(label: "Sai Scout", zone: .battlefield)], polls: 5).isEmpty)
        #expect(Self.run([Self.object(label: "Disintegrate", zone: .player1Hand)], polls: 5).isEmpty)
    }

    /// A card being carried between regions isn't misplaced — it's between
    /// places.
    @Test("A card in transit is never reported")
    func inTransitIsSilent() {
        #expect(Self.run([Self.object(label: "Order Rune", zone: .unknown)], polls: 5).isEmpty)
    }

    /// Refusing to name a card shouldn't mean accusing it of being in the
    /// wrong place.
    @Test("An unrecognized card is never reported")
    func unrecognizedIsSilent() {
        let unnamed = TrackedObject(
            id: 9, type: .card, center: .zero, boundingBox: .zero, rotation: 0,
            previousZone: .base, currentZone: .base,
            confidence: 0.3, isVisible: true, lastSeenFrame: 1, recognizedLabel: nil
        )
        #expect(Self.run([unnamed], polls: 5).isEmpty)
    }

    @Test("Returning the card clears the report")
    func returningTheCardClearsIt() {
        let monitor = MisplacedCardMonitor()
        let offending = Self.run([Self.object(label: "Order Rune", zone: .base)], polls: 3, monitor: monitor)
        #expect(!offending.isEmpty)

        let corrected = monitor.update(
            objects: [Self.object(label: "Order Rune", zone: .runeArea)],
            kind: Self.kind
        )
        #expect(corrected.isEmpty)
    }
}
