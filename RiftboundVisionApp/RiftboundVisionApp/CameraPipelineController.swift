import SwiftUI
import SwiftData
import CoreImage
import RiftboundVision
import RiftboundExpertSystem
import RiftboundTextProcessing

/// One stage of the CV → Expert System pipeline, in dependency order —
/// matches the 4-stage pipeline documented in the root README. Each
/// stage needs the one before it enabled to produce anything worth
/// consuming, which is what the settings overlay's cascade behavior
/// enforces: turning a stage off also turns off everything after it.
enum PipelineStage: Int, CaseIterable, Identifiable {
    case detection = 1
    case objectTracking = 2
    case nlpTranslation = 3
    case expertSystem = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .detection: return "① YOLO Detection"
        case .objectTracking: return "② Object Tracking + Zones"
        case .nlpTranslation: return "③ NLP Translation"
        case .expertSystem: return "④ Expert System"
        }
    }

    /// Whether this stage is actually implemented in the app's live
    /// per-frame loop right now. All four are wired: ③/④ run inside
    /// `GameEngine.process`, which calls the NLP translator
    /// (`ExpertSystemTranslatorAdapter`) and then the Expert System's
    /// validator/applier/Cleanup in sequence. Because ③ and ④ live behind
    /// that single call, toggling ③ off stops the whole engine — there's
    /// no way to run the Expert System on actions the translator never
    /// produced, which is exactly the cascade the settings panel models.
    var isWired: Bool { true }
}

/// Drives camera → detector and publishes what the live overlay needs to
/// render. This is deliberately app-shell code (lives here, not in the
/// `RiftboundVision` library) — it exists to make the detection pipeline's
/// current state visible on screen.
///
/// Detection architecture matches `feature/riftbound-scanner-prototype`'s
/// `DetectionCoordinator` on purpose: poll the latest frame on a fixed
/// interval and republish a fresh, unfiltered-by-identity array every
/// time — no `TrackedObjectID`, no zone history, no occlusion tolerance.
/// Each poll is independent, so results can flicker frame to frame the
/// way raw model output does; that's the tradeoff for not carrying any
/// tracking state that could itself go stale or wrong. Card recognition
/// is a fresh `cardDatabase` lookup per detection too, not cached.
///
/// A *second*, independent consumer reads the same polled detections for
/// game-state purposes: `expertSystemAdapter` runs its own internal
/// `ObjectTracker`/`ZoneMapper`/`TemporalEventDetector` (see
/// `ExpertSystemAdapter`) to turn them into `ObservedTableEvent`s. This is
/// deliberately not the same code path as the live overlay above — the
/// overlay wants "what's visible right now," the Expert System wants
/// "what changed, debounced and identity-stable." Reverting the overlay
/// back to tracked mode to get that would have undone the whole point of
/// the stateless redesign; running two consumers off the same detections
/// keeps both needs met without forcing one architecture to serve both.
///
/// The playmat overlay (`calibration`) starts centered on the first frame
/// and does nothing useful until the user drags its corners onto their
/// actual physical mat (see `isCalibrating`). It's purely visual for the
/// live-detection overlay above (which scans the full frame, matching the
/// prototype), but it IS what `expertSystemAdapter`'s `ZoneMapper` is
/// built from — dragging the corners into place is what makes Hand/Base/
/// Battlefield resolve to real zones for game-state ingestion instead of
/// `.unknown`.
@MainActor
final class CameraPipelineController: ObservableObject {
    @Published var backgroundImage: CGImage?
    @Published var detections: [Detection] = []
    @Published var frameSize: CGSize = .zero
    @Published var errorMessage: String?
    @Published var isRunning = false

    /// Every camera currently visible to AVFoundation, refreshed on demand
    /// (see `refreshAvailableCameras()`) — a nearby iPhone only appears
    /// here once Continuity Camera has it ready, so this can change
    /// between refreshes without any action on this app's part.
    @Published var availableCameras: [CameraDeviceOption] = []
    /// `nil` means "system default video device." Selecting a specific
    /// device (including a `.isContinuityCamera` one) is exactly how "use
    /// my iPhone as the camera" is expressed — there's no separate pairing
    /// step here, Continuity Camera handles that at the OS level.
    @Published var selectedCameraID: String?

