import Testing
import Foundation
@testable import RiftboundExpertSystem

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
        metrics.record(.unrecognized, reason: "card not recognized")
        metrics.record(.unrecognized, reason: "card not recognized")
        metrics.record(.unrecognized, reason: "card type not handled")
        metrics.record(.rejected, reason: "Card not in hand")

        let unrecognized = metrics.reasons(for: .unrecognized)
        #expect(unrecognized.first?.reason == "card not recognized")
        #expect(unrecognized.first?.count == 2)
        #expect(unrecognized.count == 2)
        // A rejection reason must not leak into the unrecognized table.
        #expect(metrics.reasons(for: .rejected).map(\.reason) == ["Card not in hand"])
    }

    /// 4.4.3's denominator is every observed event, not just those that
    /// produced an instruction.
    @Test("The unrecognized share is measured against observed events")
    func shareUsesObservedEvents() {
        let metrics = PipelineMetrics()
        for _ in 0..<10 { metrics.recordObservedEvent() }
        metrics.record(.unrecognized, reason: "card not recognized")
        metrics.record(.unrecognized, reason: "card not recognized")

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
        metrics.recordUnknownZone(cause: "card at the table edge")
        metrics.recordUnknownZone(cause: "card at the table edge")
        metrics.recordUnknownZone(cause: "calibration off")

        #expect(metrics.unknownZones.first?.cause == "card at the table edge")
        #expect(metrics.unknownZones.first?.count == 2)
    }

    /// 4.4.4's second column. The marks are made by hand mid-session, so
    /// the one thing that must hold is that un-marking a mis-tap takes the
    /// count back down — and never below zero.
    @Test("A false-rejection mark can be undone, and never goes negative")
    func falseRejectionsAreReversible() {
        let metrics = PipelineMetrics()
        metrics.recordFalseRejection(reason: "Not enough Energy")
        metrics.recordFalseRejection(reason: "Not enough Energy")
        #expect(metrics.falseRejectionCount(reason: "Not enough Energy") == 2)

        metrics.undoFalseRejection(reason: "Not enough Energy")
        #expect(metrics.falseRejectionCount(reason: "Not enough Energy") == 1)

        metrics.undoFalseRejection(reason: "Not enough Energy")
        metrics.undoFalseRejection(reason: "Not enough Energy")
        #expect(metrics.falseRejectionCount(reason: "Not enough Energy") == 0)
        // Dropped entirely rather than left as a zero row, so the export
        // doesn't carry reasons nobody ever marked.
        #expect(metrics.markedFalseRejections.isEmpty)
        // Undoing a reason that was never marked must not invent one.
        metrics.undoFalseRejection(reason: "never marked")
        #expect(metrics.falseRejectionCount(reason: "never marked") == 0)
    }

    /// Every rejection reason the CSV reports must carry its mark count in
    /// the same row — that pairing is the whole of 4.4.4.
    ///
    /// Also pins the translation boundary: the label goes in in English,
    /// which is what the app records and shows, and comes out of the export
    /// in Indonesian, which is what the thesis is written in.
    @Test("The CSV pairs each rejection reason with its false-rejection count")
    func csvPairsRejectionsWithMarks() {
        let metrics = PipelineMetrics()
        metrics.record(.rejected, reason: "Not enough Energy")
        metrics.record(.rejected, reason: "Not enough Energy")
        metrics.recordFalseRejection(reason: "Not enough Energy")

        let row = metrics.csvReport()
            .split(separator: "\n")
            .first { $0.hasPrefix("4.4.4 penolakan") }
        #expect(row == "4.4.4 penolakan,\"Energy tidak cukup\",2,1,")
    }

    /// Every stage heading and every fixed label must have an Indonesian
    /// form, or a row reaches the thesis in the wrong language.
    ///
    /// A free-text translator note has no fixed form and passes through —
    /// that is the documented default, not a miss.
    @Test("Every fixed label has an Indonesian form for the export")
    func everyFixedLabelTranslates() {
        for stage in PipelineMetrics.Stage.allCases {
            #expect(stage.indonesian != stage.rawValue, "\(stage) has no Indonesian heading")
        }

        let fixed = [
            PipelineMetrics.Reason.nlpStageOff,
            PipelineMetrics.Reason.noMatchingAction,
            PipelineMetrics.UnknownZoneCause.noZoneOnEvent,
            PipelineMetrics.UnknownZoneCause.ownerNotCalibrated,
            PipelineMetrics.UnknownZoneCause.battlefieldSlotNotCalibrated,
            PipelineMetrics.UnknownZoneCause.outsideCalibratedZones
        ]
        for label in fixed {
            #expect(PipelineMetrics.indonesian(for: label) != label, "\(label) is untranslated")
        }

        // Every validator failure too. Listed by hand because `Failure`
        // carries associated values and so has no `allCases` — which is
        // exactly why this is worth pinning: a new case added to the
        // validator gets a `category` the compiler demands, and an
        // Indonesian form nothing would otherwise ask for.
        let failures: [LegalityValidator.Failure] = [
            .notPlayersPriority,
            .unitAlreadyExhausted(ObjectID()),
            .unitNotFound(ObjectID()),
            .destinationOccupiedByTwoOtherControllers(BattlefieldID()),
            .moveOriginsMismatch,
            .cardNotInHand(ObjectID()),
            .invalidPlayDestination(.none),
            .insufficientEnergy(required: 1, available: 0),
            .insufficientPower(required: 1, available: 0),
            .exhaustedRuneCountMismatch(required: 1, observed: 0),
            .reactionRequired,
            .actionOrReactionRequired,
            .limitedActionNotAuthorized(.draw(count: 1)),
            .notActionPhase(.startOfTurn(.awaken)),
            .illegalMoveDestination(from: .base(PlayerID()), to: .base(PlayerID())),
            .noRuneOfDomainAvailable(.fury),
            .gameAlreadyWon(PlayerID()),
            .notImplemented
        ]
        for failure in failures {
            let category = failure.category
            #expect(
                PipelineMetrics.indonesian(for: category) != category,
                "\(category) has no Indonesian form"
            )
        }

        // Unknown text is returned unchanged, deliberately.
        #expect(PipelineMetrics.indonesian(for: "some translator note") == "some translator note")
    }

    /// Two rules with the same shape must stay one row each, not merge.
    @Test("Failure categories drop their associated values but stay distinct")
    func failureCategoriesGroup() {
        #expect(
            LegalityValidator.Failure.insufficientEnergy(required: 3, available: 2).category
            == LegalityValidator.Failure.insufficientEnergy(required: 9, available: 0).category
        )
        #expect(
            LegalityValidator.Failure.insufficientEnergy(required: 3, available: 2).category
            != LegalityValidator.Failure.insufficientPower(required: 3, available: 2).category
        )
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
