import Foundation

/// Measurements for the thesis's Subbab 4.4 — per-stage latency, events that
/// failed to translate, rule violations caught, and events that landed in
/// `.unknown`.
///
/// Separate from the app's existing `averageDetectionDuration`, which is an
/// exponential moving average used to pace the detector. A moving average
/// cannot produce a P95: it keeps one number, not a distribution, so the
/// 95th percentile is unrecoverable from it by construction. Every duration
/// is therefore kept as a sample here.
///
/// Lives in `RiftboundVision` rather than the app so it can be tested —
/// percentile arithmetic is exactly the kind of thing that is silently wrong
/// by one index.
public final class PipelineMetrics: @unchecked Sendable {

    /// The four stages Tabel 4.28 reports, in pipeline order.
    public enum Stage: String, CaseIterable, Sendable {
        case detection    = "Deteksi & pelacakan"
        case ingestion    = "Ingesti kejadian"
        case translation  = "Terjemahan aksi"
        case validation   = "Validasi & state machine"
    }

    /// How an observed event ended up, for 4.4.3 and 4.4.4.
    public enum Outcome: String, Sendable {
        case accepted
        case rejected
        case unrecognized
    }

    private let lock = NSLock()
    private var samples: [Stage: [Double]] = [:]
    private var outcomes: [Outcome: Int] = [:]
    /// Reason string → count, kept per outcome so "kartu tidak dikenali"
    /// under `.unrecognized` and a validator failure under `.rejected` stay
    /// separate rather than being merged into one table.
    private var reasons: [Outcome: [String: Int]] = [:]
    private var unknownZoneCauses: [String: Int] = [:]
    private var observedEventCount = 0

    /// Samples kept per stage.
    ///
    /// A metrics recorder is meant to accumulate, which is in tension with
    /// "nothing on a per-poll path may grow". The cap resolves it: at six
    /// detections a second this is over two hours of continuous play, and a
    /// P95 has long since stopped moving by then. Once full, the oldest
    /// sample is dropped — a thesis run is measured in minutes, so in
    /// practice nothing is ever dropped at all.
    public static let sampleCap = 50_000

    public init() {}

    // MARK: - Recording

    public func record(_ stage: Stage, seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        lock.lock(); defer { lock.unlock() }
        samples[stage, default: []].append(seconds)
        if samples[stage]!.count > Self.sampleCap {
            samples[stage]!.removeFirst(samples[stage]!.count - Self.sampleCap)
        }
    }

    /// Times `body` and records it. Returns whatever `body` returns, so a
    /// call site becomes a wrapper rather than three extra lines.
    public func measure<T>(_ stage: Stage, _ body: () throws -> T) rethrows -> T {
        let started = CFAbsoluteTimeGetCurrent()
        defer { record(stage, seconds: CFAbsoluteTimeGetCurrent() - started) }
        return try body()
    }

    public func measure<T>(_ stage: Stage, _ body: () async throws -> T) async rethrows -> T {
        let started = CFAbsoluteTimeGetCurrent()
        defer { record(stage, seconds: CFAbsoluteTimeGetCurrent() - started) }
        return try await body()
    }

    /// One observed table event reached the engine. Counted separately from
    /// outcomes so 4.4.3's denominator is the real number of events, not the
    /// number that happened to produce an instruction.
    public func recordObservedEvent() {
        lock.lock(); defer { lock.unlock() }
        observedEventCount += 1
    }

    /// - Parameter reason: the player-facing reason, or `nil` when accepted.
    public func record(_ outcome: Outcome, reason: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        outcomes[outcome, default: 0] += 1
        if let reason, !reason.isEmpty {
            reasons[outcome, default: [:]][reason, default: 0] += 1
        }
    }

    /// An event that couldn't be placed in a zone (4.4.5) — a card at the
    /// table's edge, in a hand, or outside a mis-aimed calibration.
    public func recordUnknownZone(cause: String) {
        lock.lock(); defer { lock.unlock() }
        unknownZoneCauses[cause, default: 0] += 1
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        samples = [:]; outcomes = [:]; reasons = [:]
        unknownZoneCauses = [:]; observedEventCount = 0
    }

    // MARK: - Reading

