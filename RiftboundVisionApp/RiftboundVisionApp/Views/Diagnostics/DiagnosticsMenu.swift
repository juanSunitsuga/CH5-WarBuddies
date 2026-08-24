import SwiftUI

/// The two ways into the app's own explanation of itself, behind one
/// toolbar control.
///
/// This was "Help & Diagnostics" and carried four more items — an iPhone
/// camera action, the pipeline stage toggles, a device dump and the text
/// size setting. They've been removed one at a time; what's left is help,
/// so the control says Help and nothing else.
///
/// Text size did not move *out* of the app when it left this menu — it
/// lives in the View menu (see `RiftboundTextSizeCommands`), with the
/// standard ⌘+ / ⌘− / ⌘0 shortcuts, which is where a Mac user looks for it
/// anyway.
struct DiagnosticsMenu: View {
    /// Re-opens the welcome sheet. Owned by `ContentView`, which also
    /// shows it on first launch.
    let onShowOnboarding: () -> Void
    /// Opens `OnboardingTourView` — the step-by-step BonBon walkthrough,
    /// alongside the welcome sheet above rather than instead of it.
    let onShowTour: () -> Void

    var body: some View {
        Menu {
            Button {
                onShowOnboarding()
            } label: {
                Label("Quick Guide…", systemImage: "questionmark.circle")
            }

            Button {
                onShowTour()
            } label: {
                Label("Take the Tour…", systemImage: "figure.walk")
            }
        } label: {
            Label("Help", systemImage: "questionmark.circle")
        }
    }
}