    /// The playmat template's alignment against the current camera frame —
    /// a visual reference layer only (see this type's doc comment); it is
    /// never consulted by detection. Starts centered on whatever the first
    /// frame's size turns out to be (see `process(_:)`) and is otherwise
    /// only ever changed by the user dragging `PlaymatOverlayView`'s
    /// corner handles.
    @Published var calibration = CameraPipelineController.defaultCalibration(for: CGSize(width: 1280, height: 720))
    /// Shows the draggable corner handles.
    @Published var isCalibrating = false
    /// Output of `runCameraDiagnostic()` — every video device macOS
    /// reports, across every device type, not just the curated picker
    /// list. For "Continuity Camera works elsewhere but this app says no
    /// iPhone camera found" — answers whether the device is missing
    /// entirely or just showing up under a `deviceType` the picker
    /// doesn't recognize as a phone.
    @Published var debugReport: String?

    /// Whose turn it is, what phase, and what round — set by hand (see
    /// `GameStateBar`), never inferred from the camera. Nothing in
    /// `process(_:)` reads or writes this; it exists purely for on-screen
    /// display and for the user's own bookkeeping.
    @Published var gameState = ManualGameState()

    /// UI-only flag for the "Auto-detect" toggle in the turn control bar —
    /// no vision-driven phase detection is actually wired up yet (nothing
    /// in `process(_:)` reads or writes `gameState` from the camera feed,
    /// same limitation `gameState`'s own doc comment describes). While
    /// this is on, the app is asserting phase advancement should come from
    /// detection rather than the Next/End Turn buttons, so those buttons
    /// disable — but there's no real detector behind it yet.
    @Published var isAutoDetectingPhase = false

    /// Rule 190/191: points toward the 8 needed to win. Set by hand for
    /// the same reason `gameState` is — scoring happens on a physical dial
    /// or by agreement, and no card movement the camera can see reliably
    /// implies it. (Cleanup *can* score a contested Battlefield in the
    /// engine, but this app's `GameState` has no opponent seat to score
    /// against, so the two aren't connected yet.)
    @Published var playerScore = 0
    @Published var opponentScore = 0

    /// Every `ObservedTableEvent` the reconnected tracking pipeline
    /// (`expertSystemAdapter`) has produced this session, most recent
    /// last, capped so a long session doesn't grow this unboundedly.
    /// Nothing consumes these into a real `GameState`/`GameEngine` yet —
    /// that needs actual game setup (a decklist, player identification),
    /// which this app has no UI for. This is the observable proof the
    /// reconnected Object Tracking + Area of Region pipeline is really
    /// producing real events, and the seam a future GameEngine wiring
    /// would read from.
    @Published private(set) var observedEvents: [RiftboundExpertSystem.ObservedTableEvent] = []

    /// Which `PipelineStage`s the user has asked to run, via the settings
    /// overlay. Independent of `PipelineStage.isWired` — a stage can be
    /// "requested" here and still do nothing if it isn't wired into
    /// `process(_:)` yet (see `isStageActive(_:)`, which is what actually
    /// gates behavior and accounts for both).
    @Published var enabledStages: Set<PipelineStage> = Set(PipelineStage.allCases)

    /// What the Expert System has decided about what it saw, newest first —
    /// the end of the pipeline and the thing the user actually reads. Each
    /// entry is a `PlayerInstruction` rendered to text (see
    /// `InstructionLogEntry`).
    @Published private(set) var instructions: [InstructionLogEntry] = []

    let cardDatabase = CardDatabaseLoader.loadBundled()

    /// Overlaps the rules forbid (currently Unit-on-Unit), recomputed each
    /// detection poll by `UnderlayResolver` — surfaced so the UI can warn
    /// the player instead of silently mis-modeling an illegal stack.
    @Published var illegalOverlaps: [IllegalOverlap] = []

