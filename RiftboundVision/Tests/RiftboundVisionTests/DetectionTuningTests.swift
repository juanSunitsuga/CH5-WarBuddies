import Testing
import CoreGraphics
import Foundation
@testable import RiftboundVision

/// The tuning's one piece of real logic is the aspect range, and getting it
/// wrong traps at runtime rather than returning something wrong — the two
/// bounds are edited separately, so an inverted pair is a normal moment
/// between edits, not an error.
@Suite("Detection Tuning")
struct DetectionTuningTests {

    @Test("An inverted aspect pair still produces a valid range")
    func invertedBoundsAreSorted() {
        var tuning = DetectionTuning.default
        tuning.aspectRatioLowerBound = 1.9
        tuning.aspectRatioUpperBound = 1.3

        #expect(tuning.aspectRatioRange == 1.3...1.9)
    }

    @Test("Equal bounds are a single-value range, not a trap")
    func equalBoundsAreAllowed() {
        var tuning = DetectionTuning.default
        tuning.aspectRatioLowerBound = 1.4
        tuning.aspectRatioUpperBound = 1.4

        #expect(tuning.aspectRatioRange == 1.4...1.4)
    }

    /// The defaults have to match the properties they feed, or turning the
    /// debugger on would silently change how the app behaves.
    @Test("The defaults are the values the pipeline already used")
    func defaultsMatchThePipeline() {
        let tuning = DetectionTuning.default
        #expect(tuning.minimumConfidence == 0.75)
        #expect(tuning.aspectRatioRange == 1.2...1.8)
        #expect(tuning.matchRadiusInCardLengths == 1.2)
        #expect(tuning.occlusionToleranceFrames == 15)
        #expect(tuning.labelCommitThreshold == 6.0)
        #expect(tuning.confirmationFrames == 2)
    }

    /// Persistence is a JSON round trip, and a value that failed to decode
    /// would silently fall back to the defaults — a run measured under
    /// settings nobody chose.
    @Test("A tuning survives a JSON round trip unchanged")
    func roundTripsThroughJSON() throws {
        var tuning = DetectionTuning.default
        tuning.minimumConfidence = 0.4
        tuning.occlusionToleranceFrames = 40
        tuning.confirmationFrames = 5

        let data = try JSONEncoder().encode(tuning)
        #expect(try JSONDecoder().decode(DetectionTuning.self, from: data) == tuning)
    }

    /// Both detectors take the tuning, so a run made on the geometric
    /// fallback doesn't quietly ignore two of the six settings.
    @Test("The fallback detector takes the tuning too")
    func fallbackDetectorAppliesTuning() {
        var detector = VisionRectangleDetector()
        var tuning = DetectionTuning.default
        tuning.minimumConfidence = 0.3
        tuning.aspectRatioLowerBound = 1.1
        tuning.aspectRatioUpperBound = 2.0

        detector.applyTuning(tuning)

        #expect(detector.minimumConfidence == 0.3)
        #expect(detector.cardAspectRatioRange == 1.1...2.0)
    }

    /// Changed in place rather than rebuilt, because rebuilding the tracker
    /// would throw away every live track.
    @Test("Tracking parameters are settable on a live tracker")
    func trackerParametersAreSettable() {
        let tracker = ObjectTracker()
        tracker.matchRadiusInCardLengths = 2.5
        tracker.occlusionToleranceFrames = 30
        tracker.labelCommitThreshold = 9

        #expect(tracker.matchRadiusInCardLengths == 2.5)
        #expect(tracker.occlusionToleranceFrames == 30)
        #expect(tracker.labelCommitThreshold == 9)
    }
}
