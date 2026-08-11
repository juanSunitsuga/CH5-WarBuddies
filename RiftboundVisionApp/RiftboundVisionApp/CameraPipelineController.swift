import SwiftUI
import CoreImage
import RiftboundVision

/// Drives camera → detector → tracker → temporal confirmation and publishes
/// what the debug UI needs to render. This is deliberately app-shell code
/// (lives here, not in the `RiftboundVision` library) — it exists to make
/// the pipeline's current state visible on screen, not to be reused by the
/// Expert System integration path, which goes through `ExpertSystemAdapter`
/// instead (already covered by the package's test suite).
///
/// The playmat overlay (`calibration`) starts centered on the first frame
/// and does nothing useful until the user drags its corners onto their
/// actual physical mat (see `isCalibrating`) — until then, `zoneMapper`
/// resolves everything to whatever zone that default quad happens to
/// overlap, which is meaningless. That's the gap this app makes visible
/// via the overlay itself, rather than a silent TODO comment.
@MainActor
final class CameraPipelineController: ObservableObject {
    @Published var backgroundImage: CGImage?
    @Published var snapshot = DebugFrameSnapshot(objects: [], latestEvent: nil, frameSize: .zero)
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

    /// The playmat template's alignment against the current camera frame.
    /// Starts centered on whatever the first frame's size turns out to be
    /// (see `process(_:)`) and is otherwise only ever changed by the user
    /// dragging `PlaymatOverlayView`'s corner handles.
    @Published var calibration = CameraPipelineController.defaultCalibration(for: CGSize(width: 1280, height: 720))
    /// Shows the draggable corner handles. Detection keeps running while
    /// calibrating — dragging updates `zoneMapper` live, so the overlay
    /// snapping into place over the physical mat is itself the feedback
    /// that calibration is correct.
    @Published var isCalibrating = false
    /// Output of `runCameraDiagnostic()` — every video device macOS
    /// reports, across every device type, not just the curated picker
    /// list. For "Continuity Camera works elsewhere but this app says no
    /// iPhone camera found" — answers whether the device is missing
    /// entirely or just showing up under a `deviceType` the picker
    /// doesn't recognize as a phone.
    @Published var debugReport: String?

    /// Manual stand-in for real card recognition, which doesn't exist yet
    /// (see `RecognizedCard`'s doc comment in the library) — the user taps
    /// an unidentified tracked card and picks it from `cardDatabase`. This
    /// is the exact seam a real recognizer plugs into later: swap
    /// `assignCard(_:to:)`'s manual call site for an automatic one, and
    /// everything downstream (the sidebar, the detail view) keeps working
    /// unchanged.
    @Published var cardAssignments: [TrackedObjectID: CardPrinting] = [:]
    let cardDatabase = CardDatabaseLoader.loadBundled()

    /// "Highlight the N Runes that need to be exhausted, don't move on
    /// until the player's actually exhausted them" — set by
    /// `beginPlayingCard(objectID:)`, cleared automatically once every
    /// required Rune's *observed* rotation reads Exhausted (see
    /// `process(_:)`), or manually via `cancelPendingPlay()`.
    @Published var pendingPlay: PendingCardPlay?

    /// Whose turn it is, what phase, and what round — set by hand (see
    /// `GameStateBar`), never inferred from the camera. Nothing in
    /// `process(_:)` reads or writes this; it exists purely for on-screen
    /// display and for the user's own bookkeeping.
    @Published var gameState = ManualGameState()

    /// Rotation only ever lands on exactly `0` or `.pi / 2` (see
    /// `process(_:)`'s orientation-derived rotation) — this threshold just
    /// needs to sit cleanly between the two.
    private static let exhaustedRotationThreshold: CGFloat = .pi / 4

    struct PendingCardPlay: Equatable {
        let cardObjectID: TrackedObjectID
        let cardName: String
        let cost: Int
        /// Fixed at the moment play begins — which specific physical
        /// Runes were chosen to pay for it. Doesn't change even if new
        /// Runes appear afterward; the player exhausts *these*, not "any
        /// N Runes."
        let requiredRuneIDs: [TrackedObjectID]
    }

    private let camera = AVFoundationCameraCapture()
    private let detector: any ObjectDetecting = CardDetectionModelLoader.loadDetector()
    private let tracker = ObjectTracker(settledOcclusionToleranceFrames: 300)
    private let temporalDetector = TemporalEventDetector()
    private let ciContext = CIContext()

    /// Rebuilt from `calibration` on every access rather than cached —
    /// cheap (it's ~15 small polygons), and guarantees it's never one
    /// frame stale relative to a corner the user just dragged.
    private var zoneMapper: ZoneMapper { ZoneMapper(zones: calibration.boardZones()) }

