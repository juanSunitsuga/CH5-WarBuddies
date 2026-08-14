import Testing
import Foundation
import CoreGraphics
@testable import RiftboundVision
import RiftboundExpertSystem
import RiftboundTextProcessing

/// The whole pipeline, stage ① output through stage ④ output, with no
/// stubs between stages: raw `Detection`s (what `CoreMLCardDetector`
/// emits) → `ExpertSystemAdapter` tracking/zones → the real
/// `ExpertSystemTranslatorAdapter` → `GameEngine`'s validator/applier/
/// Cleanup → a `PlayerInstruction`.
///
/// This is the test that would have caught the label/`CardDefID` mismatch:
/// the detector labels cards `"Annie Fiery"` while `GameState` is keyed by
/// `riftboundID` (`"ogs-001-024"`), so without the adapter's injected
/// `resolveLabel` the engine never finds the card in hand and rejects
/// every Play.
struct FullPipelineIntegrationTests {

    private static func square(_ minX: CGFloat, _ minY: CGFloat, _ size: CGFloat = 50) -> [CGPoint] {
        [CGPoint(x: minX, y: minY), CGPoint(x: minX + size, y: minY), CGPoint(x: minX + size, y: minY + size), CGPoint(x: minX, y: minY + size)]
    }

    private static func loadDatabase() throws -> CardDatabase {
        let url = try #require(Bundle.module.url(forResource: "annie_trimmed", withExtension: "json"))
        return try CardDatabase(jsonDeckFiles: [try Data(contentsOf: url)])
    }

    /// Mirrors the app's `GameSessionBuilder`: hand seeded from the card
    /// database, keyed by `riftboundID`, with enough Energy that cost
    /// isn't what's under test here.
    private static func makeState(database: CardDatabase, player: PlayerID, battlefieldID: BattlefieldID) -> GameState {
        let printings = database.allPrintings
        let legendPrinting = printings.first { $0.classification.type.lowercased() == "legend" }
        let legend = ChampionLegend(
            definitionID: CardDefID(rawValue: legendPrinting?.riftboundID ?? "legend-placeholder"),
            owner: player,
            name: legendPrinting?.name ?? "Unknown Legend",
            domains: [],
            championTag: legendPrinting?.name ?? "Unknown"
        )

        let hand = printings.compactMap { printing -> MainDeckCard? in
            let type: MainDeckCardType
            switch printing.classification.type.lowercased() {
            case "unit": type = .unit(isChampion: false)
            case "gear": type = .gear
            case "spell": type = .spell
            default: return nil
            }
            return MainDeckCard(
                definitionID: CardDefID(rawValue: printing.riftboundID),
                owner: player,
                name: printing.name,
                type: type,
                cost: Cost(energy: printing.attributes.energy ?? 0),
                might: printing.attributes.might
            )
        }

        let battlefield = Battlefield(id: battlefieldID, definitionID: CardDefID(rawValue: "bf"), owner: player, name: "Void Gate")
        var state = GameState(
            turnOrder: [player],
            battlefields: [battlefieldID: battlefield],
            zones: [player: PlayerZones(hand: hand, legend: legend)]
        )
        state.zones[player]?.runePool.energy = 99
        return state
    }

    /// Six frames of a card physically moving Hand → Battlefield, exactly
    /// the cadence `ExpertSystemAdapterTests` established as producing one
    /// confirmed move (two frames per position; the middle pair is the
    /// in-transit position outside any zone).
    private static func playFrames(label: String, into adapter: ExpertSystemAdapter) {
        func card(at point: CGPoint) -> Detection {
            Detection(
                type: .card,
                center: point,
                boundingBox: CGRect(x: point.x - 10, y: point.y - 15, width: 20, height: 30),
                rotation: 0,
                confidence: 0.95,
                recognizedLabel: label
            )
        }
        let positions: [CGPoint] = [
            CGPoint(x: 25, y: 25), CGPoint(x: 25, y: 25),
            CGPoint(x: 1000, y: 1000), CGPoint(x: 1000, y: 1000),
            CGPoint(x: 225, y: 225), CGPoint(x: 225, y: 225)
        ]
        for (index, point) in positions.enumerated() {
            adapter.ingest(detections: [card(at: point)], frameIndex: index, timestamp: Double(index) / 30)
        }
        adapter.finish()
    }

