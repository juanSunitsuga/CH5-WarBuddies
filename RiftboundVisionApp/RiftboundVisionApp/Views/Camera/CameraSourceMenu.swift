import SwiftUI
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
}