    public struct StageLatency: Sendable, Equatable {
        public let stage: Stage
        public let count: Int
        /// Milliseconds — the unit Tabel 4.28 reports.
        public let meanMilliseconds: Double
        public let p95Milliseconds: Double
    }

    public func latency(for stage: Stage) -> StageLatency {
        lock.lock(); defer { lock.unlock() }
        let values = samples[stage] ?? []
        guard !values.isEmpty else {
            return StageLatency(stage: stage, count: 0, meanMilliseconds: 0, p95Milliseconds: 0)
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return StageLatency(
            stage: stage,
            count: values.count,
            meanMilliseconds: mean * 1000,
            p95Milliseconds: Self.percentile(values, 0.95) * 1000
        )
    }

    public var allLatencies: [StageLatency] { Stage.allCases.map(latency(for:)) }

    public var eventCount: Int {
        lock.lock(); defer { lock.unlock() }
        return observedEventCount
    }

    public func count(of outcome: Outcome) -> Int {
        lock.lock(); defer { lock.unlock() }
        return outcomes[outcome] ?? 0
    }

    /// Reasons for one outcome, commonest first.
    public func reasons(for outcome: Outcome) -> [(reason: String, count: Int)] {
        lock.lock(); defer { lock.unlock() }
        return (reasons[outcome] ?? [:])
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (reason: $0.key, count: $0.value) }
    }

    public var unknownZones: [(cause: String, count: Int)] {
        lock.lock(); defer { lock.unlock() }
        return unknownZoneCauses
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (cause: $0.key, count: $0.value) }
    }

    /// Share of observed events that failed to translate — 4.4.3's headline.
    /// `nil` rather than zero when nothing has been observed, so an idle run
    /// doesn't report a flattering 0%.
    public var unrecognizedShare: Double? {
        lock.lock(); defer { lock.unlock() }
        guard observedEventCount > 0 else { return nil }
        return Double(outcomes[.unrecognized] ?? 0) / Double(observedEventCount)
    }

    // MARK: - Export

    /// The whole session as CSV, ready to paste into the thesis.
    ///
    /// One file rather than four, with a `bagian` column naming the
    /// sub-section each block belongs to, because the four measurements are
    /// reported together and splitting them into separate exports is how
    /// one of them ends up stale relative to the others.
    ///
    /// Decimal points, not commas, even though the prose uses commas:
    /// a comma inside an unquoted CSV field is a column break, and the
    /// thesis convention is already "titik di dalam kode dan tabel hasil".
    public func csvReport(sessionLabel: String = "") -> String {
        var rows = ["bagian,kunci,n,nilai_1,nilai_2"]

        for latency in allLatencies {
            rows.append([
                "4.4.2 latensi",
                quoted(latency.stage.rawValue),
                String(latency.count),
                String(format: "%.2f", latency.meanMilliseconds),
                String(format: "%.2f", latency.p95Milliseconds)
            ].joined(separator: ","))
        }

        rows.append("4.4.3 kejadian,\(quoted("ObservedTableEvent")),\(eventCount),,")
        for outcome in [Outcome.accepted, .rejected, .unrecognized] {
            rows.append("4.4.3 kejadian,\(quoted(outcome.rawValue)),\(count(of: outcome)),,")
        }
        for entry in reasons(for: .unrecognized) {
            rows.append("4.4.3 alasan,\(quoted(entry.reason)),\(entry.count),,")
        }
        for entry in reasons(for: .rejected) {
            rows.append("4.4.4 penolakan,\(quoted(entry.reason)),\(entry.count),,")
        }
        for entry in unknownZones {
            rows.append("4.4.5 zona unknown,\(quoted(entry.cause)),\(entry.count),,")
        }

        if !sessionLabel.isEmpty {
            rows.insert("# sesi,\(quoted(sessionLabel)),,,", at: 0)
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// Quotes a field and escapes any quote inside it, so a reason
    /// containing a comma — most of them do — stays one column.
    private func quoted(_ field: String) -> String {
        "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Percentile

    /// Nearest-rank percentile: the smallest value at or below which at
    /// least `p` of the samples fall.
    ///
    /// Nearest-rank rather than interpolated, because a reported P95 should
    /// be a latency the system actually produced — an interpolated figure is
    /// a number no frame ever took, which is awkward to defend in a viva.
    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}
