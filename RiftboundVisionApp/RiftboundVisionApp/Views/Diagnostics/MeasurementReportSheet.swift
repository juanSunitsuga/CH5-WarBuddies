import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RiftboundExpertSystem

/// The four measurements the thesis's Subbab 4.4 reports, as the app sees
/// them right now.
///
/// Exists because those tables were being filled in by hand from the
/// console. Numbers copied by eye are numbers nobody can re-derive, which
/// is the opposite of what a results chapter is for — so the app that
/// produced them exports them.
///
/// Reads the recorder on a timer rather than observing it. `PipelineMetrics`
/// is written from the detection poll, from the engine's actor and from the
/// adapter, several times a second; making it `@Published` would redraw this
/// sheet at detection rate for numbers a human reads once a second at most.
struct MeasurementReportSheet: View {

    @ObservedObject var pipeline: CameraPipelineController
    let onClose: () -> Void

    /// Bumped by the timer, and by the buttons that change the numbers, to
    /// pull fresh values out of the recorder. The value itself is never
    /// read — only the fact that it changed.
    @State private var revision = 0
    @State private var exportError: String?

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var metrics: PipelineMetrics { pipeline.metrics }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    latencySection
                    translationSection
                    rejectionSection
                    unknownZoneSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let exportError {
                Text(exportError)
                    .riftFont(.body)
                    .foregroundStyle(RiftboundPalette.dangerButton)
            }