    private static func makeAdapter(
        database: CardDatabase,
        player: PlayerID,
        battlefieldID: BattlefieldID
    ) -> ExpertSystemAdapter {
        ExpertSystemAdapter(
            zoneMapper: ZoneMapper(zones: [
                BoardZone(type: .player1Hand, polygon: square(0, 0), owner: .player1),
                BoardZone(type: .battlefield, polygon: square(200, 200), battlefieldSlot: 0)
            ]),
            playerCalibration: [.player1: player],
            battlefieldCalibration: [0: battlefieldID],
            tracker: ObjectTracker(matchDistanceThreshold: 2000),
            resolveLabel: { label in
                database.printing(approximatelyNamed: label).map { CardDefID(rawValue: $0.riftboundID) }
            }
        )
    }

    /// Stage ① → ②: the detector's raw label resolves to the same
    /// canonical `CardDefID` the Expert System's `GameState` is keyed by.
    /// Without `resolveLabel` this yields the literal string `"Annie
    /// Fiery"`, which matches nothing in `GameState` — the exact silent
    /// failure this asserts against.
    @Test("Stage 1-2: a detector label resolves to the canonical riftboundID CardDefID")
    func detectorLabelResolvesToCanonicalCardDefID() async throws {
        let database = try Self.loadDatabase()
        let player = PlayerID()
        let battlefieldID = BattlefieldID()
        let adapter = Self.makeAdapter(database: database, player: player, battlefieldID: battlefieldID)

        let stream = adapter.events()
        Self.playFrames(label: "Annie Fiery", into: adapter)

        var received: [RiftboundExpertSystem.ObservedTableEvent] = []
        for await event in stream { received.append(event) }

        let moved = try #require(received.first { if case .cardMoved = $0.kind { return true }; return false })
        #expect(moved.card?.cardDefinitionID == CardDefID(rawValue: "ogs-001-024"))
    }

    /// The whole thing: detections in, a player-facing accepted Play out,
    /// with `GameState` actually mutated (card left hand, unit entered the
    /// board exhausted per 563.1.c).
    @Test("Stage 1-4: raw detections of a card played to the battlefield produce an accepted Play")
    func fullPipelineProducesAcceptedPlay() async throws {
        let database = try Self.loadDatabase()
        let player = PlayerID()
        let battlefieldID = BattlefieldID()
        let adapter = Self.makeAdapter(database: database, player: player, battlefieldID: battlefieldID)

        let store = GameStateStore(initialState: Self.makeState(database: database, player: player, battlefieldID: battlefieldID))
        // Same wiring the app uses: `printing.id` is the catalogue id the
        // NLP package's card database is keyed by. Without it every lookup
        // misses, since the pipeline's `riftbound_id` shares no values with
        // that id space.
        let translator = ExpertSystemTranslatorAdapter { defID in
            let printing = database.printing(riftboundID: defID.rawValue)
            return .init(
                databaseID: printing?.id,
                name: printing?.name,
                printedText: printing?.text.plain
            )
        }
        let engine = GameEngine(store: store, observer: adapter, translator: translator)

        let stream = adapter.events()
        Self.playFrames(label: "Annie Fiery", into: adapter)

        var instructions: [PlayerInstruction] = []
        for await event in stream {
            instructions.append(await engine.process(event))
        }

        #expect(!instructions.isEmpty, "The pipeline produced no instruction at all — stage 1/2 didn't emit an event.")

        // The NLP classifier is a real CoreML model, so which candidate it
        // produces isn't guaranteed deterministic across model revisions.
        // What *is* guaranteed: nothing may be rejected for a reason that
        // signals broken plumbing rather than a genuine rules verdict.
        for instruction in instructions {
            if case .actionRejected(_, let reason) = instruction {
                #expect(reason != .notImplemented, "Reached an unimplemented GameAction — the engine can't act on what the pipeline produced.")
                #expect(!Self.isCardNotInHand(reason), "The observed card wasn't found in hand — CardDefID keying is mismatched between stages.")
            }
        }

        guard instructions.contains(where: { if case .actionAccepted = $0 { return true }; return false }) else {
            // Not a failure of wiring — the classifier declined to call it
            // a play. Recorded rather than silently passing.
            Issue.record("No Play was accepted; instructions were: \(instructions)")
            return
        }

        let finalState = await store.currentState
        #expect(finalState.units.values.contains { $0.cardDefinitionID == CardDefID(rawValue: "ogs-001-024") })
        #expect(finalState.zones[player]?.hand.contains { $0.definitionID == CardDefID(rawValue: "ogs-001-024") } == false)
    }

