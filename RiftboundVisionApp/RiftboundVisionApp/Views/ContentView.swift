import SwiftUI
import SwiftData
import AppKit
import RiftboundVision

/// The actual wiring is `CameraPipelineController` — this view just binds
/// to it. Everything here is "live": press Start and you'll see the real
/// camera feed with every current detection boxed and labeled, on a
/// fixed poll cadence rather than every frame (see the controller's doc
/// comment — this matches `feature/riftbound-scanner-prototype`'s
/// architecture: no per-object tracking, no persistent identity).
///
/// The V3 layout is the same three-part split it always was — header,
/// camera + right column, bottom bar — with one structural change: the
/// camera feed is now locked to 16:9 and inset inside a gold
/// `elementStroke` frame, with the window's `mainBackground` visible
/// around it. Without the aspect lock the stage took whatever rectangle
/// the split view left it and the feed letterboxed itself inside, so the
/// frame ended up enclosing two large slabs of empty space rather than
/// the picture.
struct ContentView: View {
    @StateObject private var pipeline: CameraPipelineController
    @State private var isShowingPipelineSettings = false
    @State private var isShowingOnboarding = false
    /// Whether the welcome sheet has already been shown. Persisted, so it
    /// greets a new player once and then stays out of the way — a modal
    /// that appears every launch is one people learn to dismiss without
    /// reading. It stays reachable from the Help menu.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    /// The card being inspected. Lives here rather than in the panel so the
    /// camera view and the sidebar agree on what's selected — tapping a box
    /// is what usually sets it.
    @State private var selectedCard: CardPrinting?

    /// `modelContext` is optional so SwiftUI previews (and the no-arg
    /// `ContentView()` used in `#Preview`) still work without a container —
    /// persistence just no-ops when it's absent.
    init(modelContext: ModelContext? = nil) {
        _pipeline = StateObject(wrappedValue: CameraPipelineController(modelContext: modelContext))
    }

    var body: some View {
        // Top bar across the full width, then the two columns beneath it.
        //
        // `GameStateBar` is inside the left column rather than spanning the
        // window, which is what puts the Score panel level with the turn
        // banner instead of starting below it. The bottom bar is in that
        // column too, so the sidebar runs unbroken to the bottom edge.
        VStack(spacing: 0) {
            topBar

            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    GameStateBar(gameState: $pipeline.gameState)
                    cameraStage
                    TurnControlBar(
                        gameState: $pipeline.gameState,
                        isAutoDetecting: $pipeline.isAutoDetectingPhase,
                        instructions: pipeline.instructions,
                        phaseProgress: pipeline.phaseProgress,
                        misplacedCards: pipeline.misplacedCards,
                        needsCalibration: pipeline.needsCalibration
                    )
                }

                DetectedCardsPanel(pipeline: pipeline, selection: $selectedCard)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(RiftboundPalette.mainBackground)
        .frame(minWidth: 1160, minHeight: 675)
        .onAppear {
            pipeline.refreshAvailableCameras()
            // First launch only. Set before presenting rather than on
            // dismiss, so a player who closes the window with the sheet
            // still open isn't greeted by it again next time.
            if !hasSeenOnboarding {
                hasSeenOnboarding = true
                isShowingOnboarding = true
            }
        }
        .sheet(isPresented: $isShowingOnboarding) {
            OnboardingView { isShowingOnboarding = false }
        }
        // Bring the camera up as soon as the window opens, prompting for
        // access the first time. Calibration needs a live picture, and
        // aligning the mat after starting detection is what put cards in
        // the wrong zones.
        .task { await pipeline.openCamera() }
        // Release the camera when the window goes away. Without this the
        // capture session — and the OS camera indicator — stayed live for
        // the rest of the process's life.
        .onDisappear { pipeline.closeCamera() }
        .sheet(isPresented: Binding(
            get: { pipeline.debugReport != nil },
            set: { if !$0 { pipeline.debugReport = nil } }
        )) {
            debugReportSheet
        }
    }


    // MARK: - Camera stage

    /// The framed camera area. The frame is drawn *outside* the
    /// `GeometryReader` so the overlay maths below is untouched by it —
    /// the scale correction still refers to the feed's own bounds, not the
    /// frame's.
    private var cameraStage: some View {
        cameraFeed
            // Every camera this app targets (built-in, Continuity, USB)
            // delivers 16:9, so the frame can simply *be* that shape
            // rather than boxing a letterboxed picture.
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(RiftboundPalette.elementStroke, lineWidth: 2)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
    }