            footer
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 560)
        .background(RiftboundPalette.mainBackground)
        .onReceive(tick) { _ in revision &+= 1 }
    }

    // MARK: - Header and footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Measurement Report")
                .riftFont(.heading)
                .foregroundStyle(RiftboundPalette.regularText)
            Text("Subbab 4.4 — \(metrics.eventCount) kejadian teramati pada sesi ini.")
                .riftFont(.body)
                .foregroundStyle(RiftboundPalette.regularText)
        }
    }

    private var footer: some View {
        HStack {
            Button("Export CSV…") { export() }
                .buttonStyle(RiftSecondaryButtonStyle())
            Button("Copy CSV") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(csv, forType: .string)
            }
            .buttonStyle(RiftSecondaryButtonStyle())
            Spacer()
            // Destructive and not undoable, so it is the one control here
            // that states what it throws away rather than saying "Reset".
            Button("Discard this session's samples") {
                metrics.reset()
                revision &+= 1
            }
            .buttonStyle(RiftSecondaryButtonStyle())
            Button("Close") { onClose() }
                .buttonStyle(RiftPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - 4.4.2 latency

    private var latencySection: some View {
        section("Tabel 4.28 — Latensi per tahap") {
            grid(columns: ["Tahap", "n", "Rata-rata (ms)", "P95 (ms)"]) {
                ForEach(metrics.allLatencies, id: \.stage) { latency in
                    GridRow {
                        cell(latency.stage.rawValue, leading: true)
                        cell("\(latency.count)")
                        cell(latency.count == 0 ? "—" : String(format: "%.2f", latency.meanMilliseconds))
                        cell(latency.count == 0 ? "—" : String(format: "%.2f", latency.p95Milliseconds))
                    }
                }
            }
        }
    }

    // MARK: - 4.4.3 untranslated

    private var translationSection: some View {
        section("4.4.3 — Kejadian yang tidak berhasil diterjemahkan") {
            VStack(alignment: .leading, spacing: 8) {
                Text(shareLine)
                    .riftFont(.body)
                    .foregroundStyle(RiftboundPalette.regularText)

                let rows = metrics.reasons(for: .unrecognized)
                if rows.isEmpty {
                    emptyLine("Belum ada kejadian yang gagal diterjemahkan.")
                } else {
                    grid(columns: ["Alasan", "Jumlah"]) {
                        ForEach(rows, id: \.reason) { row in
                            GridRow {
                                cell(row.reason, leading: true)
                                cell("\(row.count)")
                            }
                        }
                    }
                }
            }
        }
    }

    private var shareLine: String {
        guard let share = metrics.unrecognizedShare else {
            return "Belum ada kejadian teramati."
        }
        let unrecognized = metrics.count(of: .unrecognized)
        return String(
            format: "%d dari %d kejadian (%.1f%%) tidak menghasilkan aksi. Diterima: %d. Ditolak: %d.",
            unrecognized,
            metrics.eventCount,
            share * 100,
            metrics.count(of: .accepted),
            metrics.count(of: .rejected)
        )
    }

    // MARK: - 4.4.4 rejections

    private var rejectionSection: some View {
        section("4.4.4 — Pelanggaran aturan yang tertangkap") {
            let rows = metrics.reasons(for: .rejected)
            if rows.isEmpty {
                emptyLine("Belum ada aksi yang ditolak validator.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // The second column is the half of 4.4.4 no code can
                    // fill in: the validator already believes every
                    // rejection was right. Only the player who made the
                    // move knows it was legal.
                    Text("Tandai penolakan yang sebenarnya sah — hanya pemain yang tahu.")
                        .riftFont(.body)
                        .foregroundStyle(RiftboundPalette.regularText)

                    grid(columns: ["Alasan penolakan", "Ditolak", "Salah tolak", ""]) {
                        ForEach(rows, id: \.reason) { row in
                            GridRow {
                                cell(row.reason, leading: true)
                                cell("\(row.count)")
                                cell("\(metrics.falseRejectionCount(reason: row.reason))")
                                HStack(spacing: 4) {
                                    Button("−") {
                                        metrics.undoFalseRejection(reason: row.reason)
                                        revision &+= 1
                                    }
                                    .buttonStyle(RiftSecondaryButtonStyle())
                                    .disabled(metrics.falseRejectionCount(reason: row.reason) == 0)
                                    Button("+") {
                                        metrics.recordFalseRejection(reason: row.reason)
                                        revision &+= 1
                                    }
                                    .buttonStyle(RiftSecondaryButtonStyle())
                                    // Marking more wrong rejections than
                                    // there were rejections is not a
                                    // judgement, it is a typo.
                                    .disabled(metrics.falseRejectionCount(reason: row.reason) >= row.count)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 4.4.5 unknown zones

    private var unknownZoneSection: some View {
        section("4.4.5 — Kejadian berzona tidak dikenal") {
            let rows = metrics.unknownZones
            if rows.isEmpty {
                emptyLine("Belum ada kartu yang jatuh di luar zona terkalibrasi.")
            } else {
                grid(columns: ["Penyebab", "Jumlah"]) {
                    ForEach(rows, id: \.cause) { row in
                        GridRow {
                            cell(row.cause, leading: true)
                            cell("\(row.count)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Export

    private var csv: String {
        metrics.csvReport(sessionLabel: pipeline.videoSourceURL?.lastPathComponent ?? "Kamera langsung")
    }

    /// Writes the report where the user picks.
    ///
    /// `NSSavePanel` rather than SwiftUI's `.fileExporter` for the same
    /// reason the video picker uses `NSOpenPanel`: a `.fileExporter`
    /// attached to a sheet that is itself presented from a toolbar control
    /// does not reliably come up.
    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "riftbound-4.4-\(Self.stamp()).csv"
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportError = nil
        } catch {
            // Shown rather than swallowed: a silent failure here means
            // sitting down to write the chapter and finding no file.
            exportError = "Gagal menyimpan: \(error.localizedDescription)"
        }
    }

    /// A sortable timestamp, so several runs in one afternoon don't
    /// overwrite each other in the Downloads folder.
    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    // MARK: - Small pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .riftFont(.subheading)
                .foregroundStyle(RiftboundPalette.regularText)
            content()
        }
    }

    private func grid<Content: View>(columns: [String], @ViewBuilder rows: () -> Content) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, name in
                    Text(name)
                        .riftFont(.body)
                        .foregroundStyle(RiftboundPalette.regularText)
                        .opacity(0.7)
                        .gridColumnAlignment(index == 0 ? .leading : .trailing)
                }
            }
            Divider()
            rows()
        }
    }

    /// Monospaced digits so a column of counts lines up — the same reason
    /// the camera dump is monospaced, applied only to the numbers.
    private func cell(_ text: String, leading: Bool = false) -> some View {
        Text(text)
            .riftFont(.body)
            .monospacedDigit()
            .foregroundStyle(RiftboundPalette.regularText)
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .riftFont(.body)
            .foregroundStyle(RiftboundPalette.regularText)
            .opacity(0.7)
    }
}
