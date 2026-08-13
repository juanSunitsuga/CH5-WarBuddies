import SwiftUI

/// Per-stage pipeline toggles. Disabling a stage automatically disables
/// everything after it — enforced by
/// `CameraPipelineController.setStage`/`isStageActive`, not by this view,
/// so there's no way to reach an inconsistent "stage 3 on, stage 2 off"
/// state from the UI.
///
/// Extracted from `ContentView`'s toolbar so the right panel's gear button
/// can present the same controls.
struct PipelineSettingsView: View {
    @ObservedObject var pipeline: CameraPipelineController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pipeline Stages").font(.headline)
            Text("Turning off a stage automatically turns off everything after it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(PipelineStage.allCases) { stage in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(isOn: Binding(
                        get: { pipeline.isStageActive(stage) },
                        set: { pipeline.setStage(stage, enabled: $0) }
                    )) {
                        Text(stage.title)
                    }
                    .disabled(!stage.isWired)

                    if !stage.isWired {
                        Text("Not yet wired into the live pipeline.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(width: 280)
    }
}
