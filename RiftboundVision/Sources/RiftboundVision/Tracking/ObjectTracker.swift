import CoreGraphics
import Foundation

/// One frame's raw output from the detection layer — no identity yet,
/// that's what `ObjectTracker` assigns. Deliberately excludes exact card
/// identity (see `TrackedObject`'s doc comment).
public struct Detection: Sendable {
    public let type: ObjectType
    public let center: CGPoint
    public let boundingBox: CGRect
    public let rotation: CGFloat
    public let confidence: Float

    public init(type: ObjectType, center: CGPoint, boundingBox: CGRect, rotation: CGFloat, confidence: Float) {
        self.type = type
        self.center = center
        self.boundingBox = boundingBox
        self.rotation = rotation
        self.confidence = confidence
    }
}

/// One frame's tracking result: the live objects, plus which IDs are new
/// or were just dropped this frame. Callers (`TemporalEventDetector`) use
/// `appearedIDs`/`disappearedIDs` to gate appearance/disappearance events —
/// a mere occlusion frame produces neither.
public struct TrackerUpdateResult: Sendable {
    public let objects: [TrackedObject]
    public let appearedIDs: [TrackedObjectID]
    public let disappearedIDs: [TrackedObjectID]
}

/// Answers "which physical object is this," not "what card is this."
/// Preserves a stable `TrackedObjectID` across frames using nearest-
/// neighbor matching by position + type, and tolerates short visibility
/// gaps (a hand covering a card) without treating them as
/// disappear-then-reappear — per the brief, an occluded object is neither
/// removed from `tracked` nor reported as an appearance/disappearance
/// candidate until the occlusion tolerance is actually exceeded.
///
/// This class intentionally does not decide zones or emit events — see
/// `ZoneMapper` and `TemporalEventDetector`. Its only job is identity.
///
/// `@unchecked Sendable`: mutable by design (tracking state persists
/// across frames) but not internally synchronized — the contract is one
/// writer, calling `update(...)` strictly in frame order, same as
/// `GameStateStore` requires serialized mutation of `GameState`. Wrap in
/// an actor if frames ever arrive from more than one task concurrently.
public final class ObjectTracker: @unchecked Sendable {
    private var tracked: [TrackedObjectID: TrackedObject] = [:]
    private var nextID: TrackedObjectID = 1

    /// How many consecutive frames an object may go unseen before it's
    /// dropped and reported as disappeared, rather than treated as
    /// occluded.
    public let occlusionToleranceFrames: Int
    /// Maximum center-to-center distance (same units as `Detection.center`)
    /// for a detection to be considered "the same object" as an existing
    /// track. Tune against your calibrated table's pixel/point scale.
    public let matchDistanceThreshold: CGFloat

    public init(occlusionToleranceFrames: Int = 15, matchDistanceThreshold: CGFloat = 60) {
        self.occlusionToleranceFrames = occlusionToleranceFrames
        self.matchDistanceThreshold = matchDistanceThreshold
    }

    /// Feeds one frame's detections in. Must be called once per frame, in
    /// frame order — `frameIndex` should be strictly increasing.
    @discardableResult
    public func update(detections: [Detection], zoneMapper: ZoneMapper, frameIndex: Int, timestamp: TimeInterval, previousTimestamp: TimeInterval?) -> TrackerUpdateResult {
        var remainingDetections = Array(detections.enumerated())
        var matchedTrackIDs = Set<TrackedObjectID>()
        var appearedIDs: [TrackedObjectID] = []

        // Greedy nearest-neighbor matching, same-type only, closest pairs
        // first — good enough for a handful of tabletop objects; revisit
        // with a real assignment algorithm (e.g. Hungarian) only if
        // testing shows greedy matching misassigns under real occlusion.
        var candidatePairs: [(distance: CGFloat, trackID: TrackedObjectID, detectionIndex: Int)] = []
        for (existingID, existing) in tracked {
            for (index, detection) in remainingDetections {
                guard detection.type == existing.type else { continue }
                let distance = hypot(detection.center.x - existing.center.x, detection.center.y - existing.center.y)
                guard distance <= matchDistanceThreshold else { continue }
                candidatePairs.append((distance, existingID, index))
            }
        }
        candidatePairs.sort { $0.distance < $1.distance }

        var claimedDetectionIndices = Set<Int>()
        for pair in candidatePairs {
            guard !matchedTrackIDs.contains(pair.trackID), !claimedDetectionIndices.contains(pair.detectionIndex) else { continue }
            matchedTrackIDs.insert(pair.trackID)
            claimedDetectionIndices.insert(pair.detectionIndex)

            var track = tracked[pair.trackID]!
            let detection = detections[pair.detectionIndex]
            let dt = previousTimestamp.map { timestamp - $0 } ?? 0
            let velocity: CGVector = dt > 0
                ? CGVector(dx: (detection.center.x - track.center.x) / dt, dy: (detection.center.y - track.center.y) / dt)
                : .zero

            track.center = detection.center
            track.boundingBox = detection.boundingBox
            track.rotation = detection.rotation
            track.confidence = detection.confidence
            track.velocity = velocity
            track.isVisible = true
            track.lastSeenFrame = frameIndex
            track.previousZone = track.currentZone
            track.currentZone = zoneMapper.zone(for: detection.center)
            tracked[pair.trackID] = track
        }
        remainingDetections.removeAll { claimedDetectionIndices.contains($0.offset) }

        // Unmatched detections are new objects.
        for (_, detection) in remainingDetections {
            let id = nextID
            nextID += 1
            let zone = zoneMapper.zone(for: detection.center)
            tracked[id] = TrackedObject(
                id: id,
                type: detection.type,
                center: detection.center,
                boundingBox: detection.boundingBox,
                rotation: detection.rotation,
                previousZone: zone,
                currentZone: zone,
                velocity: .zero,
                confidence: detection.confidence,
                isVisible: true,
                lastSeenFrame: frameIndex
            )
            appearedIDs.append(id)
        }

        // Unmatched existing tracks: still-occluded, or finally dropped.
        var disappearedIDs: [TrackedObjectID] = []
        for (id, track) in tracked where !matchedTrackIDs.contains(id) {
            if frameIndex - track.lastSeenFrame > occlusionToleranceFrames {
                disappearedIDs.append(id)
                tracked.removeValue(forKey: id)
            } else {
                var occluded = track
                occluded.isVisible = false
                tracked[id] = occluded
            }
        }

        return TrackerUpdateResult(
            objects: Array(tracked.values),
            appearedIDs: appearedIDs,
            disappearedIDs: disappearedIDs
        )
    }
}