    /// Minted once per app session — there's no player-identification UI,
    /// so there's no real per-match `PlayerID` to use yet. `.player1`
    /// (the calibrated mat's owner, "You" throughout this app) maps to
    /// `localPlayerID`. No opponent seat — this app tracks one physical
    /// mat/camera only.
    let localPlayerID = PlayerID()
    /// One per `RiftboundPlaymatTemplate.singlePlayerZones()` Battlefield
    /// slot (just slot 0 now — the template calibrates a single physical
    /// Battlefield card) — same "minted once per session" caveat as the
    /// player IDs above.
    let battlefieldSlotIDs: [Int: BattlefieldID] = [0: BattlefieldID()]

    private let camera = AVFoundationCameraCapture()
    private let detector: any ObjectDetecting = CardDetectionModelLoader.loadDetector()
    private let ciContext = CIContext()

    /// Matches `feature/riftbound-scanner-prototype`'s
    /// `DetectionCoordinator.pollInterval` (0.35s) — the CoreML/Vision
    /// pass is the expensive step and doesn't need to run at full camera
    /// framerate, especially now that there's no per-object tracking to
    /// keep in sync frame-to-frame.
    private static let detectionPollInterval: TimeInterval = 0.35
    private var lastDetectionTimestamp: TimeInterval?

    // MARK: - Persistence consumer

    /// A *third* consumer of the same polled detections (after the live
    /// overlay and `expertSystemAdapter`): its own `ObjectTracker`, so the
    /// durable board store has the stable per-card identity the stateless
    /// overlay deliberately doesn't keep. `ExpertSystemAdapter` owns its
    /// tracker privately, so this can't share that one — the duplication is
    /// the price of not reverting the overlay to tracked mode.
    private let persistenceTracker = ObjectTracker()
    private let underlayResolver = UnderlayResolver()
    private var persistenceFrameIndex = 0
    private var persistencePreviousTimestamp: TimeInterval?

    /// Durable board store, injected from the app's `ModelContainer`. `nil`
    /// in previews / the no-arg path, where persistence simply no-ops.
    private let modelContext: ModelContext?
    /// In-memory mirror of persisted rows, keyed by tracking id, so the
    /// per-poll sync doesn't fetch from disk every time — we insert once
    /// and mutate in place, saving only when a field actually changed.
    private var persistedCards: [TrackedObjectID: PersistentTrackedCard] = [:]
    /// How many consecutive detection polls each card has sat in the Trash
    /// zone. A card only gets deleted after `trashConfirmationPolls`, so a
    /// card merely dragged *across* the trash area on its way elsewhere
    /// isn't destroyed. Cleared the moment a card leaves the trash zone.
    private var trashPollCounts: [TrackedObjectID: Int] = [:]
    /// ~1s at the 0.35s poll cadence — the design brief's deletion buffer,
    /// restated in polls now that detection no longer runs per frame.
    private let trashConfirmationPolls = 3

    /// Rebuilt from `calibration` on every access rather than cached —
    /// cheap (it's ~15 small polygons), and guarantees it's never one
    /// poll stale relative to a corner the user just dragged.
    private var zoneMapper: ZoneMapper { ZoneMapper(zones: calibration.boardZones()) }

    private var hasSizedCalibrationToFrame = false
    private var runLoop: Task<Void, Never>?
    private var statusLoop: Task<Void, Never>?

    /// The reconnected Object Tracking + Area of Region consumer (see
    /// this type's doc comment) — built fresh in `start()`, from
    /// `calibration` as it stands at that moment.
    ///
    /// KNOWN LIMITATION: its `ZoneMapper` is a one-time snapshot, not
    /// live — re-dragging the calibration corners after `start()` keeps
    /// updating the visual overlay (which reads `calibration` directly
    /// every redraw) but won't retroactively fix zone resolution here.
    /// Flagging rather than hiding: fixing this properly means either
    /// rebuilding the adapter on every calibration change (losing its
    /// tracking history each time) or teaching `ExpertSystemAdapter` to
    /// accept a live zone source instead of a fixed one — a real design
    /// question, not a quick patch, so left for whoever picks this up
    /// once recalibrating mid-session is actually a problem in practice.
    private var expertSystemAdapter: ExpertSystemAdapter?
    private var expertSystemFrameIndex = 0
    private var expertSystemEventLoop: Task<Void, Never>?