    private var cameraFeed: some View {
        GeometryReader { proxy in
                ZStack {
                    // Was `Color.black`. The letterbox around an
                    // aspect-fit feed is a large area of the window, and
                    // pure black is the one shade on screen that belongs
                    // to no part of the palette — it read as a hole.
                    // `elementShadow` is the board's own darkest value.
                    RiftboundPalette.elementShadow

                    if let backgroundImage = pipeline.backgroundImage {
                        Image(decorative: backgroundImage, scale: 1, orientation: .up)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Text(pipeline.isCameraRunning ? "Waiting for camera frames…" : "Opening camera…")
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
                    }

                    // Both overlays draw in the raw pixel coordinates of
                    // `pipeline.frameSize`/`pipeline.calibration` (the
                    // camera frame's native size), but the image above is
                    // displayed aspect-fit inside whatever the window's
                    // current size is — without this correction, boxes
                    // and the zone reference layer drift away from what
                    // they're labeling as soon as the window isn't
                    // exactly the camera's native resolution.
                    let scale = fitScale(container: proxy.size, content: pipeline.frameSize)

                    PlaymatOverlayView(calibration: $pipeline.calibration, isEditable: pipeline.isCalibrating)
                        .frame(width: pipeline.frameSize.width, height: pipeline.frameSize.height)
                        .scaleEffect(scale)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    // Interactive: tapping a card's box selects it, which
                    // is how the sidebar is driven now.
                    LiveDetectionOverlayView(
                        detections: pipeline.detections,
                        cardDatabase: pipeline.cardDatabase,
                        selectedPrintingID: selectedCard?.id,
                        onSelect: { selectedCard = $0 }
                    )
                        .frame(width: pipeline.frameSize.width, height: pipeline.frameSize.height)
                        .scaleEffect(scale)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    // Above the detection boxes: the tracker's centroids
                    // and their stable IDs. This is the layer that shows
                    // whether a card keeps its identity across a pickup —
                    // the boxes below look the same either way.
                    TrackedObjectOverlayView(objects: pipeline.trackedObjects)
                        .frame(width: pipeline.frameSize.width, height: pipeline.frameSize.height)
                        .scaleEffect(scale)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .allowsHitTesting(false)

                    VStack {
                        detectionCountBadge
                        Spacer()
                    }
                    .padding(.top, 12)

                    if let errorMessage = pipeline.errorMessage {
                        VStack {
                            Spacer()
                            Text(errorMessage)
                                .font(RiftboundFont.body)
                                .foregroundStyle(RiftboundPalette.regularText)
                                .padding(10)
                                .background(RiftboundPalette.primaryButton, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding()
                        }
                    }
                }
            }
    }

    private var detectionCountBadge: some View {
        HStack(spacing: 8) {
            Text(pipeline.detections.isEmpty ? "No cards detected" : "\(pipeline.detections.count) card\(pipeline.detections.count == 1 ? "" : "s") detected")
            // Visible proof the reconnected Object Tracking + Area of
            // Region pipeline (expertSystemAdapter) is actually producing
            // events, not just structurally wired — see
            // CameraPipelineController.observedEvents' doc comment.
            if !pipeline.observedEvents.isEmpty {
                Text("· \(pipeline.observedEvents.count) table event\(pipeline.observedEvents.count == 1 ? "" : "s")")
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
            }
            // The measured detection rate, not a configured one — this is
            // what the machine actually sustains.
            if pipeline.detectionsPerSecond > 0 {
                Text("· \(pipeline.detectionsPerSecond, specifier: "%.0f") fps")
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
            }
        }
        .font(RiftboundFont.body)
        .foregroundStyle(RiftboundPalette.regularText)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(RiftboundPalette.elementShadow.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(RiftboundPalette.elementStroke.opacity(0.7), lineWidth: 1))
    }

    private var debugReportSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camera Diagnostic")
                .font(RiftboundFont.heading)
                .foregroundStyle(RiftboundPalette.regularText)
            ScrollView {
                // Monospaced on purpose — this is a device dump, and
                // column alignment is the point. Sora is a proportional
                // face, so the theme scale doesn't apply here.
                Text(pipeline.debugReport ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(RiftboundPalette.regularText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Copy") {
                    if let report = pipeline.debugReport {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report, forType: .string)
                    }
                }
                .buttonStyle(RiftSecondaryButtonStyle())
                Spacer()
                Button("Close") { pipeline.debugReport = nil }
                    .buttonStyle(RiftPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 400)
        .background(RiftboundPalette.mainBackground)
    }

    /// Camera-source picker — "connect to iPhone" is just picking the
    /// Continuity Camera entry once the iPhone is nearby/paired and has
    /// made itself available (that pairing/handoff is entirely OS-level,
    /// nothing this app needs to negotiate).
    private var cameraPicker: some View {
        Menu {
            Button("System Default") {
                pipeline.selectCamera(id: nil)
            }
            if !pipeline.availableCameras.isEmpty {
                Divider()
                ForEach(pipeline.availableCameras) { device in
                    Button {
                        pipeline.selectCamera(id: device.id)
                    } label: {
                        Label(device.name, systemImage: device.isContinuityCamera ? "iphone" : "camera")
                        if pipeline.selectedCameraID == device.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button("Refresh Camera List") {
                pipeline.refreshAvailableCameras()
            }
        } label: {
            // Icon only: the full "Camera: FaceTime HD Camera" is useful in
            // the menu's own header but far too wide for a bar whose whole
            // point is four compact controls.
            Label(cameraLabel, systemImage: selectedIsContinuityCamera ? "iphone" : "camera")
                .labelStyle(.iconOnly)
        }
    }

    // MARK: - Top bar

    /// The window's own bar, drawn rather than handed to SwiftUI's
    /// `.toolbar`.
    ///
    /// The reference puts the app name hard left and the four controls hard
    /// right. `.toolbar` couldn't produce that here: under
    /// `.hiddenTitleBar` there is no title for `.primaryAction` items to
    /// sit opposite, so every item — whatever its placement — packed
    /// against the leading edge next to the traffic lights. Two attempts at
    /// steering it with placements and background modifiers both came out
    /// left-aligned.
    ///
    /// An `HStack` with a `Spacer` is not a workaround for that, it's the
    /// thing being asked for: a name, a gap, four controls. Drawing it
    /// directly also means the name is plain text with no item container,
    /// which is what the reference shows and what the platform's own
    /// styling kept adding back.
    ///
    /// The leading inset clears the traffic lights, which the system still
    /// draws on top of this view.
    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Riftchamps")
                .font(RiftboundFont.heading)
                .foregroundStyle(RiftboundPalette.regularText)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 20)

            cameraPicker
                .menuStyle(.borderlessButton)
                .fixedSize()

            // Drag the 4 corner handles onto the physical mat's actual
            // corners as seen by the camera — a visual reference layer
            // only, not consulted by detection.
            Toggle(isOn: $pipeline.isCalibrating) {
                Label("Calibrate Playmat", systemImage: "square.dashed")
                    .labelStyle(.iconOnly)
            }
            .toggleStyle(.button)

            diagnosticsMenu
                .menuStyle(.borderlessButton)
                .fixedSize()

            // Starts the *pipeline*, not the camera — the feed is already
            // live so the mat can be calibrated first.
            Button(pipeline.isPipelineRunning ? "Stop" : "Start Game") {
                pipeline.isPipelineRunning ? pipeline.stopPipeline() : pipeline.startPipeline()
            }
            .disabled(!pipeline.isCameraRunning)
        }
        .padding(.leading, 78)
        .padding(.trailing, 16)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(RiftboundPalette.titleBar)
    }

    /// The three developer affordances, folded behind one control.
    ///
    /// They used to be three separate toolbar buttons — an iPhone glyph, a
    /// gear and a ladybug — which put six items across the top bar and made
    /// the two a player actually needs (pick a camera, calibrate the mat)
    /// hard to find among them. None of them is used during a game: two are
    /// for when a camera won't appear, and one is a pipeline kill-switch
    /// panel.
    ///
    /// Nothing is removed, only gathered. A menu also lets each item carry
    /// its full name instead of a glyph that has to be guessed at.
    private var diagnosticsMenu: some View {
        Menu {
            // Explicit action for the case passive discovery can't handle —
            // an iPhone the user manually Disconnected on the phone side.
            // This actively tries to open it, which is what triggers the
            // reconnect/permission handshake, rather than waiting for it to
            // reappear on its own.
            Button {
                isShowingOnboarding = true
            } label: {
                Label("How to Play…", systemImage: "questionmark.circle")
            }

            Divider()

            Button {
                pipeline.useIPhoneCamera()
            } label: {
                Label("Use iPhone Camera", systemImage: "iphone")
            }

            // Per-stage toggles instead of one flat kill switch. Disabling
            // an earlier stage cascades: everything downstream turns off
            // too (enforced by `CameraPipelineController.setStage`/
            // `isStageActive`), so there's no way to leave the pipeline in
            // an inconsistent "stage 3 on, stage 2 off" state from here.
            Button {
                isShowingPipelineSettings = true
            } label: {
                Label("Pipeline Settings…", systemImage: "gearshape")
            }

            Divider()

            // Diagnostic for "Continuity Camera works elsewhere but this
            // app doesn't see it" — dumps every video device macOS reports
            // (all device types, plus the legacy enumeration API).
            Button {
                pipeline.runCameraDiagnostic()
            } label: {
                Label("Debug Cameras…", systemImage: "ladybug")
            }
        } label: {
            Label("Help & Diagnostics", systemImage: "questionmark.circle")
                .labelStyle(.iconOnly)
        }
        .popover(isPresented: $isShowingPipelineSettings) {
            PipelineSettingsView(pipeline: pipeline)
        }
    }

    private var selectedIsContinuityCamera: Bool {
        guard let id = pipeline.selectedCameraID else { return false }
        return pipeline.availableCameras.first(where: { $0.id == id })?.isContinuityCamera ?? false
    }

    private var cameraLabel: String {
        guard let id = pipeline.selectedCameraID,
              let device = pipeline.availableCameras.first(where: { $0.id == id }) else {
            return "Camera: System Default"
        }
        return "Camera: \(device.name)"
    }

    /// Aspect-fit scale factor, matching `.aspectRatio(contentMode: .fit)`
    /// above — kept in lockstep so the overlay always sits exactly over
    /// the displayed video image, not the raw window bounds.
    private func fitScale(container: CGSize, content: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0 else { return 1 }
        return min(container.width / content.width, container.height / content.height)
    }
}

#Preview {
    ContentView()
}
