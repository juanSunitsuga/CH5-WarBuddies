import SwiftUI
import RiftboundVision
import RiftboundExpertSystem

/// What the pipeline is actually doing, in the right column, behind the
/// Debugger Mode switch.
///
/// This is the developer surface the app had been missing. The two logs are
/// the point of it, and they are deliberately *two*: the vision log is what
/// tracking saw, the engine log is what the rules made of it, and when
/// those two disagree the difference is the whole debugging signal. A
/// single merged stream hides exactly that — an event present in one and
/// absent from the other is the common failure, and it only reads as a
/// failure when the two are side by side.
///
/// Absorbed `PipelineSettingsView`, which held the same stage toggles and
/// telemetry in a popover nothing presented any more.
struct DebuggerPanel: View {
    @ObservedObject var pipeline: CameraPipelineController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            stages
            telemetry
            visionLog
            engineLog
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stage toggles

    private var stages: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Pipeline Stages")
            Text("Turning off a stage turns off everything after it.")
                .riftFont(.body)
                .foregroundStyle(RiftboundPalette.regularText.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(PipelineStage.allCases) { stage in
                // The board's rule applied literally: an unwired stage is a
                // *whole* row that's off — label, switch and footnote — so
                // the dim goes on the row, not on the switch alone.
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
        }
    }

    // MARK: - Telemetry

    private var telemetry: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Live Telemetry")
            row(
                "Detection rate",
                pipeline.detectionsPerSecond > 0
                    ? String(format: "%.0f fps", pipeline.detectionsPerSecond)
                    : "—"
            )
            row("Table events", "\(pipeline.metrics.eventCount)")
            row("Tracked objects", "\(pipeline.trackedObjects.count)")
            // Per-stage sample counts, so it is visible at a glance whether
            // a stage is being reached at all. A stage sitting at 0 while
            // the one before it climbs is the pipeline stopping there, which
            // is otherwise only discoverable by reading the logs below.
            ForEach(pipeline.metrics.allLatencies, id: \.stage) { latency in
                row(latency.stage.rawValue, "\(latency.count)")
            }
        }
    }

    // MARK: - Vision log

    private var visionLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Vision Log")
            if pipeline.visionTrace.isEmpty {
                empty(pipeline.isPipelineRunning
                      ? "Nothing seen yet."
                      : "Starts filling when the game starts.")
            } else {
                ForEach(pipeline.visionTrace) { line in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            // A dropped event is the finding, so it is
                            // marked rather than merely listed.
                            Text(line.wasForwarded ? "→" : "✕")
                                .riftFont(.body)
                                .foregroundStyle(line.wasForwarded
                                                 ? RiftboundPalette.regularText.opacity(0.6)
                                                 : RiftboundPalette.dangerButton)
                            Text("#\(line.objectID) \(line.kind)")
                                .riftFont(.body)
                                .foregroundStyle(RiftboundPalette.regularText)
                        }
                        Text(line.transition)
                            .riftFont(.body)
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.7))
                        if let label = line.label {
                            Text(String(format: "%@ · %.0f%%", label, Double(line.confidence) * 100))
                                .riftFont(.body)
                                .foregroundStyle(RiftboundPalette.regularText.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Engine log

    private var engineLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Engine Log")
            if pipeline.instructions.isEmpty {
                empty("No verdicts yet.")
            } else {
                ForEach(pipeline.instructions) { entry in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.eventSummary)
                            .riftFont(.body)
                            .foregroundStyle(RiftboundPalette.regularText.opacity(0.7))
                        Text(entry.headline)
                            .riftFont(.body)
                            .foregroundStyle(color(for: entry.verdict))
                        if let detail = entry.detail {
                            Text(detail)
                                .riftFont(.body)
                                .foregroundStyle(RiftboundPalette.regularText.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func color(for verdict: InstructionLogEntry.Verdict) -> Color {
        switch verdict {
        case .accepted, .informational: return RiftboundPalette.regularText
        case .rejected: return RiftboundPalette.dangerButton
        // Not an error — tracking jitter produces these routinely, and
        // colouring them like a rejection would make a working pipeline
        // look broken.
        case .unrecognized: return RiftboundPalette.regularText.opacity(0.6)
        }
    }

    // MARK: - Small pieces

    private func heading(_ text: String) -> some View {
        Text(text)
            .riftFont(.subheading)
            .foregroundStyle(RiftboundPalette.regularText)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .riftFont(.body)
                .foregroundStyle(RiftboundPalette.regularText.opacity(0.7))
            Spacer(minLength: 8)
            Text(value)
                .riftFont(.body)
                .monospacedDigit()
                .foregroundStyle(RiftboundPalette.regularText)
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .riftFont(.body)
            .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
    }
}