    private static func isCardNotInHand(_ failure: LegalityValidator.Failure) -> Bool {
        if case .cardNotInHand = failure { return true }
        return false
    }

    /// Throughput guard. Stage ③ runs a real CoreML classifier per event,
    /// which is the pipeline's slowest link and the one most likely to
    /// become a bottleneck — the camera polls detections every 0.35s
    /// (`CameraPipelineController.detectionPollInterval`), so a single
    /// event must resolve well inside that budget or events will queue up
    /// in the adapter's unbounded `AsyncStream` faster than they drain.
    @Test("Stage 3-4 keeps up with the camera's detection poll interval")
    func enginePerEventLatencyFitsThePollBudget() async throws {
        let database = try Self.loadDatabase()
        let player = PlayerID()
        let battlefieldID = BattlefieldID()

        let store = GameStateStore(initialState: Self.makeState(database: database, player: player, battlefieldID: battlefieldID))
        // Same wiring the app uses: `printing.id` is the catalogue id the
        // NLP package's card database is keyed by. Without it every lookup
        // misses, since the pipeline's `riftbound_id` shares no values with
        // that id space.
        let translator = ExpertSystemTranslatorAdapter { defID in
            let printing = database.printing(riftboundID: defID.rawValue)
            return .init(
                databaseID: printing?.id,
                name: printing?.name,
                printedText: printing?.text.plain
            )
        }
        let engine = GameEngine(store: store, observer: NeverObservingStub(), translator: translator)

        let event = RiftboundExpertSystem.ObservedTableEvent(
            kind: .cardMoved(
                from: TableRegion(owner: player, location: nil, isHandRegion: true),
                to: TableRegion(owner: player, location: .battlefield(battlefieldID), isHandRegion: false)
            ),
            card: CardIdentification(
                cardDefinitionID: CardDefID(rawValue: "ogs-001-024"),
                physicalRegion: TableRegion(owner: player, location: .battlefield(battlefieldID), isHandRegion: false),
                confidence: 0.95
            ),
            observedAt: 0
        )

        // Warm the model first — first-call CoreML load time isn't the
        // steady-state cost the camera loop actually lives with.
        _ = await engine.process(event)

        let iterations = 5
        let start = Date()
        for _ in 0..<iterations {
            _ = await engine.process(event)
        }
        let perEvent = Date().timeIntervalSince(start) / Double(iterations)

        #expect(
            perEvent < 0.35,
            "Stage 3+4 takes \(String(format: "%.3f", perEvent))s per event, at or past the 0.35s detection poll interval — events will queue faster than they drain."
        )
    }
}

/// `GameEngine.init` requires a `BoardObserving`; the latency test drives
/// `process(_:)` directly and never consumes the stream.
private struct NeverObservingStub: BoardObserving {
    func events() -> AsyncStream<RiftboundExpertSystem.ObservedTableEvent> {
        AsyncStream { $0.finish() }
    }
}
