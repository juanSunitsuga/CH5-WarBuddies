import SwiftUI
import SwiftData
import CoreImage
import AVFoundation
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

/// One-slot, lock-guarded hand-off for the NLP translator's explanation of
/// an event it declined to turn into an action. The translator runs inside
/// `GameEngine.process` off the main actor, while the UI reads on it, so
/// the value can't simply live on `CameraPipelineController`.
final class TranslationNoteBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func set(_ newValue: String?) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    /// Reads and clears in one atomic step, so a note is attached to
    /// exactly one instruction.
    func take() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value = nil
        return current
    }
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

    /// Whether the camera feed is live. Independent of the pipeline: the
    /// feed comes up as soon as the app opens so the playmat overlay can be
    /// calibrated against a real picture. Calibrating blind — pressing
    /// Start first and only then dragging the mat into place — is what put
    /// cards in the wrong zones.
    @Published private(set) var isCameraRunning = false

    /// Whether detection, tracking, and the rules engine are running. This
    /// is what the Start button toggles; the camera is already up by then.
    @Published private(set) var isPipelineRunning = false

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


    /// The tracker's own view of the table — stable IDs and centroids,
    /// as opposed to `detections`, which is a fresh identity-free array
    /// every poll. Drawn on screen so ID churn is visible: the boxes look
    /// identical whether tracking is holding or not.
    @Published private(set) var trackedObjects: [TrackedObject] = []



    /// Cards currently sitting somewhere their kind isn't allowed, with
    /// where to put each one back. Confirmed over several polls, so a
    /// single misread never asks a player to move a card that's already in
    /// the right place.
    @Published private(set) var misplacedCards: [MisplacedCard] = []

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

    /// Floor on the gap between detections — about 5 Hz.
    ///
    /// Chasing the hardware's maximum was a mistake: cards are moved by
    /// hand, so a few samples a second already follow every move, and the
    /// extra polls bought nothing but a tracking log scrolling faster than
    /// it could be read. Detection also runs on the main actor, so each
    /// poll is UI time spent.
    ///
    /// This is a floor, not a target — a machine that can't sustain it
    /// still falls back to whatever it manages, via the measurement below.
    private static let minimumDetectionInterval: TimeInterval = 0.2

    /// Detector cost, averaged over recent polls. Detection runs
    /// synchronously on the main actor, so this is also roughly how long
    /// the UI is blocked per poll — asking for a rate faster than this
    /// can't be honoured and only starves the interface.
    private var averageDetectionDuration: TimeInterval = 0

    /// Measured detections per second, for display.
    @Published private(set) var detectionsPerSecond: Double = 0

    /// The interval actually used: never faster than the detector can
    /// finish, never slower than needed.
    ///
    /// Fixed intervals were guesses — 0.35s was far slower than the machine
    /// could manage, and 0.12s was picked to pair with a region-of-interest
    /// speedup that has since been reverted. Measuring sidesteps the guess
    /// and adapts to whatever Mac this runs on.
    private var detectionPollInterval: TimeInterval {
        guard averageDetectionDuration > 0 else { return Self.minimumDetectionInterval }
        // A little headroom so detection doesn't consume the whole main
        // actor and leave nothing for drawing.
        return max(Self.minimumDetectionInterval, averageDetectionDuration * 1.3)
    }

    /// Exponential moving average — one slow poll (a hiccup, a thermal
    /// blip) shouldn't halve the sample rate for the rest of the session.
    private func recordDetectionDuration(_ duration: TimeInterval) {
        averageDetectionDuration = averageDetectionDuration == 0
            ? duration
            : averageDetectionDuration * 0.8 + duration * 0.2
        detectionsPerSecond = averageDetectionDuration > 0 ? 1 / detectionPollInterval : 0
    }
    private var lastDetectionTimestamp: TimeInterval?

    // MARK: - Persistence

    /// Durable board store. `nil` in previews and the no-arg path, where
    /// persistence simply doesn't run.
    ///
    /// This used to be a whole second consumer here — its own
    /// `ObjectTracker`, frame counter, row cache, trash counters and
    /// upsert logic inline in this type — which meant two independent sets
    /// of `TrackedObjectID`s for the same physical cards. It now runs off
    /// the tracker that already exists, in its own file.
    private let boardPersistence: BoardStatePersistence?

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

    /// The translator's explanation for the event currently being
    /// processed, if it declined to produce an action. Written from
    /// whatever context `GameEngine.process` runs the translator on and
    /// read back on the main actor, so it needs its own synchronization
    /// rather than living directly on this `@MainActor` type — see
    /// `ExpertSystemTranslatorAdapter.onUntranslatable`.
    private let translationNote = TranslationNoteBox()

    /// Which zones each kind of card can physically occupy — a filter on
    /// detector noise, not a rules decision. See `CardPlacementRules`.
    private let placementRules = CardPlacementRules()
    private let underlayResolver = UnderlayResolver()
    private let misplacedMonitor = MisplacedCardMonitor()
    /// Memo for `kind(forLabel:)` — see its doc comment.
    private var cardKindByLabel: [String: CardKind] = [:]
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
        self.boardPersistence = modelContext.map {
            BoardStatePersistence(context: $0, cardDatabase: CardDatabaseLoader.loadBundled())
        }
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

        // Switching devices is a camera concern, not a pipeline one — the
        // feed is normally already up by the time the user picks a camera.
        if isCameraRunning {
            do {
                try camera.switchCamera(to: iPhone.id)
            } catch {
                errorMessage = "Couldn't switch to iPhone camera: \(error)"
            }
        } else {
            Task { await openCamera() }
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
        guard isCameraRunning else { return }
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

    // MARK: - Camera lifecycle

    /// Asks for camera access and brings the feed up. Called when the app
    /// opens, so the playmat can be aligned against a live picture before
    /// anything is detected.
    func openCamera() async {
        guard !isCameraRunning else { return }

        guard await Self.requestCameraAccess() else {
            errorMessage = "Camera access denied. Grant it in System Settings › Privacy & Security › Camera, then reopen the app."
            return
        }

        do {
            try camera.start(deviceID: selectedCameraID)
        } catch {
            errorMessage = "Camera failed to start: \(error)"
            return
        }
        isCameraRunning = true
        errorMessage = nil

        // Frames flow whenever the camera is up. `process(_:)` always
        // refreshes the preview and only runs detection once the pipeline
        // is started, so the feed is usable for calibration on its own.
        //
        // This consumer has to live here, not in `startPipeline()`: nothing
        // reads `camera.frames()` otherwise, so the capture session runs
        // (the OS shows the camera in use) while the window stays black
        // until Start is pressed — which is the whole problem this split
        // was meant to solve.
        runLoop = Task { [weak self] in
            guard let frames = self?.camera.frames() else { return }
            for await frame in frames {
                await self?.process(frame)
            }
        }
    }

    func closeCamera() {
        stopPipeline()
        camera.stop()
        runLoop?.cancel()
        runLoop = nil
        isCameraRunning = false
        backgroundImage = nil
    }

    /// The camera went away mid-session. The pipeline can't run without
    /// frames, so it stops with it rather than sitting on stale state.
    private func cameraLost() {
        stopPipeline()
        isCameraRunning = false
    }

    /// `.notDetermined` is the only case that shows the system prompt;
    /// everything else has already been decided by the user.
    private static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    // MARK: - Pipeline lifecycle

    /// Starts detection, tracking, and the rules engine against the feed
    /// that's already running.
    func startPipeline() {
        guard isCameraRunning, !isPipelineRunning else { return }
        isPipelineRunning = true

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
            },
            // One physical mat, one seat: an event in an unowned zone (the
            // Battlefield) can only be this player's.
            defaultSeat: .player1
        )
        expertSystemAdapter = adapter
        expertSystemFrameIndex = 0
        trackedObjects = []
        misplacedCards = []
        misplacedMonitor.reset()

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
        // Written synchronously from inside `GameEngine.process`, read
        // synchronously by `recordInstruction` right after it returns.
        // Deliberately not a `Task { @MainActor … }` hop: that would race
        // the read and attach the note to the wrong event, or lose it.
        translator.onUntranslatable = { [translationNote] reason in
            translationNote.set(reason)
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
                guard await self.isStageActive(.nlpTranslation) else {
                    // Still log it, otherwise switching stage ③ off looks
                    // identical to the camera seeing nothing at all.
                    await self.recordUnprocessed(event)
                    continue
                }
                let instruction = await engine.process(event)
                await self.recordInstruction(instruction, for: event)
            }
        }

    }

    /// Stops detection and the engine. The camera keeps running, so the
    /// mat stays visible and can be re-calibrated before starting again.
    func stopPipeline() {
        guard isPipelineRunning else { return }
        isPipelineRunning = false
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
        boardPersistence?.reset()
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

    /// The coarse role `UnderlayResolver` needs to decide what can sit
    /// under what: a Unit can have Gear or Runes beneath it, two Units
    /// can't legitimately overlap. Derived from the same memoized category
    /// as the placement rules, so both agree by construction.
    private func stackingRole(of id: TrackedObjectID, in objects: [TrackedObject]) -> CardRole {
        guard let label = objects.first(where: { $0.id == id })?.recognizedLabel else { return .unknown }
        switch kind(forLabel: label) {
        case .unit, .champion: return .unit
        case .gear, .rune: return .attachment
        case .unknown: return .unknown
        case .spell, .legend, .battlefield: return .other
        }
    }

    /// What kind of card a recognizer label names, resolved once per label.
    ///
    /// `CardDatabase.printing(approximatelyNamed:)` normalizes and scans the
    /// whole catalogue, and this sits on the per-detection, per-poll path —
    /// a card's category can't change between polls, so re-deriving it every
    /// time was pure repetition. Cards keep their label for a whole session,
    /// so this settles after the first sighting of each distinct card.
    ///
    /// A label that resolves to nothing is cached as `.unknown`, which
    /// `CardPlacementRules` permits everywhere — an unrecognized card is
    /// still tracked, just not constrained.
    private func kind(forLabel label: String) -> CardKind {
        if let cached = cardKindByLabel[label] { return cached }
        let resolved = cardDatabase.printing(approximatelyNamed: label).map {
            CardKind.from(type: $0.classification.type, supertype: $0.classification.supertype)
        } ?? .unknown
        cardKindByLabel[label] = resolved
        return resolved
    }

    private func recordUnprocessed(_ event: RiftboundExpertSystem.ObservedTableEvent) {
        append(InstructionLogEntry(
            unprocessed: event,
            cardName: cardName(for: event),
            reason: "NLP translation is switched off — event seen but not interpreted."
        ))
    }

    private func append(_ entry: InstructionLogEntry) {
        instructions.insert(entry, at: 0)
        if instructions.count > 30 {
            instructions.removeLast(instructions.count - 30)
        }
    }

    private func recordInstruction(_ instruction: PlayerInstruction, for event: RiftboundExpertSystem.ObservedTableEvent) {
        // Consume (not just read) the note the translator left during this
        // same event's `GameEngine.process` call, so it can't leak onto a
        // later event that had no note of its own.
        let entry = InstructionLogEntry(
            instruction: instruction,
            cardName: cardName(for: event),
            note: translationNote.take(),
            event: event
        )
        append(entry)
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
                    cameraLost()
                }
            } else {
                errorMessage = "Camera disconnected — no camera available."
                cameraLost()
            }

        case .interrupted(let reason):
            errorMessage = "Camera interrupted: \(reason)"

        case .interruptionEnded:
            errorMessage = nil

        case .runtimeError(let message):
            errorMessage = "Camera error: \(message)"
            cameraLost()

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

        // Everything above this line runs whenever the camera is up — the
        // preview picture and the frame sizing the playmat overlay needs.
        // Detection only begins when the user starts the pipeline, so the
        // mat can be calibrated against a live feed first.
        //
        // The stage check is the debug kill switch (see `enabledStages` /
        // `isStageActive`): the video keeps playing either way, only
        // detection and everything downstream of it stops.
        guard isPipelineRunning, isStageActive(.detection) else {
            detections = []
            return
        }

        // Poll cadence, not per-frame — see `detectionPollInterval`'s doc
        // comment. `frame.timestamp` is the sample buffer's presentation
        // time (seconds), monotonic within a capture session.
        if let lastDetectionTimestamp, frame.timestamp - lastDetectionTimestamp < detectionPollInterval {
            return
        }
        lastDetectionTimestamp = frame.timestamp

        // Full-frame scan. Restricting Vision to a `regionOfInterest` was
        // tried as a speedup and reverted: it depends on how Vision
        // normalizes results relative to that region, which this project
        // has no way to verify without the model and a camera, and getting
        // it wrong displaces every detection. That mis-placed cards into
        // the Trash zone, where each one was discarded and re-detected on
        // the next poll, burning tracking IDs into four figures.
        //
        // Correctness over an unmeasured saving. Restore it only alongside
        // a way to confirm the mapping against a known card position.
        let started = CFAbsoluteTimeGetCurrent()
        let raw = (try? detector.detect(in: frame.pixelBuffer)) ?? []
        recordDetectionDuration(CFAbsoluteTimeGetCurrent() - started)
        detections = raw

        // Second consumer of the same detections, same poll cadence — see
        // `expertSystemAdapter`'s doc comment. Gated on stage 2 so turning
        // Object Tracking off in the pipeline settings actually stops it,
        // not just stage 1.
        if isStageActive(.objectTracking), let expertSystemAdapter {
            // Re-point zone resolution at the *current* calibration before
            // every ingest. The overlay always drew from `calibration`
            // live, so a mis-set mapper looked perfectly aligned on screen
            // while silently resolving cards into the wrong zone — or into
            // none at all, which drops the event entirely.
            expertSystemAdapter.updateZones(ZoneMapper(zones: calibration.boardZones()))
            expertSystemFrameIndex += 1
            expertSystemAdapter.ingest(detections: detections, frameIndex: expertSystemFrameIndex, timestamp: frame.timestamp)

            // The vision-layer trace is still produced by the adapter and
            // still drainable — it's the tap to reach for when tracking
            // next needs debugging — but nothing renders it now that the
            // tracking log is gone, so it's drained and dropped rather than
            // accumulating behind a view that no longer exists.
            _ = expertSystemAdapter.drainVisionTrace()
            // Stacking is resolved here, once, before anything consumes
            // the objects. The detector reports the top card of a stack;
            // working out what's underneath is tracking's job, so the
            // z-order and underlay links belong to the objects everything
            // else reads — the overlay, the tracking log, and the durable
            // store alike. Resolving inside persistence meant only the
            // database ever knew about a stack.
            let resolution = underlayResolver.resolve(expertSystemAdapter.trackedObjects) { [self] id in
                stackingRole(of: id, in: expertSystemAdapter.trackedObjects)
            }
            trackedObjects = resolution.objects
            illegalOverlaps = resolution.illegalOverlaps

            // Report placement mistakes rather than hiding them. Filtering
            // an implausible reading out made the card vanish from the app
            // while it sat there on the mat, so the board diverged from the
            // engine with nothing on screen to say why.
            misplacedCards = misplacedMonitor.update(objects: resolution.objects) { [self] label in
                kind(forLabel: label)
            }

            // Durable board state runs off those same resolved objects, so
            // screen and disk agree on identity and z-order both.
            boardPersistence?.sync(
                objects: resolution.objects,
                disappearedIDs: expertSystemAdapter.lastDisappearedIDs,
                zoneMapper: zoneMapper
            )
        }
    }

}
