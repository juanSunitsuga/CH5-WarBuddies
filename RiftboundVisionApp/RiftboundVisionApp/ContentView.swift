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
struct ContentView: View {
    @StateObject private var pipeline: CameraPipelineController
    @State private var isShowingPipelineSettings = false
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
        VStack(spacing: 0) {
            GameStateBar(gameState: $pipeline.gameState)

            HStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack {
                    Color.black

                    if let backgroundImage = pipeline.backgroundImage {
                        Image(decorative: backgroundImage, scale: 1, orientation: .up)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Text(pipeline.isCameraRunning ? "Waiting for camera frames…" : "Opening camera…")
                            .foregroundStyle(.white.opacity(0.6))
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
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.red.opacity(0.8))
                                .cornerRadius(6)
                                .padding()
                        }
                    }
                }
            }

            DetectedCardsPanel(pipeline: pipeline, selection: $selectedCard)
            }

            TurnControlBar(
                gameState: $pipeline.gameState,
                isAutoDetecting: $pipeline.isAutoDetectingPhase,
                latestInstruction: pipeline.instructions.first,
                misplacedCards: pipeline.misplacedCards
            )
        }
        .frame(minWidth: 1160, minHeight: 675)
        .toolbar {
            ToolbarItem {
                cameraPicker
            }
            ToolbarItem {
                // Explicit action for the case passive discovery can't
                // handle — an iPhone the user manually Disconnected on
                // the phone side. This actively tries to open it, which
                // is what triggers the reconnect/permission handshake,
                // rather than waiting for it to reappear on its own.
                Button {
                    pipeline.useIPhoneCamera()
                } label: {
                    Label("Use iPhone Camera", systemImage: "iphone")
                }
            }
            ToolbarItem {
                // Drag the 4 yellow corner handles onto the physical
                // mat's actual corners as seen by the camera — a visual
                // reference layer only now, not consulted by detection.
                Toggle(isOn: $pipeline.isCalibrating) {
                    Label("Calibrate Playmat", systemImage: "square.dashed")
                }
                .toggleStyle(.button)
            }
            ToolbarItem {
                // Debug settings overlay — per-stage toggles instead of one
                // flat kill switch. Disabling an earlier stage cascades:
                // everything downstream of it turns off too (enforced by
                // `CameraPipelineController.setStage`/`isStageActive`), so
                // there's no way to leave the pipeline in an inconsistent
                // "stage 3 on, stage 2 off" state from this UI.
                Button {
                    isShowingPipelineSettings = true
                } label: {
                    Label("Pipeline Settings", systemImage: "gearshape")
                }
                .popover(isPresented: $isShowingPipelineSettings) {
                    PipelineSettingsView(pipeline: pipeline)
                }
            }
            ToolbarItem {
                // Diagnostic for "Continuity Camera works elsewhere but
                // this app doesn't see it" — dumps every video device
                // macOS reports (all device types, plus the legacy
                // enumeration API) to the console and the sheet below.
                Button {
                    pipeline.runCameraDiagnostic()
                } label: {
                    Label("Debug Cameras", systemImage: "ladybug")
                }
            }
            ToolbarItem {
                // Starts the *pipeline*, not the camera — the feed is
                // already live so the mat can be calibrated first.
                Button(pipeline.isPipelineRunning ? "Stop" : "Start") {
                    pipeline.isPipelineRunning ? pipeline.stopPipeline() : pipeline.startPipeline()
                }
                .disabled(!pipeline.isCameraRunning)
            }
        }
        .onAppear { pipeline.refreshAvailableCameras() }
        // Bring the camera up as soon as the window opens, prompting for
        // access the first time. Calibration needs a live picture, and
        // aligning the mat after starting detection is what put cards in
        // the wrong zones.
        .task { await pipeline.openCamera() }
        .sheet(isPresented: Binding(
            get: { pipeline.debugReport != nil },
            set: { if !$0 { pipeline.debugReport = nil } }
        )) {
            debugReportSheet
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
                    .foregroundStyle(.white.opacity(0.6))
            }
            // The measured detection rate, not a configured one — this is
            // what the machine actually sustains.
            if pipeline.detectionsPerSecond > 0 {
                Text("· \(pipeline.detectionsPerSecond, specifier: "%.0f") fps")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.black.opacity(0.4), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
    }

    private var debugReportSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camera Diagnostic").font(.title2.bold())
            ScrollView {
                Text(pipeline.debugReport ?? "")
                    .font(.system(.body, design: .monospaced))
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
                Spacer()
                Button("Close") { pipeline.debugReport = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
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
            Label(cameraLabel, systemImage: selectedIsContinuityCamera ? "iphone" : "camera")
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
