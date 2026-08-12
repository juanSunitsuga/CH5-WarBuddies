import SwiftUI
import SwiftData
import AppKit
import RiftboundVision

/// The actual wiring is `CameraPipelineController` — this view just binds
/// to it. Everything here is "live": press Start and you'll see the real
/// camera feed with real detections drawn over it. With `ZoneMapper`
/// uncalibrated (see the controller), every object's zone reads
/// `.unknown` and no `.objectMoved` event ever confirms — that's the
/// visible gap, not a placeholder screen.
struct ContentView: View {
    @StateObject private var pipeline: CameraPipelineController

    /// `modelContext` is optional so SwiftUI previews (and the no-arg
    /// `ContentView()` used in `#Preview`) still work without a container —
    /// persistence just no-ops when it's absent.
    init(modelContext: ModelContext? = nil) {
        _pipeline = StateObject(wrappedValue: CameraPipelineController(modelContext: modelContext))
    }

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack {
                    Color.black

                    if let backgroundImage = pipeline.backgroundImage {
                        Image(decorative: backgroundImage, scale: 1, orientation: .up)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Text(pipeline.isRunning ? "Waiting for camera frames…" : "Press Start")
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // Both overlays draw in the raw pixel coordinates of
                    // `pipeline.snapshot`/`pipeline.calibration` (the camera
                    // frame's native size), but the image above is displayed
                    // aspect-fit inside whatever the window's current size
                    // is — without this correction, boxes and zone outlines
                    // drift away from what they're labeling as soon as the
                    // window isn't exactly the camera's native resolution.
                    let scale = fitScale(container: proxy.size, content: pipeline.snapshot.frameSize)

                    PlaymatOverlayView(calibration: $pipeline.calibration, isEditable: pipeline.isCalibrating)
                        .frame(width: pipeline.snapshot.frameSize.width, height: pipeline.snapshot.frameSize.height)
                        .scaleEffect(scale)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    DebugOverlayView(snapshot: pipeline.snapshot)
                        .frame(width: pipeline.snapshot.frameSize.width, height: pipeline.snapshot.frameSize.height)
                        .scaleEffect(scale)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .allowsHitTesting(false)

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

            // The SpellTable-style sidebar: tracked cards, grouped by
            // which seat they're currently on, click for info.
            TrackedCardsPanel(pipeline: pipeline)
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
                // mat's actual corners as seen by the camera. This is the
                // entire calibration step — once the outline snaps onto
                // the real mat, `zoneMapper` resolves real zones instead
                // of `.unknown` for everything.
                Toggle(isOn: $pipeline.isCalibrating) {
                    Label("Calibrate Playmat", systemImage: "square.dashed")
                }
                .toggleStyle(.button)
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
                Button(pipeline.isRunning ? "Stop" : "Start") {
                    pipeline.isRunning ? pipeline.stop() : pipeline.start()
                }
            }
        }
        .onAppear { pipeline.refreshAvailableCameras() }
        .sheet(isPresented: Binding(
            get: { pipeline.debugReport != nil },
            set: { if !$0 { pipeline.debugReport = nil } }
        )) {
            debugReportSheet
        }
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
