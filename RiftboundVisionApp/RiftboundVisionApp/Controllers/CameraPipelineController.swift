import SwiftUI
import SwiftData
import CoreImage
import AVFoundation
import RiftboundVision
import RiftboundExpertSystem
import RiftboundTextProcessing

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
    /// What the current phase still needs from the player, recomputed each
    /// poll. Drives the bar during the fixed phases, where there are no
    /// verdicts to show (see `TurnControlBar`).
    @Published private(set) var phaseProgress: PhaseAutoDetector.Progress?

    /// The most recent "here's what this costs" / "put it back" message,
    /// and when it was raised.
    ///
    /// Kept apart from `phaseProgress` because the two have different
    /// lifetimes: `phaseProgress` is recomputed from scratch every poll,
    /// so a payment message written into it would be overwritten by the
    /// next frame's generic "Your move." — the player would see the
    /// warning flash and vanish. This one is event-driven and persists
    /// until it's stale or answered.
    /// What a card's own text says to do, raised the moment the camera sees
    /// the move that triggers it — "Play a 1 Might Recruit unit token here."
    ///
    /// This is the piece that makes a card's printed ability *reach* the
    /// player. The ability list under the instruction is a standing
    /// reminder of everything in play; this is the one thing that just
    /// became true, which is why it gets the headline rather than a bullet.
    @Published private(set) var abilityNotice: PhaseAutoDetector.Progress?
    private var abilityNoticeRaisedAt: Date?

    /// Watches for the zone changes that fire a card's printed text — see
    /// `AbilityTriggerWatcher`, which owns the per-track memory.
    private let abilityTriggers = AbilityTriggerWatcher(seat: .player1)

    @Published private(set) var paymentNotice: PhaseAutoDetector.Progress?
    private var paymentNoticeRaisedAt: Date?

    /// How long a payment message stays up. Long enough to read and act
    /// on, short enough that it can't be mistaken for a statement about a
    /// later card — the same reasoning as `TurnControlBar.verdictLifetime`.
    private static let paymentNoticeLifetime: TimeInterval = 12

    /// Parsed-ability text per printing. The poll re-reads the same cards
    /// several times a second; parsing is pure, so the answer can't change
    /// between frames.
    var abilitySummaryCache: [String: [String]] = [:]

    /// A card on the board that hasn't been paid for yet. While this is
    /// set, the Action Phase is held open: the bar keeps asking for the
    /// outstanding steps and no further play is accepted. Cleared the
    /// moment the table shows every obligation met.
    @Published private(set) var pendingPlay: PendingPlay?

    /// The landing event `pendingPlay` opened — held so it can be
    /// resubmitted to the engine once payment settles. The engine
    /// re-translates this itself (`GameEngine.resolveDeferredPlay`), same
    /// as it would have immediately; this app layer doesn't re-derive the
    /// card or destination from it. `nil` exactly when `pendingPlay` is
    /// `nil`; the two are set and cleared together.
    private var pendingPlayEvent: RiftboundExpertSystem.ObservedTableEvent?

    /// Runes currently in the player's rune area, with their stances — the
    /// input to every affordability question (130.2/130.3).
    private(set) var autoDetectRunes: [ObservedRune] = []

    /// Rune-area occupancy at the moment the Channel Phase began. 515.3.b
    /// asks for 2 *new* runes, and the area only fills up over a game, so
    /// an absolute count would be satisfied permanently after turn one.
    var channelBaseline = 0

    /// Hand size when the Draw Phase began — 515.4.b draws exactly 1, so
    /// only the change matters.
    var handBaseline = 0

    /// Rule 645.7: in 1v1 the player going **second** channels an extra
    /// rune on their first Channel Phase. Defaults to true because that's
    /// the seat this app is set up for — the single local player is the
    /// one taking the second turn.
    var playerGoesSecond = true

    /// How many of this player's own Channel Phases have already run.
    /// Rule 515.3.b needs "is this their first turn", which no global round
    /// counter answers — `ManualGameState.round` counts cycles of turn
    /// order, not this player's turns.
    var completedChannelPhases = 0

    /// Rule 515.3.b/645.7: 3 on the second player's opening turn, 2 every
    /// turn after that.
    ///
    /// Delegated to the engine's `RuneChannelPace` rather than restating
    /// the arithmetic here — it is the same rule the Expert System's own
    /// Channel Step uses, and two copies of "3 then 2" is exactly the pair
    /// that drifts. The turn order is synthesized because this app has one
    /// seat and `GameState.turnOrder` therefore has one entry, which can't
    /// express "there is another player and they went first"; 645.7 keys
    /// off going *last*, so the local player is placed accordingly.
    var runesToChannelThisTurn: Int {
        let opponent = PlayerID()
        return RuneChannelPace.runesToChannel(
            for: localPlayerID,
            turnOrder: playerGoesSecond ? [opponent, localPlayerID] : [localPlayerID, opponent],
            completedTurns: completedChannelPhases
        )
    }

    /// Phase as of the previous poll, so entering a phase can be
    /// distinguished from sitting in it — the baseline and the hold points
    /// are both once-per-phase, not per-frame.
    var lastSeenPhase: GamePhase?

    /// Consecutive polls the current phase has reported itself finished.
    ///
    /// Auto-detect used to advance on the first poll that said "complete",
    /// which made it hostage to a single frame of detection noise. A hand
    /// fanned over the mat miscounts by one and the Draw Phase completes
    /// before the card is drawn; a card flickers out of view and Awaken
    /// decides nothing is exhausted. Requiring agreement across a few
    /// polls costs about half a second and removes the whole class.
    private var completedPollStreak = 0
    /// Polls a phase must agree it's finished before the turn moves on.
    private static let phaseAdvanceConfirmations = 3

    /// The score is the player's to move, and only theirs.
    ///
    /// The Beginning Phase used to add hold points here by itself (630.2).
    /// It stopped because this app reads a camera: it can misread who holds
    /// a battlefield, and a score that moves on its own is one the player
    /// has to re-audit before they can trust any of it — which costs more
    /// than typing the number. `PhaseAutoDetector` still counts the holds
    /// and says "add 2 points"; pressing + stays a person's decision.
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
    ///
    /// Deliberately **not** `@Published`. This type is an
    /// `ObservableObject`, whose change signal carries no information about
    /// *which* property changed — so every mutation invalidates every view
    /// observing it, which here is `ContentView` (the camera stage and all
    /// three overlays) and `DetectedCardsPanel` (whose rows each fetch
    /// full-size card art). Publishing this meant a full re-render of the
    /// camera and the sidebar on every table event, to keep a diagnostic
    /// count up to date and nothing else. The count still tracks live in
    /// practice: the settings popover is re-rendered by the genuinely
    /// published per-poll properties (`detections`, `trackedObjects`)
    /// anyway, and re-reads this when it does.
    private(set) var observedEvents: [RiftboundExpertSystem.ObservedTableEvent] = []


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

    /// True when most tracked cards are falling outside every calibrated
    /// zone.
    ///
    /// This is the silent failure that looks like a broken app: an
    /// uncalibrated mat puts every card in `.unknown`, the adapter has no
    /// region to forward, and the pipeline produces nothing at all — while
    /// the screen happily shows cards being detected. Without saying so,
    /// the only symptom is that nothing ever happens.
    @Published private(set) var needsCalibration = false

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

    /// `RiftboundTextProcessing`'s SQLite catalogue — a second source for
    /// the same cards, joined to `cardDatabase`'s by `CardPrinting.id`
    /// (this database's `card_id`, both the catalogue's own hex id — see
    /// `printedText(for:)`'s doc comment). Consulted for rules text
    /// specifically because its `plain_text` column has already had the
    /// bundled JSON's icon shortcodes (`:rb_might:`, `:rb_rune_rainbow:`)
    /// resolved to words; `cardDatabase`'s `text.plain` still has them raw.
    let textDatabase = CardDatabaseService()

    /// Rules text for `printing`, cascading through three sources from
    /// most to least reader-friendly: `textDatabase`'s `simple_text` (a
    /// first-timer-friendly one-sentence rewrite, keyed by id or name —
    /// see `CardDatabaseService.simplifiedText(for:name:)`'s doc comment
    /// for why both are passed), then its tag-resolved `plain_text`, then
    /// `printing.text.plain`'s raw copy (which still has the bundled
    /// JSON's icon shortcodes like `:rb_might:` unresolved). Each step
    /// only exists for what the step before it doesn't carry — the
    /// synthetic Token entry, or a printing outside either catalogue's
    /// coverage, still shows *something* rather than nothing.
    func description(for printing: CardPrinting) -> String {
        textDatabase.simplifiedText(for: printing.id, name: printing.name)
            ?? textDatabase.printedText(for: printing.id)
            ?? printing.text.plain
    }

    /// BonBon's hand-curated comment for `printing` (`textDatabase`'s
    /// `bonbons_comment_changes` column), if the "Card Description +
    /// Comment Fix" pass has reached this card yet. `nil` when it hasn't —
    /// the caller falls back to `CardPlainLanguage.describeCard`'s
    /// algorithmic rewrite of the raw printed text for everything the
    /// curated pass hasn't covered.
    func bonbonComment(for printing: CardPrinting) -> String? {
        textDatabase.bonbonComment(for: printing.id, name: printing.name)
    }

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
    private let loadedDetector = CardDetectionModelLoader.loadDetector()
    private var detector: any ObjectDetecting { loadedDetector.detector }

    /// Set when the trained Core ML model couldn't be loaded and the app
    /// is running on the geometric fallback detector, which finds cards
    /// but can't say which card each one is.
    ///
    /// Separate from `errorMessage` on purpose: that one is for transient
    /// camera conditions and gets cleared when they resolve (a reconnect,
    /// an interruption ending). This is a condition fixed for the whole
    /// session — the model either loaded at launch or it didn't — so it
    /// must not be cleared by an unrelated camera event. Surfacing it at
    /// all is the point: the fallback used to be a `print` nobody reads,
    /// so a mis-filed model looked exactly like a working app that had
    /// stopped recognizing anything.
    var detectorFallbackWarning: String? { loadedDetector.fallbackReason }
    private let ciContext = CIContext()

    /// Preview refresh ceiling. The picture cannot usefully update faster
    /// than the display refreshes, and every conversion above that rate is
    /// work thrown away.
    private static let previewFrameInterval: TimeInterval = 1.0 / 30.0
    private var lastPreviewTimestamp: TimeInterval?
    /// Guards against queueing conversions behind a slow one — with a
    /// 60fps camera and a conversion that takes longer than a frame, every
    /// frame would otherwise start another and they'd pile up.
    private var isConvertingPreview = false

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

    private let underlayResolver = UnderlayResolver()
    private let misplacedMonitor = MisplacedCardMonitor()
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
    /// The earliest stage that is switched off while the pipeline runs, as
    /// a sentence — or `nil` when the whole chain is live.
    ///
    /// Exists so the instruction band can say "the Expert System is off"
    /// instead of going blank. A blank band and a broken app look identical
    /// from the player's chair; naming the switch they flipped is the
    /// difference between a setting and a bug.
    var inactivePipelineNotice: String? {
        guard isPipelineRunning else { return nil }
        guard let firstOff = PipelineStage.allCases.first(where: { !isStageActive($0) }) else { return nil }
        return firstOff.title
    }

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

    /// Brings the feed up, optionally asking for access first.
    ///
    /// `promptingForAccess: false` means "open it if we're already allowed,
    /// otherwise do nothing, quietly." That's what launch uses, and the
    /// reason is the system permission dialog: asked at launch it lands
    /// before the player has been told what the camera is *for*, on top of
    /// an app they haven't seen yet, which is the moment someone is most
    /// likely to decline — and on macOS a declined camera can only be
    /// undone in System Settings.
    ///
    /// So the ask is deferred to the tour step where BonBon explains he
    /// needs to see the table (see `ContentView`), which is the first
    /// moment the dialog has a reason attached to it. Anyone who already
    /// granted it still gets a live picture immediately at launch, because
    /// `.authorized` never shows a dialog.
    func openCamera(promptingForAccess: Bool = true) async {
        guard !isCameraRunning else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            // The only state that actually shows the dialog — so it's the
            // only one that has to wait for a good moment to show it.
            guard promptingForAccess else { return }
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                errorMessage = "Camera access denied. Grant it in System Settings › Privacy & Security › Camera, then reopen the app."
                return
            }
        default:
            // Already declined, or restricted by policy. Nothing to ask —
            // and saying so at launch, unprompted, is just noise, so this
            // only speaks up when the player asked for the camera.
            if promptingForAccess {
                errorMessage = "Camera access denied. Grant it in System Settings › Privacy & Security › Camera, then reopen the app."
            }
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
            // Through the shared resolver, so the engine and the screen
            // agree about what is on the table. These were two lookups with
            // different rules: the UI applied deck scope and this didn't, so
            // an out-of-deck card vanished from the strip while the engine
            // went on proposing plays for it.
            //
            // Battlefield-scoped, because that is where an opponent's cards
            // legitimately arrive and the engine has to name them to track
            // combat — the same exception `DeckScope` already makes.
            resolveLabel: { [resolver = identityResolver] label in
                resolver.printing(forLabel: label, in: .battlefield)
                    .map { CardDefID(rawValue: $0.riftboundID) }
            },
            // One physical mat, one seat: an event in an unowned zone (the
            // Battlefield) can only be this player's.
            defaultSeat: .player1
        )
        expertSystemAdapter = adapter
        expertSystemFrameIndex = 0
        trackedObjects = []
        misplacedCards = []
        needsCalibration = false
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
                printedText: printing?.text.plain,
                domains: printing?.classification.domain.compactMap(GameSessionBuilder.domain(named:)) ?? []
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
        // This `Task` inherits the main actor from its enclosing context,
        // so the bookkeeping calls below run without suspending — only
        // `engine.process` actually crosses into another actor, and it's
        // the sole `await` here for exactly that reason.
        expertSystemEventLoop = Task {
            for await event in adapter.events() {
                self.recordObservedEvent(event)
                let deferredToSettlement = self.checkAffordability(of: event)
                guard self.isStageActive(.nlpTranslation) else {
                    // Still log it, otherwise switching stage ③ off looks
                    // identical to the camera seeing nothing at all.
                    self.recordUnprocessed(event)
                    continue
                }
                // This landing just opened a `pendingPlay` — its real
                // submission (with the physically observed Rune count)
                // happens later, from `updateAutoDetect`, once payment
                // settles. Asking the translator to accept it now, with no
                // observation to check, would register the Play (and
                // deduct its cost) before the player has paid anything.
                guard !deferredToSettlement else { continue }
                let instruction = await engine.process(event)
                self.recordInstruction(instruction, for: event)
                // Read straight back, on the same hop that just mutated it.
                // Refreshing anywhere else would let the screen show a state
                // the engine had already moved past.
                self.engineState = await session.store.currentState
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

    /// Runs the detector on a background executor and hands the results
    /// back on the main actor.
    ///
    /// `CVPixelBuffer` and the detector are both reference-like values that
    /// Swift can't prove `Sendable`, so this crossing is asserted rather
    /// than checked. It's sound in practice for the reason the tracker's
    /// own contract states: one caller, one frame at a time, in order —
    /// `process(_:)` awaits this before starting the next poll, so no two
    /// detections are ever in flight over the same buffer.
    private func detect(in pixelBuffer: CVPixelBuffer) async -> [Detection] {
        let box = UncheckedBox(value: (detector, pixelBuffer))
        return await Task.detached(priority: .userInitiated) {
            let (detector, buffer) = box.value
            return (try? detector.detect(in: buffer)) ?? []
        }.value
    }

    /// Converts a camera frame to a `CGImage` off the main actor.
    ///
    /// Same asserted crossing as `detect(in:)`, and sound for the same
    /// reason: one caller, one frame at a time — `isConvertingPreview`
    /// guarantees no second conversion starts while this one is in flight.
    private func makePreviewImage(from ciImage: CIImage) async -> CGImage? {
        let box = UncheckedBox(value: (ciContext, ciImage))
        return await Task.detached(priority: .userInitiated) {
            let (context, image) = box.value
            return context.createCGImage(image, from: image.extent)
        }.value
    }

    /// Distinct printings behind the currently-*tracked* cards, oldest track
    /// first.
    ///
    /// Deduped because several boxes can resolve to the same printing (two
    /// copies of the same rune) and a list should name a card once. Lives
    /// here rather than in a view because two now need it — the card strip
    /// and the sidebar — and two copies of "what's on the table" could
    /// disagree about what the player is looking at.
    ///
    /// Reads `trackedObjects`, not `detections`, on purpose. `detections` is
    /// the raw, per-poll detector output — no identity, no occlusion
    /// tolerance, and (by design, for the live on-camera overlay) not run
    /// through `ObjectTracker`'s label-vote stabilization at all. Building
    /// this list from it meant every card flickered in and out, and renamed
    /// itself, at the raw detector's own noise level — several times a
    /// second, even for a card lying dead still — because that's exactly
    /// what `detections` is supposed to expose for the overlay.
    /// `trackedObjects` is the stabilized output of the same poll: a card
    /// keeps its place through brief occlusion (a hand passing over it) and
    /// its name only changes when the evidence for a different card is
    /// actually decisive, not on every ambiguous frame.
    ///
    /// Sorted by `TrackedObjectID` rather than relying on the underlying
    /// storage's order, which isn't guaranteed stable across mutations — IDs
    /// are assigned in increasing order as cards first appear, so this
    /// reproduces "in detection order" deterministically instead of by
    /// accident.
    /// Which deck is on the table, and the narrowing that follows from it.
    ///
    /// Empty rosters until the database loads; nothing is narrowed until a
    /// Legend has actually been seen.
    /// Turns a detector label into a card, deck scope and all. One
    /// instance, shared by every consumer — see `CardIdentityResolver`.
    private lazy var identityResolver = CardIdentityResolver(database: cardDatabase)

    /// Bumped whenever the resolver adopts a deck, so SwiftUI redraws.
    ///
    /// The resolver is a reference type and deliberately *not* `@Published`
    /// itself: publishing a class doesn't observe its mutations, and
    /// keeping a second copy of the scope here would be exactly the
    /// duplicate source of truth this extraction removes.
    @Published private(set) var deckIdentityRevision = 0

    /// The deck the Legend on the table belongs to, once known.
    var activeDeckName: String? {
        _ = deckIdentityRevision
        return identityResolver.activeDeckName
    }

    /// The engine's own view of the game, refreshed after every event it
    /// processes.
    ///
    /// The app used to write to `GameState` and never read it back, which
    /// made the engine a ledger nobody consulted: it recorded what happened
    /// but nothing on screen was derived from it, so the two could disagree
    /// indefinitely with no way to notice. Publishing the snapshot is what
    /// closes that loop — anything the engine knows can now be shown, and a
    /// disagreement between the board and the engine becomes visible
    /// instead of silent.
    ///
    /// `nil` until the first event is processed.
    @Published private(set) var engineState: GameState?

    /// Energy currently in the local player's pool, as the *engine* has it —
    /// the number a play is actually validated against (130.2).
    var engineEnergy: Int? { engineState?.zones[localPlayerID]?.runePool.energy }

    /// Runes the engine believes are on the board, and how many are still
    /// upright and therefore still able to pay for something (157.2.a).
    var engineRuneCount: Int? {
        engineState.map { state in state.runes.values.filter { $0.controller == localPlayerID }.count }
    }
    var engineReadyRuneCount: Int? {
        engineState.map { state in
            state.runes.values.filter { $0.controller == localPlayerID && !$0.isExhausted }.count
        }
    }

    /// Standing damage bonuses granted by cards currently on the table.
    ///
    /// Read from the board rather than from the deck, because that is where
    /// they come from: Annie - Fiery is a Unit you play and Void Gate is a
    /// Battlefield in the match, so both arrive and leave mid-game. Only
    /// the zones where a card's text is live count — a card in hand or a
    /// deck grants nothing (137–145).
    var activeDamageBonuses: [ActiveDamageBonus] {
        var found: [ActiveDamageBonus] = []
        var seenSources = Set<String>()

        for object in trackedObjects.sorted(by: { $0.id < $1.id }) {
            let zone = zoneMapper.boardZone(for: object.center)?.type ?? object.currentZone
            guard Self.abilityLiveZones.contains(zone),
                  let printing = scopedPrinting(for: object),
                  let bonus = CardAbilityParser.damageBonus(in: printing.text.plain),
                  // Two copies of the same card would each grant their own
                  // bonus in the rules; this list is advice, and naming the
                  // same card twice reads as a bug rather than as a stack.
                  seenSources.insert(printing.name).inserted
            else { continue }
            found.append(ActiveDamageBonus(source: printing.name, bonus: bonus))
        }
        return found
    }

    /// Where a card's printed text is live — its Base, a Battlefield, the
    /// Legend and Champion slots.
    private static let abilityLiveZones: Set<Zone> = [.base, .battlefield, .legend, .champion]

    /// A tracked object's card, subject to deck scope.
    ///
    /// The single place a label becomes a card, so the narrowing can't be
    /// bypassed by a call site that forgot about it. A label the scope
    /// rejects returns `nil` — the object stays tracked and drawn, it just
    /// isn't claimed to be a specific card, which is the honest reading of
    /// "that name can't be right".
    func scopedPrinting(for object: TrackedObject) -> CardPrinting? {
        identityResolver.printing(forLabel: object.recognizedLabel, in: zone(of: object))
    }

    /// A track's zone, preferring the calibrated mapping over the tracker's
    /// own last answer.
    private func zone(of object: TrackedObject) -> Zone {
        zoneMapper.boardZone(for: object.center)?.type ?? object.currentZone
    }

    /// Adopts the deck as soon as a Legend is identified on the table.
    ///
    /// Rule 166 puts exactly one Legend out during setup and it stays for
    /// the game, so this fires once. Waits for `isIdentityCommitted`: the
    /// deck is chosen off a single label, and choosing it from a reading
    /// that is still wobbling would narrow everything else to the wrong
    /// deck — the most expensive mistake available here.
    func adoptDeckIfLegendSeen(in objects: [TrackedObject]) {
        if identityResolver.adoptDeckIfLegendSeen(in: objects) {
            deckIdentityRevision += 1
        }
    }

    var cardsOnTable: [CardPrinting] {
        var seen = Set<String>()
        var result: [CardPrinting] = []
        for object in trackedObjects.sorted(by: { $0.id < $1.id }) {
            guard let printing = scopedPrinting(for: object),
                  seen.insert(printing.id).inserted else { continue }
            result.append(printing)
        }
        return result
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
        identityResolver.kind(forLabel: label)
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

        // The preview conversion, off the main actor and rate-limited.
        //
        // This used to run inline, on every camera frame, on this
        // `@MainActor` type. `createCGImage` is a synchronous
        // full-resolution GPU→CPU copy, so at 60fps the main thread spent
        // most of its time converting frames it was about to throw away —
        // which is what made the feed feel laggy no matter how cheap
        // detection got. The comment here used to claim only the detector
        // was expensive; the conversion was the larger cost of the two.
        //
        // Capped at `previewFrameInterval` because the display cannot show
        // more than it refreshes, and skipped entirely while a conversion
        // is still in flight so a slow frame can't queue up behind itself.
        frameSize = size
        if !isConvertingPreview,
           frame.timestamp - (lastPreviewTimestamp ?? -.infinity) >= Self.previewFrameInterval {
            lastPreviewTimestamp = frame.timestamp
            isConvertingPreview = true
            let image = await makePreviewImage(from: ciImage)
            isConvertingPreview = false
            if let image { backgroundImage = image }
        }

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
        // Inference runs off the main actor. This whole type is
        // `@MainActor`, so a synchronous `detect` here blocked the UI for
        // the duration of every poll — at a ~5 Hz cadence and ~100ms per
        // pass that's half the main thread spent inside Core ML, which
        // shows up as a stuttering preview and sluggish controls even
        // though the pipeline itself is keeping up.
        let started = CFAbsoluteTimeGetCurrent()
        let raw = await detect(in: frame.pixelBuffer)
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

            // Needs a couple of cards before it means anything — one card
            // held off-mat while being read is normal, half the table
            // sitting outside every zone is a calibration that doesn't
            // match the camera.
            let cards = resolution.objects.filter { $0.type == .card }
            let offMat = cards.filter { $0.currentZone == .unknown }
            needsCalibration = cards.count >= 2 && offMat.count * 2 >= cards.count

            // Auto-detect reads the same resolved objects as everything
            // else — a second view of the table would be the duplicate
            // source of truth CLAUDE.md warns about, and could disagree
            // with the overlay the player is looking at.
            updateAutoDetect(with: resolution.objects)

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

// MARK: - Auto-detect (rule 515)

extension CameraPipelineController {

    /// Turns the resolved tracks into the phase detector's vocabulary and,
    /// when Auto-detect is on, advances the turn as each fixed phase is
    /// satisfied.
    ///
    /// Only the four Start of Turn phases advance themselves. 516.2 gives
    /// the Action Phase no completion condition — it ends when the player
    /// says so (516.6) — so Auto-detect narrates it and nothing more.
    func updateAutoDetect(with objects: [TrackedObject]) {
        // Everything below this line is the Expert System stage: reading
        // the table against the rules and saying what the turn needs next.
        // It used to run whenever Object Tracking was on, which is why
        // switching stages ③ and ④ off changed nothing a player could see —
        // the overlays went quiet but the instruction band carried on
        // narrating the turn, off a stage that was supposedly disabled.
        // Now the band goes quiet too, and says why.
        guard isStageActive(.expertSystem) else {
            phaseProgress = nil
            abilityNotice = nil
            abilityNoticeRaisedAt = nil
            abilityTriggers.reset()
            return
        }

        adoptDeckIfLegendSeen(in: objects)
        let observed = objects.compactMap { observedCard(from: $0) }
        noteAbilityTriggers(in: objects)
        autoDetectRunes = observed.compactMap { card in
            guard card.zone == .runeArea, let domain = card.domain else { return nil }
            return ObservedRune(domain: domain, stance: card.stance)
        }

        // The baseline has to be taken as the phase *begins*, or "2 new
        // runes" is measured against whatever happened to be there when
        // the first frame after the change arrived.
        if gameState.phase != lastSeenPhase {
            lastSeenPhase = gameState.phase
            if gameState.phase == .channel {
                channelBaseline = observed.filter { $0.zone == .runeArea }.count
            }
            if gameState.phase == .draw {
                handBaseline = observed.filter { $0.zone.isHand(for: .player1) }.count
                // Leaving Channel for Draw is the Channel Phase completing.
                // Counted on the way out rather than the way in, so the
                // phase itself still sees `completedChannelPhases == 0` and
                // asks for the opening three.
                completedChannelPhases += 1
            }
            completedPollStreak = 0
            // A play left unsettled when the phase changed isn't chased
            // into the next one. Ending the turn is the player asserting
            // they're done, and holding last turn's obligation over them
            // would make the app impossible to get out of. Its Play was
            // never submitted (that only happens on settlement), so
            // abandoning it here is correct, not lossy — the card simply
            // never became official, same as it never having paid.
            pendingPlay = nil
            pendingPlayEvent = nil
        }

        let detector = PhaseAutoDetector(
            channelBaseline: channelBaseline,
            runesToChannel: runesToChannelThisTurn,
            handBaseline: handBaseline
        )
        // A payment message outranks the generic phase text while it's
        // live — it's about a specific card the player is holding over the
        // board right now.
        if let raisedAt = paymentNoticeRaisedAt,
           Date().timeIntervalSince(raisedAt) > Self.paymentNoticeLifetime {
            paymentNotice = nil
            paymentNoticeRaisedAt = nil
        }
        // Same clock, same reasoning: a triggered ability is about a move
        // that just happened, and stale feedback claims the app is keeping
        // up when it isn't.
        if let raisedAt = abilityNoticeRaisedAt,
           Date().timeIntervalSince(raisedAt) > Self.paymentNoticeLifetime {
            abilityNotice = nil
            abilityNoticeRaisedAt = nil
        }

        let progress = detector.progress(for: gameState.phase, cards: observed, seat: .player1)

        // An unsettled play outranks everything: until it's paid for, what
        // the phase wants next is irrelevant.
        if let play = pendingPlay {
            let observation = observation(of: play, in: observed)
            var settlement = detector.settlement(of: play, observing: observation)
            settlement.steps = detector.abilitySteps(cards: observed, seat: .player1)

            if settlement.isComplete {
                // Paid — this is the first moment `observedExhaustedRuneCount`
                // is actually known, so this is where the Play the landing
                // event opened finally reaches the engine, not before. The
                // engine re-translates `event` itself (same NLP layer
                // `process(_:)` uses), so this app layer doesn't re-derive
                // the card or destination — only the observed count is new.
                if let event = pendingPlayEvent, let engine = gameEngine {
                    let observedExhaustedRuneCount = play.energyPaid(observation)
                    Task { [weak self] in
                        guard let self else { return }
                        let instruction = await engine.resolveDeferredPlay(
                            for: event,
                            observedExhaustedRuneCount: observedExhaustedRuneCount,
                            proposedBy: self.localPlayerID
                        )
                        self.recordInstruction(instruction, for: event)
                    }
                }
                // Drop the hold and let the next poll speak normally.
                pendingPlay = nil
                pendingPlayEvent = nil
                paymentNotice = nil
                paymentNoticeRaisedAt = nil
            }
            phaseProgress = settlement
            return
        }

        // A payment notice replaces the *headline*, not the board. The
        // ability list is a standing property of what's in play, so it
        // carries across rather than blinking out for the twelve seconds a
        // cost message is up.
        if var notice = paymentNotice {
            notice.steps = progress.steps
            phaseProgress = notice
        } else if var triggered = abilityNotice {
            // Below payment, above the phase. A cost the player still owes
            // is the thing blocking the game; a triggered ability is the
            // thing that just happened and has to be resolved next.
            triggered.steps = progress.steps
            phaseProgress = triggered
        } else {
            phaseProgress = progress
        }

        guard isAutoDetectingPhase else { return }

        guard progress.isComplete else {
            completedPollStreak = 0
            return
        }
        completedPollStreak += 1
        guard completedPollStreak >= Self.phaseAdvanceConfirmations else { return }
        completedPollStreak = 0
        gameState.advance()
    }

    /// Resolves one track into what the detector needs: where it is, which
    /// way up, and — if the card database knows it — what it costs.
    ///
    /// Returns `nil` for a track that isn't on the mat at all. A card in
    /// transit between zones isn't in the wrong place, it's between places,
    /// and counting it would make Awaken flicker in and out of completion
    /// as the player's hand crosses the mat.
    private func observedCard(from object: TrackedObject) -> ObservedCard? {
        let boardZone = zoneMapper.boardZone(for: object.center)
        let zone = boardZone?.type ?? object.currentZone
        guard zone != .unknown else { return nil }

        let printing = scopedPrinting(for: object)
        let domains = (printing?.classification.domain ?? []).compactMap(Domain.init(caseInsensitive:))

        return ObservedCard(
            id: object.id,
            name: printing?.name ?? object.recognizedLabel ?? "Card #\(object.id)",
            zone: zone,
            battlefieldSlot: boardZone?.battlefieldSlot,
            owner: boardZone?.owner,
            stance: object.stance(knowing: printing),
            kind: object.recognizedLabel.map { kind(forLabel: $0) } ?? .unknown,
            domain: domains.first,
            energyCost: printing?.attributes.energy ?? 0,
            powerCost: printing?.attributes.power ?? 0,
            eligibleDomains: domains,
            entersReady: printing.map(Self.entersReady(_:)) ?? false,
            abilities: printing.map { abilitySummaries(for: $0) } ?? []
        )
    }

    /// Rule 139.4 vs 717: Units enter exhausted unless something says
    /// otherwise. Accelerate is the keyword; some cards say it in words, so
    /// both are checked. Read off the printed text rather than assumed,
    /// because getting this wrong tells the player to turn a card sideways
    /// that should stay upright — and they'll believe the app.
    static func entersReady(_ printing: CardPrinting) -> Bool {
        let text = printing.text.plain.lowercased()
        return text.contains("[accelerate]")
            || text.contains("accelerate")
            || text.contains("enters play ready")
            || text.contains("enters ready")
    }

    /// The card's abilities, already translated to Game Actions by the NLP
    /// layer (`CardAbilityParser`). Memoized per printing: the poll runs
    /// several times a second over the same handful of cards, and parsing
    /// the same text each time would be pure waste.
    func abilitySummaries(for printing: CardPrinting) -> [String] {
        if let cached = abilitySummaryCache[printing.riftboundID] { return cached }
        // `CardAbilityParser.read` names Game Actions, which is the
        // engine's vocabulary; these lines are read by a player mid-game,
        // so they get the plain rendering instead. Falls back to the parsed
        // summaries when a card's text has no plain form — better a terse
        // line than a blank one.
        let explanation = CardPlainLanguage.explain(printing.text.plain)
        let summaries = explanation.lines.isEmpty
            ? CardAbilityParser.read(printing.text.plain).abilities.map(\.summary)
            : explanation.lines
        abilitySummaryCache[printing.riftboundID] = summaries
        return summaries
    }

    /// Fires a card's "when I move to a battlefield" text the moment the
    /// camera sees that move.
    ///
    /// Only the triggers a camera can actually witness — a zone change —
    /// are ever fired. `AbilityTrigger.unobservable` covers attacking,
    /// conquering and defending, which this app has no way to see; those
    /// stay in the standing ability list where the player can read them,
    /// rather than being guessed at from a card twitching on the mat.
    private func noteAbilityTriggers(in objects: [TrackedObject]) {
        let fired = abilityTriggers.fired(
            in: objects,
            card: { [weak self] object in
                guard let printing = self?.scopedPrinting(for: object) else { return nil }
                return (name: printing.name, text: printing.text.plain)
            },
            triggers: { [weak self] text in
                CardAbilityParser.triggers(in: text).map { ability in
                    (
                        fires: { previous, zone in
                            switch ability.trigger {
                            case .movedToBattlefield: return zone == .battlefield
                            case .moved: return true
                            case .played: return self?.abilityTriggers.isPlayFromHand(from: previous, to: zone) ?? false
                            case .unobservable: return false
                            }
                        },
                        effect: ability.effect
                    )
                }
            }
        )

        guard let first = fired.first else { return }
        abilityNotice = PhaseAutoDetector.Progress(
            headline: "\(first.cardName): \(CardPlainLanguage.simplify(first.effects[0]))",
            detail: first.effects.count > 1
                ? first.effects.dropFirst().joined(separator: " ")
                : "Its text triggered when you moved it. Resolve it before you carry on."
        )
        abilityNoticeRaisedAt = Date()
    }

    /// Rule 130.2/130.3: a card leaving the hand for the board has to be
    /// paid for, and the runes to pay with are sitting on the table where
    /// the camera can count them.
    ///
    /// This is the check the player actually needs during the Action
    /// Phase, and it's deliberately *not* the engine's `.insufficientEnergy`
    /// — that one reads `RunePool`, which this app still seeds (see
    /// `GameSessionBuilder`), so it can never say no. This reads the rune
    /// area itself: how many runes are still upright to exhaust for
    /// energy, and how many of an accepted domain could be recycled for
    /// power.
    ///
    /// Only during the Action Phase (516.1). A card moving out of the hand
    /// during Awaken or Channel is the player tidying up, not paying for
    /// anything.
    ///
    /// Returns whether this event's Play should be held back from
    /// `engine.process(_:)` — true exactly when it just opened a
    /// `pendingPlay`, whose real submission (with the physically observed
    /// Rune count) happens later, once `updateAutoDetect` sees it settle.
    /// Every other outcome here (nothing owed, unaffordable, wrong phase,
    /// not a play at all) is unchanged from before and should still reach
    /// the engine immediately.
    @discardableResult
    func checkAffordability(of event: RiftboundExpertSystem.ObservedTableEvent) -> Bool {
        guard gameState.phase.validatesPlayerMoves else { return false }

        // A play arrives as either shape, and assuming only the first is
        // why this never fired. Picking a card up ends its track and
        // putting it down starts a new one — `ExpertSystemAdapter`'s own
        // doc comment says so — so the common signature for playing a card
        // is `.cardAppeared` at the destination, *not* a `.cardMoved` that
        // remembers the hand. Requiring the move meant the app watched for
        // an event that mostly doesn't happen.
        let destinationRegion: TableRegion
        switch event.kind {
        case .cardMoved(let from, let to):
            guard from.isHandRegion else { return false }
            destinationRegion = to
        case .cardAppeared(let region):
            // A card appearing in hand is the camera catching up, not a
            // play (and it's where cards come *from*).
            guard !region.isHandRegion else { return false }
            destinationRegion = region
        case .cardRemoved, .cardOrientationChanged:
            return false
        }

        // Rule 106: only a Location is somewhere a card gets played *to*.
        // Hand → trash is a discard, not a play, and costs nothing.
        guard destinationRegion.location != nil else { return false }
        guard let definitionID = event.card?.cardDefinitionID,
              let printing = cardDatabase.printing(riftboundID: definitionID.rawValue) else { return false }

        let domains = printing.classification.domain.compactMap(Domain.init(caseInsensitive:))
        let card = ObservedCard(
            id: 0,
            name: printing.name,
            zone: .base,
            kind: CardKind.from(
                type: printing.classification.type,
                supertype: printing.classification.supertype
            ),
            energyCost: printing.attributes.energy ?? 0,
            powerCost: printing.attributes.power ?? 0,
            eligibleDomains: domains,
            entersReady: Self.entersReady(printing),
            // The card's own text, translated to Game Actions by the NLP
            // layer — what the player has to resolve now that it's down.
            abilities: abilitySummaries(for: printing)
        )

        // One play at a time. A second card landing while the first is
        // still unpaid is the player getting ahead of themselves, and
        // accepting it would bury the obligation they already owe. That
        // second card still isn't tracked here, so it reaches the engine
        // immediately (unaffected by this function) — same as before.
        guard pendingPlay == nil else { return false }

        let progress = PhaseAutoDetector().paymentProgress(for: card, runes: autoDetectRunes)
        // Only speak up when there's something to say — a free card played
        // with a full rune area doesn't need narrating over the verdict the
        // engine is about to give.
        // A free Unit still needs saying: 139.4 makes it enter exhausted,
        // and that's a physical step the player owes regardless of cost.
        let owesSomething = progress.needsCorrection
            || card.energyCost > 0
            || card.powerCost > 0
            || card.kind == .unit || card.kind == .champion
            || card.kind == .spell
            || !card.abilities.isEmpty
        guard owesSomething else { return false }
        paymentNotice = progress
        paymentNoticeRaisedAt = Date()
        phaseProgress = progress

        // Affordable and something is owed → hold the phase open until the
        // table shows it paid. Unaffordable plays don't open a pending
        // play: the answer there is "put it back", not "now pay for it" —
        // and the engine's own abstract-pool check rejects it immediately,
        // same as before this function deferred anything.
        guard !progress.needsCorrection else { return false }
        let mustExhaustCard = (card.kind == .unit || card.kind == .champion) && !card.entersReady
        // 150/556.2: a Spell has no board form — it resolves and goes to
        // the Trash. It's laid in the Base while being paid for, which is
        // how it's played at a table, so the play isn't finished until the
        // card is swept away.
        let mustGoToTrash = card.kind == .spell
        guard mustExhaustCard || mustGoToTrash || card.energyCost > 0 || card.powerCost > 0 else { return false }

        pendingPlayEvent = event
        pendingPlay = PendingPlay(
            name: card.name,
            mustExhaustCard: mustExhaustCard,
            mustGoToTrash: mustGoToTrash,
            energyCost: card.energyCost,
            powerCost: card.powerCost,
            eligibleDomains: card.eligibleDomains,
            exhaustedRunesAtPlay: autoDetectRunes.filter { !$0.isReady }.count,
            runesInAreaAtPlay: autoDetectRunes.count
        )
        return true
    }

    /// What the table currently says about an unsettled play.
    ///
    /// The card is found by name among the player's board zones, because
    /// the played card arrives as a *new* track — picking it up ended the
    /// old one — and the event that opened this play carried a `CardDefID`,
    /// not a `TrackedObjectID`.
    private func observation(of play: PendingPlay, in cards: [ObservedCard]) -> PendingPlay.Observation {
        // Searched across the whole table, not just the board: a Spell's
        // last step is reaching the Trash, and a search limited to Base and
        // Battlefield would lose sight of it exactly when it matters.
        let found = cards.first { $0.name == play.name }
        return PendingPlay.Observation(
            cardStance: found?.stance,
            cardZone: found?.zone,
            exhaustedRunesNow: autoDetectRunes.filter { !$0.isReady }.count,
            runesInAreaNow: autoDetectRunes.count
        )
    }
}
