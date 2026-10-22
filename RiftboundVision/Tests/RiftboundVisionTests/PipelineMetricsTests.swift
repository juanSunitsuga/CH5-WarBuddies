import Testing
import Foundation
@testable import RiftboundVision

/// These numbers go in a thesis, so the arithmetic has to be right rather
/// than roughly right. Percentiles are off by one index more often than any
/// other small calculation.
@Suite("Pipeline Metrics")
struct PipelineMetricsTests {

    /// 1…100: the 95th percentile by nearest rank is the 95th value.
    @Test("P95 picks the nearest-rank sample, not an interpolated one")
    func p95IsNearestRank() {
        let values = (1...100).map(Double.init)
        #expect(PipelineMetrics.percentile(values, 0.95) == 95)
        #expect(PipelineMetrics.percentile(values, 0.50) == 50)
        #expect(PipelineMetrics.percentile(values, 1.0) == 100)
    }

    /// Order of arrival must not matter.
    @Test("P95 does not depend on the order samples arrived in")
    func p95IgnoresOrder() {
        let ascending = (1...20).map(Double.init)
        #expect(
            PipelineMetrics.percentile(ascending, 0.95)
            == PipelineMetrics.percentile(ascending.shuffled(), 0.95)
        )
    }

    /// The edges, where an off-by-one shows up.
    @Test("P95 holds for one sample and for an empty set")
    func p95Edges() {
        #expect(PipelineMetrics.percentile([], 0.95) == 0)
        #expect(PipelineMetrics.percentile([7], 0.95) == 7)
        #expect(PipelineMetrics.percentile([1, 2], 0.95) == 2)
    }

    @Test("Mean and P95 are reported in milliseconds")
    func reportsMilliseconds() {
        let metrics = PipelineMetrics()
        // 10 ms and 20 ms, in seconds.
        metrics.record(.detection, seconds: 0.010)
        metrics.record(.detection, seconds: 0.020)

        let latency = metrics.latency(for: .detection)
        #expect(latency.count == 2)
        #expect(abs(latency.meanMilliseconds - 15) < 0.001)
        #expect(abs(latency.p95Milliseconds - 20) < 0.001)
    }

    /// A stage nobody recorded reports zero rather than crashing — Tabel
    /// 4.28 has four rows whether or not every stage ran.
    @Test("An unrecorded stage reports zero, and all four stages are listed")
    func unrecordedStageIsZero() {
        let metrics = PipelineMetrics()
        #expect(metrics.latency(for: .validation).count == 0)
        #expect(metrics.allLatencies.count == 4)
        #expect(metrics.allLatencies.map(\.stage) == PipelineMetrics.Stage.allCases)
    }

    @Test("A negative or non-finite duration is refused rather than skewing the mean")
    func rejectsImpossibleDurations() {
        let metrics = PipelineMetrics()
        metrics.record(.detection, seconds: -1)
        metrics.record(.detection, seconds: .nan)
        metrics.record(.detection, seconds: .infinity)

        #expect(metrics.latency(for: .detection).count == 0)
    }

    // MARK: - 4.4.3 / 4.4.4 counts

    @Test("Reasons are grouped per outcome and ordered commonest first")
    func reasonsGroupedAndOrdered() {
        let metrics = PipelineMetrics()
        metrics.record(.unrecognized, reason: "kartu tidak dikenali")
        metrics.record(.unrecognized, reason: "kartu tidak dikenali")
        metrics.record(.unrecognized, reason: "jenis kartu tidak ditangani")
        metrics.record(.rejected, reason: "kartu tidak ada di Hand")

        let unrecognized = metrics.reasons(for: .unrecognized)
        #expect(unrecognized.first?.reason == "kartu tidak dikenali")
        #expect(unrecognized.first?.count == 2)
        #expect(unrecognized.count == 2)
        // A rejection reason must not leak into the unrecognized table.
        #expect(metrics.reasons(for: .rejected).map(\.reason) == ["kartu tidak ada di Hand"])
    }

    /// 4.4.3's denominator is every observed event, not just those that
    /// produced an instruction.
    @Test("The unrecognized share is measured against observed events")
    func shareUsesObservedEvents() {
        let metrics = PipelineMetrics()
        for _ in 0..<10 { metrics.recordObservedEvent() }
        metrics.record(.unrecognized, reason: "kartu tidak dikenali")
        metrics.record(.unrecognized, reason: "kartu tidak dikenali")

        #expect(metrics.eventCount == 10)
        #expect(metrics.unrecognizedShare == 0.2)
    }

    /// An idle run must not report a flattering zero.
    @Test("With no events observed the share is nil, not zero")
    func idleRunReportsNothing() {
        #expect(PipelineMetrics().unrecognizedShare == nil)
    }

    @Test("Unknown-zone causes are counted and ordered")
    func unknownZoneCauses() {
        let metrics = PipelineMetrics()
        metrics.recordUnknownZone(cause: "kartu di tepi meja")
        metrics.recordUnknownZone(cause: "kartu di tepi meja")
        metrics.recordUnknownZone(cause: "kalibrasi meleset")

        #expect(metrics.unknownZones.first?.cause == "kartu di tepi meja")
        #expect(metrics.unknownZones.first?.count == 2)
    }

    @Test("Reset clears everything, for a fresh session")
    func resetClears() {
        let metrics = PipelineMetrics()
        metrics.record(.detection, seconds: 0.01)
        metrics.recordObservedEvent()
        metrics.record(.rejected, reason: "x")
        metrics.recordUnknownZone(cause: "y")

        metrics.reset()

        #expect(metrics.latency(for: .detection).count == 0)
        #expect(metrics.eventCount == 0)
        #expect(metrics.count(of: .rejected) == 0)
        #expect(metrics.unknownZones.isEmpty)
    }

    @Test("measure records the time the body took")
    func measureRecords() {
        let metrics = PipelineMetrics()
        let result = metrics.measure(.translation) {
            Thread.sleep(forTimeInterval: 0.02)
            return 42
        }

        #expect(result == 42)
        #expect(metrics.latency(for: .translation).count == 1)
        #expect(metrics.latency(for: .translation).meanMilliseconds >= 15)
    }
}