    /// Stage ③+④. `GameEngine` owns the whole tail of the pipeline: it
    /// calls the NLP translator to turn an `ObservedTableEvent` into a
    /// candidate `GameAction`, runs `LegalityValidator`, applies it through
    /// `GameStateStore` with `Cleanup`, and hands back a
    /// `PlayerInstruction`. Built in `start()` alongside the vision
    /// adapter, since it needs that adapter as its `BoardObserving` source.
    private var gameEngine: GameEngine?
    private var gameStateStore: GameStateStore?

    /// The starting calibration quad, sized so the *whole* active
    /// template — including Hand, which extrapolates past the quad's own
    /// bottom edge (see `RiftboundPlaymatTemplate.singlePlayerZones()`) —
    /// lands on screen before the user has dragged a single corner.
    /// Without this, Hand's mapped position falls below the visible frame
    /// by default, since `PlaymatCalibration.centered(in:)` alone only
    /// guarantees `y = 0...1` (the mat itself) stays in view.
    private static func defaultCalibration(for frameSize: CGSize) -> PlaymatCalibration {
        let contentHeight = RiftboundPlaymatTemplate.singlePlayerZones()
            .flatMap(\.normalizedPolygon)
            .map(\.y)
            .max() ?? 1.0
        return .centered(in: frameSize, contentHeight: contentHeight)
    }

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        // Listening starts immediately, not just while capturing — device
        // list changes (an iPhone's Continuity Camera reappearing) should
        // refresh the picker even before the user ever presses Start.
        statusLoop = Task {
            for await event in camera.statusEvents() {
                await self.handle(event)
            }
        }
        refreshAvailableCameras()
    }

    /// Re-scans for available cameras. Called automatically on
    /// `.deviceListChanged` (see `handle(_:)`) and whenever the picker
    /// appears; safe to call any time — cheap, no new discovery session
    /// is created (see `AVFoundationCameraCapture.availableDevices()`).
    func refreshAvailableCameras() {
        availableCameras = AVFoundationCameraCapture.availableDevices()
    }

    /// Explicit "use my iPhone as the camera" action. Passive discovery
    /// (the KVO-observed `discoverySession` in `AVFoundationCameraCapture`)
    /// only reliably catches an iPhone macOS still considers idle-but-
    /// available. Once you tap **Disconnect** in the phone's own
    /// Continuity Camera control, Apple gives third-party apps no public
    /// API to be told when it's available again — the entry can simply
    /// stop appearing in `availableDevices()` until something actively
    /// tries to open it, which is what triggers the reconnect/permission
    /// handshake with the phone. That's what this does, instead of
    /// waiting on a notification that may never come.
    func useIPhoneCamera() {
        refreshAvailableCameras()
        guard let iPhone = availableCameras.first(where: { $0.isContinuityCamera }) else {
            errorMessage = "No iPhone camera found. On your iPhone: Control Center → tap the Camera Continuity icon (or Settings → General → AirPlay & Handoff → Continuity Camera), then press this again."
            return
        }

        selectedCameraID = iPhone.id
        errorMessage = nil

        if isRunning {
            do {
                try camera.switchCamera(to: iPhone.id)
            } catch {
                errorMessage = "Couldn't switch to iPhone camera: \(error)"
            }
        } else {
            start()
        }
    }

    /// Prints (and stores, for on-screen display) a full device report —
    /// see `debugReport`'s doc comment.
    func runCameraDiagnostic() {
        let report = AVFoundationCameraCapture.debugDeviceReport()
        print(report)
        debugReport = report
    }

    /// Whether `stage` is actually active right now — requested (in
    /// `enabledStages`), actually wired into the live loop, *and* every
    /// stage before it is active too. This is what `process(_:)` and the
    /// settings overlay should read, not `enabledStages` directly.
    func isStageActive(_ stage: PipelineStage) -> Bool {
        guard stage.isWired, enabledStages.contains(stage) else { return false }
        return PipelineStage.allCases
            .filter { $0.rawValue < stage.rawValue }
            .allSatisfy { isStageActive($0) }
    }

    /// Turns `stage` on/off. Turning a stage off also turns off every
    /// stage after it — each depends on the output of the one before, so
    /// "cut stage 2" means stage 3/4 cut down automatically too, rather
    /// than silently running on stale/impossible input.
    func setStage(_ stage: PipelineStage, enabled: Bool) {
        if enabled {
            enabledStages.insert(stage)
        } else {
            for laterOrEqual in PipelineStage.allCases where laterOrEqual.rawValue >= stage.rawValue {
                enabledStages.remove(laterOrEqual)
            }
        }
    }

    func selectCamera(id: String?) {
        selectedCameraID = id
        guard isRunning else { return }
        // Switching while already running: fall back to whatever
        // AVFoundation calls "default" if the user picked System Default
        // explicitly, since `switchCamera` needs a concrete device.
        let targetID = id ?? AVFoundationCameraCapture.availableDevices().first(where: { $0.isBuiltIn })?.id
        guard let targetID else { return }
        do {
            try camera.switchCamera(to: targetID)
        } catch {
            errorMessage = "Couldn't switch camera: \(error)"
        }
    }

    func start() {
        guard !isRunning else { return }
        do {
            try camera.start(deviceID: selectedCameraID)
        } catch {
            errorMessage = "Camera failed to start: \(error)"
            return
        }
        isRunning = true
        errorMessage = nil

        // Reconnect Object Tracking + Area of Region as a second consumer
        // of the same detections `process(_:)` feeds the live overlay —
        // see `expertSystemAdapter`'s doc comment for the snapshot-zone
        // caveat.
        //
        // `resolveLabel` is what makes the detector's raw class label
        // ("Annie Fiery") agree with the `CardDefID`s `GameSessionBuilder`
        // keyed `GameState` by (`riftboundID`). Without it the engine
        // would never find the observed card in hand and would reject
        // every Play — see `CardDatabase.printing(approximatelyNamed:)`.
        let database = cardDatabase
        let adapter = ExpertSystemAdapter(
            zoneMapper: ZoneMapper(zones: calibration.boardZones()),
            playerCalibration: [.player1: localPlayerID],
            battlefieldCalibration: battlefieldSlotIDs,
            resolveLabel: { label in
                database.printing(approximatelyNamed: label).map { CardDefID(rawValue: $0.riftboundID) }
            }
        )
        expertSystemAdapter = adapter
        expertSystemFrameIndex = 0

        // Stage ③+④: a real GameState, the NLP translator, and the engine
        // that runs both against every observed event.
        let session = GameSessionBuilder.makeSession(
            database: database,
            localPlayerID: localPlayerID,
            battlefieldSlotIDs: battlefieldSlotIDs
        )
        // `CardPrinting.id` is what makes the NLP package's SQLite lookup
        // reachable at all: that database keys on a hex `card_id`
        // (`69bc5bc6d308c64675ca86bc`) which shares no values with the
        // `riftbound_id` (`ogn-007-298`) this pipeline uses for `CardDefID`.
        // Both come from the same catalogue, so `printing.id` matches every
        // row — without passing it every lookup missed, and the engine fell
        // through to the CoreML/regex path for cards it already knew.
        let translator = ExpertSystemTranslatorAdapter { defID in
            let printing = database.printing(riftboundID: defID.rawValue)
            return .init(
                databaseID: printing?.id,
                name: printing?.name,
                printedText: printing?.text.plain
            )
        }
        let engine = GameEngine(store: session.store, observer: adapter, translator: translator)
        gameStateStore = session.store
        gameEngine = engine
        instructions = []

        // One consumer, not two: the adapter's `events()` stream can only
        // be consumed once (each call replaces the stored continuation),
        // so the engine is driven per-event from here rather than via
        // `engine.run()`, which would try to claim that same stream.
        expertSystemEventLoop = Task {
            for await event in adapter.events() {
                await self.recordObservedEvent(event)
                guard await self.isStageActive(.nlpTranslation) else { continue }
                let instruction = await engine.process(event)
                await self.recordInstruction(instruction, for: event)
            }
        }

        runLoop = Task {
            for await frame in camera.frames() {
                await self.process(frame)
            }
        }
    }

    func stop() {
        camera.stop()
        runLoop?.cancel()
        runLoop = nil
        isRunning = false
        detections = []
        lastDetectionTimestamp = nil

        expertSystemAdapter?.finish()
        expertSystemEventLoop?.cancel()
        expertSystemEventLoop = nil
        expertSystemAdapter = nil
        expertSystemFrameIndex = 0
        gameEngine = nil
        gameStateStore = nil

        // Persisted rows survive a stop (that's the point of the durable
        // store) — only the in-flight bookkeeping resets, since the next
        // session's tracker mints fresh `TrackedObjectID`s.
        persistencePreviousTimestamp = nil
        trashPollCounts = [:]
        illegalOverlaps = []
    }

    deinit {
        statusLoop?.cancel()
    }

    private func recordObservedEvent(_ event: RiftboundExpertSystem.ObservedTableEvent) {
        observedEvents.append(event)
        if observedEvents.count > 50 {
            observedEvents.removeFirst(observedEvents.count - 50)
        }
    }

    private func recordInstruction(_ instruction: PlayerInstruction, for event: RiftboundExpertSystem.ObservedTableEvent) {
        let entry = InstructionLogEntry(instruction: instruction, cardName: cardName(for: event))
        instructions.insert(entry, at: 0)
        if instructions.count > 30 {
            instructions.removeLast(instructions.count - 30)
        }
    }

    /// The printed name behind an event's `CardDefID`, for instruction text
    /// that reads "Played Annie - Fiery" rather than an opaque ID.
    private func cardName(for event: RiftboundExpertSystem.ObservedTableEvent) -> String? {
        guard let defID = event.card?.cardDefinitionID else { return nil }
        return cardDatabase.printing(riftboundID: defID.rawValue)?.name
    }

    /// Reacts to `CameraStatusEvent`s from the capture layer — most
    /// importantly, a disconnected device (an iPhone's Continuity Camera
    /// going away, a USB webcam unplugged). Without this, capture just
    /// silently stops delivering frames and nothing in the UI explains
    /// why or offers a way back — which is exactly the bug this fixes:
    /// falls back to the built-in camera automatically instead of leaving
    /// the app stuck.
    private func handle(_ event: CameraStatusEvent) async {
        switch event {
        case .deviceDisconnected(let deviceID):
            refreshAvailableCameras()
            if selectedCameraID == deviceID {
                selectedCameraID = nil
            }
            if let fallback = availableCameras.first(where: { $0.isBuiltIn }) ?? availableCameras.first {
                do {
                    try camera.switchCamera(to: fallback.id)
                    errorMessage = nil
                } catch {
                    errorMessage = "Camera disconnected, and couldn't fall back automatically: \(error)"
                    isRunning = false
                }
            } else {
                errorMessage = "Camera disconnected — no camera available."
                isRunning = false
            }

        case .interrupted(let reason):
            errorMessage = "Camera interrupted: \(reason)"

        case .interruptionEnded:
            errorMessage = nil

        case .runtimeError(let message):
            errorMessage = "Camera error: \(message)"
            isRunning = false

        case .deviceListChanged:
            // This is the fix for "iPhone won't reappear until another
            // app looks for it" — the picker now updates itself as soon
            // as AVFoundation's (retained) discovery session notices the
            // device again, no manual refresh or app restart needed.
            refreshAvailableCameras()
        }
    }

    private func process(_ frame: CapturedFrame) async {
        let ciImage = CIImage(cvPixelBuffer: frame.pixelBuffer)
        let size = CGSize(width: ciImage.extent.width, height: ciImage.extent.height)

        if !hasSizedCalibrationToFrame {
            calibration = Self.defaultCalibration(for: size)
            hasSizedCalibrationToFrame = true
        }

        // Video stays smooth at full camera framerate regardless of the
        // detection poll below — only the (expensive) detector call is
        // throttled.
        backgroundImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
        frameSize = size

        // Debug kill switch — see `enabledStages`'/`isStageActive`'s doc
        // comments. Bails out after the camera picture above is already
        // updated, so the video itself keeps playing; only detection and
        // everything it feeds stops.
        guard isStageActive(.detection) else {
            detections = []
            return
        }

        // Poll cadence, not per-frame — see `detectionPollInterval`'s doc
        // comment. `frame.timestamp` is the sample buffer's presentation
        // time (seconds), monotonic within a capture session.
        if let lastDetectionTimestamp, frame.timestamp - lastDetectionTimestamp < Self.detectionPollInterval {
            return
        }
        lastDetectionTimestamp = frame.timestamp

        // Full-frame scan, no `regionOfInterest` — matches the
        // prototype's detector, which has no calibrated-area restriction
        // either. `CoreMLCardDetector`'s own confidence floor and
        // card-shape (aspect ratio) gate are what keep this from
        // re-introducing "every square object gets identified."
        detections = (try? detector.detect(in: frame.pixelBuffer)) ?? []

        // Second consumer of the same detections, same poll cadence — see
        // `expertSystemAdapter`'s doc comment. Gated on stage 2 so turning
        // Object Tracking off in the pipeline settings actually stops it,
        // not just stage 1.
        if isStageActive(.objectTracking), let expertSystemAdapter {
            expertSystemFrameIndex += 1
            expertSystemAdapter.ingest(detections: detections, frameIndex: expertSystemFrameIndex, timestamp: frame.timestamp)
        }

        // Third consumer: stacking + durable board state, off its own
        // tracker (see `persistenceTracker`'s doc comment).
        syncBoardState(detections: detections, timestamp: frame.timestamp)
    }

    /// Tracks this poll's detections, resolves stacking (Equipment/Rune
    /// under Unit, reject Unit-on-Unit), and mirrors the result into
    /// SwiftData. No-ops entirely when there's no `modelContext` — nothing
    /// else in the app reads `illegalOverlaps` off a preview.
    private func syncBoardState(detections: [Detection], timestamp: TimeInterval) {
        guard modelContext != nil else { return }

        persistenceFrameIndex += 1
        let result = persistenceTracker.update(
            detections: detections,
            zoneMapper: zoneMapper,
            frameIndex: persistenceFrameIndex,
            timestamp: timestamp,
            previousTimestamp: persistencePreviousTimestamp
        )
        persistencePreviousTimestamp = timestamp

        // The tracker only knows geometry; card *roles* come from what the
        // detector recognized, resolved against the card database here.
        let resolution = underlayResolver.resolve(result.objects) { [weak self] id in
            self?.role(for: id, in: result.objects) ?? .unknown
        }
        illegalOverlaps = resolution.illegalOverlaps

        // Drop disappeared tracks from our per-object bookkeeping so counts
        // and cached rows don't leak (the DB row is left as last-known
        // state; only trash-zone entry deletes it).
        for id in result.disappearedIDs {
            trashPollCounts[id] = nil
            persistedCards[id] = nil
        }

        syncPersistence(resolution.objects)
    }

    /// Maps a tracked object to the coarse stacking role `UnderlayResolver`
    /// needs, via the recognizer's class label. `.unknown` while nothing has
    /// recognized the card yet, which the resolver treats as "never link,
    /// never flag."
    private func role(for id: TrackedObjectID, in objects: [TrackedObject]) -> CardRole {
        guard let printing = printing(for: id, in: objects) else { return .unknown }
        switch printing.classification.type {
        case "Unit": return .unit
        case "Gear", "Rune": return .attachment
        default: return .other
        }
    }

    /// The recognized `CardPrinting` behind a track, if the detector
    /// labeled it and the label matches the bundled database — the same
    /// label→printing lookup `DetectedCardsPanel` does for display.
    private func printing(for id: TrackedObjectID, in objects: [TrackedObject]) -> CardPrinting? {
        guard let label = objects.first(where: { $0.id == id })?.recognizedLabel else { return nil }
        return cardDatabase.printing(approximatelyNamed: label)
    }

    /// Mirrors this poll's card objects into SwiftData, and deletes a card
    /// once it's held steady in the Trash zone for `trashConfirmationPolls`
    /// — the "dead unit → remove from board" path. Deletes only the
    /// on-board `PersistentTrackedCard` instance, never a card *definition*.
    private func syncPersistence(_ objects: [TrackedObject]) {
        guard let modelContext else { return }

        for object in objects where object.type == .card {
            let zone = zoneMapper.zone(for: object.center)

            if zone == .trash {
                let count = (trashPollCounts[object.id] ?? 0) + 1
                trashPollCounts[object.id] = count
                if count >= trashConfirmationPolls {
                    deletePersisted(trackingID: object.id, context: modelContext)
                    trashPollCounts[object.id] = nil
                    continue
                }
            } else {
                trashPollCounts[object.id] = nil
            }

            upsert(object, in: objects, zone: zone, context: modelContext)
        }
    }

    /// Insert-or-update the row for one object, saving only when a field
    /// actually changed (cards sitting still shouldn't churn the disk every
    /// poll). Uses the in-memory cache first, falling back to a fetch for
    /// rows persisted in a previous session.
    private func upsert(_ object: TrackedObject, in objects: [TrackedObject], zone: Zone, context: ModelContext) {
        let printing = printing(for: object.id, in: objects)
        let zoneRaw = zone.rawValue
        // Prefer the printing-aware Exhaust check once the card is
        // recognized (a Battlefield is printed landscape and would read as
        // permanently tapped under the geometry-only fallback).
        let stance: CardStance = printing.map {
            $0.isExhausted(observedBoundingBox: object.boundingBox) ? .exhausted : .ready
        } ?? object.stance
        let orientationRaw = stance.rawValue
        let underlaid = object.underlaidCardIDs

        let card: PersistentTrackedCard
        if let cached = persistedCards[object.id] {
            card = cached
        } else if let fetched = fetchPersisted(trackingID: object.id, context: context) {
            card = fetched
            persistedCards[object.id] = fetched
        } else {
            let inserted = PersistentTrackedCard(
                trackingID: object.id,
                cardID: printing?.riftboundID,
                displayName: printing?.name,
                zoneRaw: zoneRaw,
                orientationRaw: orientationRaw,
                zIndex: object.zIndex,
                underlaidTrackingIDs: underlaid,
                lastSeenFrame: object.lastSeenFrame
            )
            context.insert(inserted)
            persistedCards[object.id] = inserted
            try? context.save()
            return
        }

        // Dirty-check: skip the save entirely if nothing meaningful moved.
        let changed = card.cardID != printing?.riftboundID
            || card.displayName != printing?.name
            || card.zoneRaw != zoneRaw
            || card.orientationRaw != orientationRaw
            || card.zIndex != object.zIndex
            || card.underlaidTrackingIDs != underlaid
        card.lastSeenFrame = object.lastSeenFrame
        guard changed else { return }

        card.cardID = printing?.riftboundID
        card.displayName = printing?.name
        card.zoneRaw = zoneRaw
        card.orientationRaw = orientationRaw
        card.zIndex = object.zIndex
        card.underlaidTrackingIDs = underlaid
        card.updatedAt = .now
        try? context.save()
    }

    private func fetchPersisted(trackingID: TrackedObjectID, context: ModelContext) -> PersistentTrackedCard? {
        let descriptor = FetchDescriptor<PersistentTrackedCard>(
            predicate: #Predicate { $0.trackingID == trackingID }
        )
        return try? context.fetch(descriptor).first
    }

    private func deletePersisted(trackingID: TrackedObjectID, context: ModelContext) {
        if let card = persistedCards[trackingID] ?? fetchPersisted(trackingID: trackingID, context: context) {
            context.delete(card)
            try? context.save()
        }
        persistedCards[trackingID] = nil
    }
}
