import RiftboundExpertSystem
import CoreGraphics
import Foundation

/// The single seam this layer talks to the Expert System through. Feed it
/// raw per-frame `Detection`s via `ingest(detections:frameIndex:timestamp:)`;
/// it does tracking + temporal confirmation internally and yields
/// `ObservedTableEvent`s out of `events()`, which is exactly the
/// `BoardObserving` contract `GameEngine` already consumes — no new
/// protocol, no Expert System changes.
///
/// Two calibration tables this type owns, deliberately kept out of the
/// Expert System (which shouldn't know cameras/vision exist at all):
///   - `playerCalibration`: physical seat (`Player`) → the Expert System's
///     `PlayerID` for this specific game.
///   - `cardIdentity`: `TrackedObjectID` → `CardDefID`, populated by
///     whatever card-recognition system eventually exists. Until then,
///     events for objects with no known identity are still forwarded —
///     `ObservedTableEvent.card` is optional exactly for this reason (see
///     its doc comment: "nil if the moved/changed object couldn't be
///     re-identified this frame").
///
/// KNOWN GAP — do not silently paper over this: `ObservedTableEvent`'s
/// `TableRegion` can only represent Base, Battlefield, and Hand
/// (`Location` per rule 106 is Base/Battlefield only; Hand gets its own
/// `isHandRegion` flag). Main Deck, Rune Deck, Trash, and Rune Area have
/// no representation in the current Expert System ingestion types at all.
/// That means Draw (Main Deck → Hand) and Channel Rune (Rune Deck → Rune
/// Area) — two of the four physical signatures in the CV spec — cannot be
/// forwarded faithfully yet. `unrepresentableZoneEvents` collects what got
/// dropped so this isn't silently lossy; surface it to whoever owns the
/// Expert System's `ObservedTableEvent`/`TableRegion` types so those zones
/// get a real home there (adding cases to `TableRegion`, not inventing
/// parallel types here).
/// `@unchecked Sendable`: same single-writer contract as `ObjectTracker`/
/// `TemporalEventDetector` (both of which it wraps) — `ingest(...)` must
/// be called strictly in frame order by one caller.
public final class ExpertSystemAdapter: BoardObserving, @unchecked Sendable {
    /// Deliberately a `var`: this used to be fixed at construction, which
    /// meant the calibration the user actually dragged into place never
    /// reached zone resolution. The overlay reads `calibration` live on
    /// every redraw, so the mat *looked* correctly aligned while this
    /// still held whatever calibration existed at `start()` — before the
    /// first frame had even sized it to the camera. Cards then resolved to
    /// `.unknown` (dropped outright) or to the wrong zone entirely. Push
    /// updates through `updateZones(_:)`, which keeps tracking history
    /// alive, unlike rebuilding the whole adapter.
    private var zoneMapper: ZoneMapper
    private let tracker: ObjectTracker
    private let temporalDetector: TemporalEventDetector
    private let playerCalibration: [Player: PlayerID]
    private let battlefieldCalibration: [Int: BattlefieldID]
    /// Seat to attribute an event to when its zone implies none of its own.
    ///
    /// A Battlefield is deliberately unowned (rule 181 — Control is
    /// contested, not a property of the printed region), so
    /// `BoardZone.owner` and `Zone.impliedOwner` are both `nil` there. But
    /// `TableRegion` requires a `PlayerID`, so without a fallback every
    /// event about a card whose track *began* on a Battlefield was
    /// dropped for lack of a seat — which is exactly what happens to a
    /// card played from hand, since the pickup ends one track and the
    /// placement starts a new one. On a single-seat mat there is only one
    /// answer, so refusing to give it wasn't caution, just silence.
    private let defaultSeat: Player?

    /// `TrackedObjectID` → recognized card definition, filled in by a
    /// card-recognition system this layer doesn't own. Public so that
    /// system can call `identify(objectID:as:)` as recognitions arrive.
    private var cardIdentity: [TrackedObjectID: CardDefID] = [:]

    private var previousTimestamp: TimeInterval?
    private var continuation: AsyncStream<ObservedTableEvent>.Continuation?

    /// `VisionEvent`s this adapter received but could not translate,
    /// because their zone has no `TableRegion` representation yet (see
    /// the type's doc comment). Inspect this in debug/testing to see what
    /// Draw/Channel Rune coverage is actually missing right now.
    public private(set) var unrepresentableZoneEvents: [VisionEvent] = []

    /// Buffer behind `drainVisionTrace()`.
    private var visionTrace: [VisionEventTrace] = []

