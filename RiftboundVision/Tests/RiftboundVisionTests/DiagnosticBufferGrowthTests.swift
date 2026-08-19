import Testing
import CoreGraphics
import Foundation
@testable import RiftboundVision
import RiftboundExpertSystem

/// The app got slower the longer a game ran. These pin the collections that
/// caused it — ones that only ever grew, so nothing was wrong on the first
/// frame and everything was wrong an hour in.
@Suite("Diagnostic Buffer Growth")
struct DiagnosticBufferGrowthTests {

    private func square(_ minX: CGFloat, _ minY: CGFloat, _ size: CGFloat = 50) -> [CGPoint] {
        [CGPoint(x: minX, y: minY), CGPoint(x: minX + size, y: minY),
         CGPoint(x: minX + size, y: minY + size), CGPoint(x: minX, y: minY + size)]
    }

    private func card(at point: CGPoint) -> Detection {
        Detection(
            type: .card, center: point,
            boundingBox: CGRect(x: point.x - 10, y: point.y - 15, width: 20, height: 30),
            rotation: 0, confidence: 0.95
        )
    }

    /// `unrepresentableZoneEvents` records what translation dropped, which
    /// is a useful diagnostic and a terrible unbounded list: a card between
    /// calibrated zones resolves to `.unknown` and lands here, so it fills
    /// at about the rate hands move over the mat.
    ///
    /// Driven far past the cap with detections that never land in a
    /// calibrated zone — the "off the mat" case, which is exactly what a
    /// player's hand crossing the camera produces.
    @Test("Dropped-event diagnostics stop growing at the cap")
    func unrepresentableEventsAreCapped() {
        let adapter = ExpertSystemAdapter(
            zoneMapper: ZoneMapper(zones: [
                BoardZone(type: .player1Hand, polygon: square(0, 0), owner: .player1)
            ]),
            playerCalibration: [.player1: PlayerID()],
            tracker: ObjectTracker(matchDistanceThreshold: 5)
        )

        // Each pass puts a card somewhere off every calibrated zone, then
        // takes it away, which produces appear/disappear events that can't
        // be translated.
        for pass in 0..<(ExpertSystemAdapter.diagnosticBufferLimit * 3) {
            let away = CGPoint(x: 5000 + CGFloat(pass) * 100, y: 5000)
            adapter.ingest(detections: [card(at: away)], frameIndex: pass * 4, timestamp: Double(pass) * 0.2)
            adapter.ingest(detections: [card(at: away)], frameIndex: pass * 4 + 1, timestamp: Double(pass) * 0.2 + 0.05)
            adapter.ingest(detections: [], frameIndex: pass * 4 + 2, timestamp: Double(pass) * 0.2 + 0.1)
            adapter.ingest(detections: [], frameIndex: pass * 4 + 3, timestamp: Double(pass) * 0.2 + 0.15)
        }

        // Exactly the cap, not merely under it: the run generates far
        // more droppable events than that, so a passing `<=` could also
        // mean the test never exercised the path at all.
        #expect(adapter.unrepresentableZoneEvents.count == ExpertSystemAdapter.diagnosticBufferLimit)
    }

    /// The vision trace is the same shape of diagnostic and was already
    /// capped — checked alongside so the pair can't drift apart.
    @Test("The vision trace stops growing at the same cap")
    func visionTraceIsCapped() {
        let adapter = ExpertSystemAdapter(
            zoneMapper: ZoneMapper(zones: [
                BoardZone(type: .player1Hand, polygon: square(0, 0), owner: .player1)
            ]),
            playerCalibration: [.player1: PlayerID()],
            tracker: ObjectTracker(matchDistanceThreshold: 5)
        )

        for pass in 0..<(ExpertSystemAdapter.diagnosticBufferLimit * 3) {
            let away = CGPoint(x: 5000 + CGFloat(pass) * 100, y: 5000)
            adapter.ingest(detections: [card(at: away)], frameIndex: pass * 4, timestamp: Double(pass) * 0.2)
            adapter.ingest(detections: [], frameIndex: pass * 4 + 2, timestamp: Double(pass) * 0.2 + 0.1)
            adapter.ingest(detections: [], frameIndex: pass * 4 + 3, timestamp: Double(pass) * 0.2 + 0.15)
        }

        #expect(adapter.drainVisionTrace().count == ExpertSystemAdapter.diagnosticBufferLimit)
    }

    /// Cards appearing and vanishing over and over is the ordinary case —
    /// a hand passing over the mat does it — and each cycle used to leave
    /// state behind keyed by an ID that would never be seen again.
    ///
    /// Asserted through the tracker's public surface: what must not grow is
    /// the live set, whatever bookkeeping sits behind it.
    @Test("Churning tracks don't accumulate live state")
    func churningTracksDoNotAccumulate() {
        let tracker = ObjectTracker(occlusionToleranceFrames: 1, matchDistanceThreshold: 5)
        let zones = ZoneMapper(zones: [BoardZone(type: .base, polygon: square(0, 0, 4000))])

        var previous: TimeInterval?
        func step(_ detections: [Detection], _ frame: Int) {
            let now = Double(frame) * 0.2
            _ = tracker.update(
                detections: detections, zoneMapper: zones,
                frameIndex: frame, timestamp: now, previousTimestamp: previous
            )
            previous = now
        }

        for pass in 0..<300 {
            let point = CGPoint(x: CGFloat(pass % 7) * 500 + 50, y: 50)
            step([card(at: point)], pass * 3)
            step([], pass * 3 + 1)
            step([], pass * 3 + 2)
        }

        let now = 10_000 * 0.2
        let live = tracker.update(
            detections: [], zoneMapper: zones,
            frameIndex: 10_000, timestamp: now, previousTimestamp: previous
        )
        #expect(live.objects.isEmpty, "Every track should have timed out by now.")
    }
}
