import SwiftUI
import UniformTypeIdentifiers
import RiftboundVision

/// Picks which camera the app watches.
///
/// "Connect to iPhone" is just choosing the Continuity Camera entry once
/// the phone is nearby and has offered itself — that handshake is entirely
/// OS-level and nothing this app negotiates.
struct CameraSourceMenu: View {
    @ObservedObject var pipeline: CameraPipelineController

    /// Camera-source picker — "connect to iPhone" is just picking the
    /// Continuity Camera entry once the iPhone is nearby/paired and has
    /// made itself available (that pairing/handoff is entirely OS-level,
    /// nothing this app needs to negotiate).
    var body: some View {
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

            // A recorded run, for the measurements in Subbab 4.4. The file
            // goes in where the camera would, through the same
            // `CameraCapturing` contract, so the figures describe the real
            // pipeline rather than a shortcut through it.
            Divider()
            Button("Play Video File…") { chooseVideoFile() }
            if pipeline.videoSourceURL != nil {
                Button("Back to Live Camera") {
                    Task { await pipeline.useLiveCamera() }
                }
            }
        } label: {
            if let url = pipeline.videoSourceURL {
                Label(url.deletingPathExtension().lastPathComponent, systemImage: "film")
            } else {
                Label(cameraLabel, systemImage: selectedIsContinuityCamera ? "iphone" : "camera")
            }
        }
    }

    /// `NSOpenPanel` rather than SwiftUI's `.fileImporter`, because this is
    /// a menu inside a toolbar item: `.fileImporter` attaches its sheet to
    /// the view it is placed on, and a menu item is gone by the time the
    /// sheet would present, so nothing appears.
    private func chooseVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Pick a recording to play in place of the camera."
        panel.prompt = "Play"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await pipeline.useVideoFile(url) }
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
}