    /// Maps a detector's raw class label (e.g. `"Annie Fiery"`) onto the
    /// canonical `CardDefID` the Expert System's `GameState` is keyed by.
    /// Without this, the label string was wrapped verbatim into a
    /// `CardDefID` — which only ever matched a `GameState` if that state
    /// happened to be built from the same raw label vocabulary, so a
    /// `GameState` built from real card data (keyed by `riftboundID`)
    /// silently failed to resolve every card the camera saw. Defaults to
    /// the old verbatim behavior; the app injects a real
    /// `CardDatabase`-backed resolver.
    private let resolveLabel: @Sendable (String) -> CardDefID?

    public init(
        zoneMapper: ZoneMapper,
        playerCalibration: [Player: PlayerID],
        battlefieldCalibration: [Int: BattlefieldID] = [:],
        tracker: ObjectTracker = ObjectTracker(),
        temporalDetector: TemporalEventDetector = TemporalEventDetector(),
        resolveLabel: @escaping @Sendable (String) -> CardDefID? = { CardDefID(rawValue: $0) },
        defaultSeat: Player? = nil
    ) {
        self.zoneMapper = zoneMapper
        self.playerCalibration = playerCalibration
        self.battlefieldCalibration = battlefieldCalibration
        self.tracker = tracker
        self.temporalDetector = temporalDetector
        self.resolveLabel = resolveLabel
        self.defaultSeat = defaultSeat
    }

    /// Re-points zone resolution at the current calibration. Cheap enough
    /// to call every detection poll; the tracker and temporal detector
    /// keep their history, so a mid-session recalibration doesn't reset
    /// what's already being followed.
    public func updateZones(_ zoneMapper: ZoneMapper) {
        self.zoneMapper = zoneMapper
    }

    /// Record a card-recognition result for a tracked object. Safe to call
    /// at any point after the object first appears — future events for
    /// this `objectID` will carry the identification; past ones already
    /// yielded won't be retroactively updated.
    public func identify(objectID: TrackedObjectID, as cardDefinitionID: CardDefID) {
        cardIdentity[objectID] = cardDefinitionID
    }

    public func events() -> AsyncStream<ObservedTableEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    /// Ends the event stream — call when the camera session stops (or, in
    /// tests, once you're done feeding frames) so consumers of `events()`
    /// see their `for await` loop terminate instead of waiting forever.
    public func finish() {
        continuation?.finish()
    }

    /// Call once per camera frame, in frame order.
    public func ingest(detections: [Detection], frameIndex: Int, timestamp: TimeInterval) {
        let trackerResult = tracker.update(
            detections: detections,
            zoneMapper: zoneMapper,
            frameIndex: frameIndex,
            timestamp: timestamp,
            previousTimestamp: previousTimestamp
        )
        previousTimestamp = timestamp

        let visionEvents = temporalDetector.process(trackerResult, zoneMapper: zoneMapper, timestamp: timestamp)
        for visionEvent in visionEvents {
            let observed = observedTableEvent(for: visionEvent)
            if let observed {
                continuation?.yield(observed)
            } else {
                unrepresentableZoneEvents.append(visionEvent)
            }
            record(VisionEventTrace(event: visionEvent, wasForwarded: observed != nil))
        }

        liveTrackCount = trackerResult.objects.count
    }

    /// How many physical objects the tracker is currently following. A
    /// count that keeps climbing while cards stay put means tracks are
    /// being abandoned and re-created rather than followed.
    public private(set) var liveTrackCount = 0

    private func record(_ trace: VisionEventTrace) {
        visionTrace.append(trace)
        // Bounded in case nothing ever drains this — a debug tap must not
        // become a leak.
        if visionTrace.count > 200 {
            visionTrace.removeFirst(visionTrace.count - 200)
        }
    }

    /// Every `VisionEvent` produced since the last call, paired with
    /// whether it made it across the boundary into the Expert System.
    ///
    /// This is the *pre-translation* view: it includes events for zones
    /// `TableRegion` can't represent (Rune Area, Trash, the decks) and
    /// events dropped for want of a seat, neither of which is visible
    /// downstream. Debugging tracking through the translated stream means
    /// debugging it through a filter that silently removes the
    /// interesting cases.
    public func drainVisionTrace() -> [VisionEventTrace] {
        defer { visionTrace = [] }
        return visionTrace
    }

    // MARK: - VisionEvent → ObservedTableEvent

