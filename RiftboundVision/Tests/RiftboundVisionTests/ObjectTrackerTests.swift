import Testing
import CoreGraphics
@testable import RiftboundVision

private func card(at point: CGPoint, rotation: CGFloat = 0) -> Detection {
    Detection(type: .card, center: point, boundingBox: CGRect(x: point.x - 10, y: point.y - 15, width: 20, height: 30), rotation: rotation, confidence: 0.95)
}

private let flatMapper = ZoneMapper(zones: [])

struct ObjectTrackerTests {

    @Test("A stationary object keeps the same ID across frames")
    func stableIdentityAcrossFrames() {
        let tracker = ObjectTracker()
        let first = tracker.update(detections: [card(at: CGPoint(x: 10, y: 10))], zoneMapper: flatMapper, frameIndex: 0, timestamp: 0, previousTimestamp: nil)
        let id = first.objects[0].id

        let second = tracker.update(detections: [card(at: CGPoint(x: 12, y: 11))], zoneMapper: flatMapper, frameIndex: 1, timestamp: 1.0 / 30, previousTimestamp: 0)

        #expect(second.objects.count == 1)
        #expect(second.objects[0].id == id)
    }

    /// Test scenario 8/9 from the brief: multiple cards moving/overlapping
    /// simultaneously must each keep their own identity, not merge or swap.
    @Test("Two simultaneously moving objects each keep a distinct, stable ID")
    func multipleSimultaneousObjectsStayDistinct() {
        let tracker = ObjectTracker()
        let frame0 = tracker.update(
            detections: [card(at: CGPoint(x: 0, y: 0)), card(at: CGPoint(x: 500, y: 500))],
            zoneMapper: flatMapper, frameIndex: 0, timestamp: 0, previousTimestamp: nil
        )
        let idA = frame0.objects.first { $0.center.x < 100 }!.id
        let idB = frame0.objects.first { $0.center.x > 100 }!.id
        #expect(idA != idB)

        // Both move a little, simultaneously, in the same frame.
        let frame1 = tracker.update(
            detections: [card(at: CGPoint(x: 15, y: 10)), card(at: CGPoint(x: 480, y: 490))],
            zoneMapper: flatMapper, frameIndex: 1, timestamp: 1.0 / 30, previousTimestamp: 0
        )

        #expect(frame1.objects.first { $0.center.x < 100 }!.id == idA)
        #expect(frame1.objects.first { $0.center.x > 100 }!.id == idB)
    }

    /// Test scenario 7: a card briefly covered by a hand must not be
    /// treated as disappeared, and must resume the same ID once visible
    /// again — occlusion tolerance from the brief.
    @Test("A short occlusion preserves object identity and does not report disappearance")
    func shortOcclusionPreservesIdentity() {
        let tracker = ObjectTracker(occlusionToleranceFrames: 10)
        let frame0 = tracker.update(detections: [card(at: CGPoint(x: 10, y: 10))], zoneMapper: flatMapper, frameIndex: 0, timestamp: 0, previousTimestamp: nil)
        let id = frame0.objects[0].id

        // Frames 1-3: occluded, no detection at all (hand covering it).
        var lastResult = frame0
        for frame in 1...3 {
            lastResult = tracker.update(detections: [], zoneMapper: flatMapper, frameIndex: frame, timestamp: Double(frame) / 30, previousTimestamp: Double(frame - 1) / 30)
            #expect(lastResult.disappearedIDs.isEmpty)
        }
        #expect(lastResult.objects.first { $0.id == id }?.isVisible == false)

        // Frame 4: visible again at roughly the same spot.
        let frame4 = tracker.update(detections: [card(at: CGPoint(x: 11, y: 9))], zoneMapper: flatMapper, frameIndex: 4, timestamp: 4.0 / 30, previousTimestamp: 3.0 / 30)

        #expect(frame4.objects.count == 1)
        #expect(frame4.objects[0].id == id)
        #expect(frame4.objects[0].isVisible == true)
        #expect(frame4.appearedIDs.isEmpty)
    }

    @Test("An occlusion exceeding tolerance is reported as disappeared, and a later reappearance gets a new ID")
    func longOcclusionReportsDisappearance() {
        let tracker = ObjectTracker(occlusionToleranceFrames: 3)
        let frame0 = tracker.update(detections: [card(at: CGPoint(x: 10, y: 10))], zoneMapper: flatMapper, frameIndex: 0, timestamp: 0, previousTimestamp: nil)
        let originalID = frame0.objects[0].id

        var disappeared: [TrackedObjectID] = []
        for frame in 1...5 {
            let result = tracker.update(detections: [], zoneMapper: flatMapper, frameIndex: frame, timestamp: Double(frame) / 30, previousTimestamp: Double(frame - 1) / 30)
            disappeared.append(contentsOf: result.disappearedIDs)
        }

        #expect(disappeared == [originalID])
    }

    /// A Unit that's settled onto a Battlefield shouldn't be reported
    /// disappeared just because the (comparatively short) default
    /// occlusion tolerance elapsed — `Zone.isPositionallyStable` zones get
    /// `settledOcclusionToleranceFrames` instead, since a card there
    /// genuinely doesn't move.
    @Test("An object settled on a Battlefield survives an occlusion the default tolerance would have dropped")
    func settledZoneObjectSurvivesLongerOcclusion() {
        let battlefieldMapper = ZoneMapper(zones: [
            BoardZone(type: .battlefield, polygon: [
                CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)
            ])
        ])
        let tracker = ObjectTracker(occlusionToleranceFrames: 3, settledOcclusionToleranceFrames: 20)
        let frame0 = tracker.update(detections: [card(at: CGPoint(x: 10, y: 10))], zoneMapper: battlefieldMapper, frameIndex: 0, timestamp: 0, previousTimestamp: nil)
        let id = frame0.objects[0].id
        #expect(frame0.objects[0].currentZone == .battlefield)

        // Occluded for longer than the default tolerance (3) but within
        // the settled tolerance (20) — must not be reported disappeared.
        var lastResult = frame0
        for frame in 1...10 {
            lastResult = tracker.update(detections: [], zoneMapper: battlefieldMapper, frameIndex: frame, timestamp: Double(frame) / 30, previousTimestamp: Double(frame - 1) / 30)
        }

        #expect(lastResult.disappearedIDs.isEmpty)
        #expect(lastResult.objects.first { $0.id == id } != nil)
    }
}