    /// Once every currently-tracked object is sitting in a
    /// `Zone.isPositionallyStable` zone (Battlefield/Rune Area/Rune Deck)
    /// and there's no `pendingPlay` actively watching for a rune flip, the
    /// board genuinely isn't changing frame to frame — running the
    /// detector (the single most expensive step in `process(_:)`, a full
    /// CoreML/Vision pass) on every one of those frames buys nothing. This
    /// throttles it to once every `settledDetectionCadence` frames in that
    /// case, and snaps back to full rate the instant anything is in a
    /// non-stable zone (hand, in transit) or a card is actively being
    /// played. The decision is one frame lagged (it reads the *previous*
    /// frame's `snapshot`), which only matters for how quickly the
    /// throttle re-engages/disengages, not for correctness — skipped
    /// frames feed the tracker zero detections, and `ObjectTracker`
    /// already tolerates that as occlusion (kept well under
    /// `settledOcclusionToleranceFrames` above) rather than a disappearance.
    private static let settledDetectionCadence = 4
    private var framesSinceRealDetection = 0

    private var previousTimestamp: TimeInterval?
    private var frameIndex = 0
    private var hasSizedCalibrationToFrame = false

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
    private var runLoop: Task<Void, Never>?
    private var statusLoop: Task<Void, Never>?

