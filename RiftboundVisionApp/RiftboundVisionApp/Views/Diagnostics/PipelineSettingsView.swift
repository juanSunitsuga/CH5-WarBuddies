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
                .riftFont(.heading)
                .foregroundStyle(RiftboundPalette.regularText)
            Text("Turning off a stage automatically turns off everything after it.")
                .riftFont(.body)
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
                            .riftFont(.body)
                            .foregroundStyle(RiftboundPalette.regularText)
                    }
                    .toggleStyle(RiftSwitchToggleStyle())

                    if !stage.isWired {
                        Text("Not yet wired into the live pipeline.")
                            .riftFont(.body)
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
                    }
                }
                .riftComponentDisabled(!stage.isWired)
            }

            Rectangle()
                .fill(RiftboundPalette.elementStroke.opacity(0.25))
                .frame(height: 1)

            // Moved here from a permanent badge on the camera view — fps
            // and a raw table-event count are developer telemetry (proof
            // the pipeline is actually producing events, and what rate the
            // machine sustains), not information a player needs in front of
            // them for the whole game. This popover is already the
            // developer surface (see this type's doc comment), so it's
            // where they belong.
            Text("Live Telemetry")
                .riftFont(.heading)
                .foregroundStyle(RiftboundPalette.regularText)

            telemetryRow(
                "Detection rate",
                pipeline.detectionsPerSecond > 0
                    ? String(format: "%.0f fps", pipeline.detectionsPerSecond)
                    : "—"
            )
            telemetryRow("Table events", "\(pipeline.observedEvents.count)")
        }
        .padding(18)
        .frame(width: 320)
        .background(RiftboundPalette.secondaryBackground)
    }

    private func telemetryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .riftFont(.body)
                .foregroundStyle(RiftboundPalette.regularText.opacity(0.7))
            Spacer()
            Text(value)
                .riftFont(.body)
                .foregroundStyle(RiftboundPalette.regularText)
        }
    }
}
