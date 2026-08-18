import SwiftUI

/// Per-stage pipeline toggles. Disabling a stage automatically disables
/// everything after it — enforced by
/// `CameraPipelineController.setStage`/`isStageActive`, not by this view,
/// so there's no way to reach an inconsistent "stage 3 on, stage 2 off"
/// state from the UI.
///
/// Extracted from `ContentView`'s toolbar so the right panel's gear button
/// can present the same controls.
///
/// This is a developer surface, not a player one — the reference doesn't
/// draw it. It's themed anyway, because a stock-grey popover hanging off a
/// gold-and-navy window is more jarring than the popover itself is useful.
struct PipelineSettingsView: View {
    @ObservedObject var pipeline: CameraPipelineController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pipeline Stages")
                .font(RiftboundFont.heading)
                .foregroundStyle(RiftboundPalette.regularText)
            Text("Turning off a stage automatically turns off everything after it.")
                .font(RiftboundFont.body)
                .foregroundStyle(RiftboundPalette.regularText.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(PipelineStage.allCases) { stage in
                // The board's rule applied literally: an unwired stage is
                // a *whole* row that's off — label, switch and footnote —
                // so the 50% dim goes on the row, not on the switch alone.
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { pipeline.isStageActive(stage) },
                        set: { pipeline.setStage(stage, enabled: $0) }
                    )) {
                        Text(stage.title)
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText)
                    }
                    .toggleStyle(RiftSwitchToggleStyle())

                    if !stage.isWired {
                        Text("Not yet wired into the live pipeline.")
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
                    }
                }
                .riftComponentDisabled(!stage.isWired)
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(RiftboundPalette.secondaryBackground)
    }
}