    init() {
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

    /// One row in the right-hand tracked-cards sidebar.
    struct TrackedCardEntry: Identifiable {
        let id: TrackedObjectID
        let object: TrackedObject
        let printing: CardPrinting?
        /// Whose side of the mat this object currently resolves to, per
        /// the live calibration — `nil` before calibration or if it's
        /// sitting outside every calibrated zone. `.player1` is always
        /// "You" (the near/bottom half in `RiftboundPlaymatTemplate`);
        /// `.player2` is "Opponent."
        let owner: Player?
    }

    /// Every currently-tracked CARD-type object (Runes excluded — this
    /// panel is specifically about card identity/text lookup), each
    /// paired with whatever card it's been assigned to, if any.
    var trackedCards: [TrackedCardEntry] {
        snapshot.objects
            .filter { $0.type == .card }
            .map { object in
                TrackedCardEntry(
                    id: object.id,
                    object: object,
                    printing: cardAssignments[object.id],
                    owner: zoneMapper.boardZone(for: object.center)?.owner
                )
            }
    }

    func assignCard(_ printing: CardPrinting, to objectID: TrackedObjectID) {
        cardAssignments[objectID] = printing
    }

    /// Starts the "pay this card's Energy cost" flow: picks `cost`
    /// currently-Ready, identified Runes and highlights them (via
    /// `pendingPlay`/`ExhaustPromptOverlayView`) as the ones the player
    /// must physically exhaust. Rule 156.1: Energy has no Domain, so any
    /// Ready Rune counts — which specific ones get chosen doesn't matter
    /// rules-wise, only the count does.
    func beginPlayingCard(objectID: TrackedObjectID) {
        guard let printing = cardAssignments[objectID] else {
            errorMessage = "This card hasn't been identified yet."
            return
        }
        guard let cost = printing.attributes.energy, cost > 0 else {
            errorMessage = "\(printing.name) has no Energy cost to pay."
            return
        }

        let readyRunes = snapshot.objects.filter { object in
            object.type == .rune
                && object.id != objectID
                && cardAssignments[object.id] != nil
                && object.rotation < Self.exhaustedRotationThreshold
        }

        guard readyRunes.count >= cost else {
            errorMessage = "Need \(cost) Ready Rune\(cost == 1 ? "" : "s") to play \(printing.name) — only \(readyRunes.count) identified and Ready right now."
            return
        }

        pendingPlay = PendingCardPlay(
            cardObjectID: objectID,
            cardName: printing.name,
            cost: cost,
            requiredRuneIDs: Array(readyRunes.prefix(cost)).map(\.id)
        )
        errorMessage = nil
    }

    func cancelPendingPlay() {
        pendingPlay = nil
    }

    /// `(exhaustedSoFar, total)` against the *current* frame — drives the
    /// overlay's progress text. `nil` when there's no pending play.
    var pendingPlayProgress: (done: Int, total: Int)? {
        guard let pendingPlay else { return nil }
        let done = pendingPlay.requiredRuneIDs.filter { id in
            (snapshot.objects.first { $0.id == id }?.rotation ?? 0) >= Self.exhaustedRotationThreshold
        }.count
        return (done, pendingPlay.requiredRuneIDs.count)
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
    }

    deinit {
        statusLoop?.cancel()
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
        frameIndex += 1

        let ciImage = CIImage(cvPixelBuffer: frame.pixelBuffer)
        let frameSize = CGSize(width: ciImage.extent.width, height: ciImage.extent.height)

        if !hasSizedCalibrationToFrame {
            calibration = Self.defaultCalibration(for: frameSize)
            hasSizedCalibrationToFrame = true
        }

        // "Object detection should only focus on the segmented area":
        // everything outside the calibrated mat's bounding rect is never
        // even handed to the detector, let alone tracked.
        //
        // Settled-mode throttle: if last frame's board was fully settled
        // (every object on a stable zone, nothing being played) and we
        // haven't skipped a real detection pass in a while, skip the
        // detector entirely this frame — see `settledDetectionCadence`.
        let everythingSettled = pendingPlay == nil
            && !snapshot.objects.isEmpty
            && snapshot.objects.allSatisfy { $0.currentZone.isPositionallyStable }
        let shouldRunDetector = !everythingSettled || framesSinceRealDetection >= Self.settledDetectionCadence

        let detections: [Detection]
        if shouldRunDetector {
            detections = (try? detector.detect(in: frame.pixelBuffer, regionOfInterest: calibration.boundingRect)) ?? []
            framesSinceRealDetection = 0
        } else {
            detections = []
            framesSinceRealDetection += 1
        }
        let result = tracker.update(
            detections: detections,
            zoneMapper: zoneMapper,
            frameIndex: frameIndex,
            timestamp: frame.timestamp,
            previousTimestamp: previousTimestamp
        )
        previousTimestamp = frame.timestamp

        // Real recognition, when `detector` is a `CoreMLCardDetector`:
        // a track carrying a `recognizedLabel` gets looked up in
        // `cardDatabase` and auto-assigned exactly once — first
        // successful recognition wins, so later frames don't flicker
        // between near-tied class guesses for the same physical card.
        // Runs *before* the rotation pass below since Exhaust/Ready
        // detection needs to know the card's printed orientation, which
        // only exists once it's identified.
        for object in result.objects {
            guard let label = object.recognizedLabel, cardAssignments[object.id] == nil else { continue }
            if let printing = cardDatabase.printing(approximatelyNamed: label) {
                cardAssignments[object.id] = printing
            }
        }

        // A card that's reached Trash has left play — its cached identity
        // shouldn't linger. `object.currentZone` is already resolved
        // against the calibrated overlay by the tracker (zoneMapper was
        // passed into `tracker.update` above), so this is just reading
        // that, not a second zone lookup.
        for object in result.objects where object.currentZone == .trash {
            cardAssignments.removeValue(forKey: object.id)
        }
        // Same idea for objects the tracker has fully dropped (occlusion
        // tolerance exceeded, or it left the calibrated area entirely) —
        // no point holding onto a cached identity for an object that's no
        // longer being tracked at all.
        for id in result.disappearedIDs {
            cardAssignments.removeValue(forKey: id)
        }

        // CoreMLCardDetector reports rotation = 0 always (YOLO gives no
        // true angle — see its doc comment). Recover Exhaust/Ready (rules
        // 592–593) the way the user described: compare the *observed*
        // bounding box's long axis against the *printed* orientation from
        // the card database, once the object is identified. Unidentified
        // objects keep whatever rotation the detector actually reported
        // (0 for CoreMLCardDetector, a real angle for VisionRectangleDetector).
        var adjustedObjects = result.objects
        for index in adjustedObjects.indices {
            guard let printing = cardAssignments[adjustedObjects[index].id] else { continue }
            let isExhausted = printing.isExhausted(observedBoundingBox: adjustedObjects[index].boundingBox)
            adjustedObjects[index].rotation = isExhausted ? .pi / 2 : 0
        }
        let adjustedResult = TrackerUpdateResult(
            objects: adjustedObjects,
            appearedIDs: result.appearedIDs,
            disappearedIDs: result.disappearedIDs
        )
        let events = temporalDetector.process(adjustedResult, zoneMapper: zoneMapper, timestamp: frame.timestamp)

        let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)

        backgroundImage = cgImage
        snapshot = DebugFrameSnapshot(
            objects: adjustedObjects,
            latestEvent: events.last ?? snapshot.latestEvent,
            frameSize: frameSize
        )

        // "Don't continue until the player's finished exhausting the
        // highlighted Runes": check every required Rune's *this-frame*
        // rotation. A Rune that's disappeared from tracking entirely
        // isn't found, and `?? 0` treats that as still-Ready — a vanished
        // Rune should never silently count as exhausted.
        if let pendingPlay, pendingPlay.requiredRuneIDs.allSatisfy({ id in
            (adjustedObjects.first { $0.id == id }?.rotation ?? 0) >= Self.exhaustedRotationThreshold
        }) {
            self.pendingPlay = nil
        }
    }
}
