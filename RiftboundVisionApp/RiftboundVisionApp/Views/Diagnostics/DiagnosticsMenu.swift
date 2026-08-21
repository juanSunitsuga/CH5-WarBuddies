import SwiftUI
import RiftboundVision

/// The developer affordances, gathered behind one control.
struct DiagnosticsMenu: View {
    @ObservedObject var pipeline: CameraPipelineController
    @Binding var isShowingPipelineSettings: Bool
    /// Re-opens the welcome sheet. Owned by `ContentView`, which also
    /// shows it on first launch.
    let onShowOnboarding: () -> Void

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
    var body: some View {
        Menu {
            // Explicit action for the case passive discovery can't handle —
            // an iPhone the user manually Disconnected on the phone side.
            // This actively tries to open it, which is what triggers the
            // reconnect/permission handshake, rather than waiting for it to
            // reappear on its own.
            Button {
                onShowOnboarding()
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
        }
        .popover(isPresented: $isShowingPipelineSettings) {
            PipelineSettingsView(pipeline: pipeline)
        }
    }
}