    private func observedTableEvent(for event: VisionEvent) -> ObservedTableEvent? {
        func card(at region: TableRegion) -> CardIdentification? {
            // `identify(objectID:as:)` (a manual/external override) wins
            // when present; otherwise fall back to whatever the detector
            // itself recognized this frame. The fallback matters more in
            // practice: `tracker`/`temporalDetector` are private to this
            // adapter, so nothing outside it can ever discover the right
            // `TrackedObjectID` to call `identify` with — `identify` only
            // helps a caller that has some *other* source of identity
            // (e.g. manual assignment) keyed by an ID it learned some
            // other way.
            let definitionID = cardIdentity[event.objectID] ?? event.recognizedLabel.flatMap(resolveLabel)
            return definitionID.map {
                CardIdentification(cardDefinitionID: $0, physicalRegion: region, confidence: Double(event.confidence))
            }
        }

        switch event.type {
        case .objectMoved:
            // NOTE: `from` always resolves with `battlefieldSlot: nil`
            // because `VisionEvent` only carries the *destination*
            // slot — a Battlefield → Battlefield move (Ganking, 140.4.c)
            // can't currently be disambiguated on its origin side. Rare
            // enough to leave as a flagged gap rather than plumb a second
            // slot field through for now.
            guard let from = region(for: event.previousZone, battlefieldSlot: nil, player: event.player),
                  let to = region(for: event.currentZone, battlefieldSlot: event.battlefieldSlot, player: event.player) else {
                return nil
            }
            return ObservedTableEvent(kind: .cardMoved(from: from, to: to), card: card(at: to), observedAt: event.timestamp)

        case .objectRotated:
            guard let region = region(for: event.currentZone, battlefieldSlot: event.battlefieldSlot, player: event.player) else {
                return nil
            }
            // 592/593: rotated to 90° = Exhausted, rotated back to 0° =
            // Ready. This assumes the rotation-bucket convention lines up
            // with the physical calibration (0° = Ready) — recalibrate
            // `TemporalEventDetector.rotationBucketDegrees`'s reference
            // frame against the actual table if that's not true.
            let nowExhausted = event.currentRotation.map { abs($0.truncatingRemainder(dividingBy: .pi)) > 0.01 } ?? false
            return ObservedTableEvent(kind: .cardOrientationChanged(region: region, nowExhausted: nowExhausted), card: card(at: region), observedAt: event.timestamp)

        case .objectAppeared:
            guard let region = region(for: event.currentZone, battlefieldSlot: event.battlefieldSlot, player: event.player) else {
                return nil
            }
            return ObservedTableEvent(kind: .cardAppeared(region: region), card: card(at: region), observedAt: event.timestamp)

        case .objectDisappeared:
            guard let region = region(for: event.previousZone, battlefieldSlot: nil, player: event.player) else {
                return nil
            }
            return ObservedTableEvent(kind: .cardRemoved(region: region), card: card(at: region), observedAt: event.timestamp)
        }
    }

    /// Maps a coarse `Zone` (+ disambiguating battlefield slot / seat) onto
    /// a `TableRegion`. Returns `nil` for zones `TableRegion` can't
    /// represent yet (Main Deck, Rune Deck, Trash, Rune Area, Legend,
    /// Champion, `.unknown`) — callers must treat `nil` as "cannot
    /// forward," not as a legal empty region.
    private func region(for zone: Zone?, battlefieldSlot: Int?, player: Player?) -> TableRegion? {
        guard let zone else { return nil }
        // `defaultSeat` covers zones that imply no seat of their own —
        // most importantly the Battlefield, where a played card's brand
        // new track would otherwise carry no seat and be dropped.
        guard let seat = player ?? defaultSeat, let ownerID = playerCalibration[seat] else { return nil }

        switch zone {
        case .player1Hand, .player2Hand:
            return TableRegion(owner: ownerID, location: nil, isHandRegion: true)
        case .base:
            return TableRegion(owner: ownerID, location: .base(ownerID), isHandRegion: false)
        case .battlefield:
            guard let slot = battlefieldSlot, let battlefieldID = battlefieldCalibration[slot] else { return nil }
            return TableRegion(owner: ownerID, location: .battlefield(battlefieldID), isHandRegion: false)
        case .mainDeck, .runeDeck, .trash, .runeArea, .legend, .champion, .unknown:
            // See the type's doc comment — no `Location`/`TableRegion`
            // representation exists for these yet. Legend Zone/Champion
            // Zone are Zones but not Locations per rule 106.5.b, same
            // category as Hand/Deck/Trash — they'd need the same
            // `TableRegion` extension the other non-Location zones do.
            return nil
        }
    }
}
