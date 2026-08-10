import CoreGraphics
import Foundation

/// Turns a stream of per-frame `TrackerUpdateResult`s into confirmed
/// `VisionEvent`s. This is where "do not generate an event from a single
/// frame" actually lives: a zone or rotation change must hold steady for
/// `confirmationFrames` consecutive frames before it's reported, so a
/// card passing through `.unknown` mid-move (occluded by a hand, or
/// between two calibrated polygons) doesn't itself produce spurious
/// events — only the eventual settled zone does.
/// `@unchecked Sendable`: same single-writer contract as `ObjectTracker` —
/// `process(...)` must be called strictly in frame order by one caller.
public final class TemporalEventDetector: @unchecked Sendable {
    private struct ObjectHistory {
        /// The last zone actually reported to the Expert System layer via
        /// a confirmed `.objectMoved` event (or the zone the object first
        /// appeared in, for objects never yet reported as moved).
        var confirmedZone: Zone
        /// The zone/rotation currently being observed, and how many
        /// consecutive frames it's held — reset whenever the raw reading
        /// changes.
        var candidateZone: Zone
        var candidateZoneStreak: Int
        var confirmedRotationBucket: Int
        var candidateRotationBucket: Int
        var candidateRotationStreak: Int
        var hasReportedAppearance: Bool
        /// Which seat this object belongs to, per the last zone it was
        /// seen in that actually had an owner. Carried forward through
        /// physically-neutral zones (Battlefield, Rune Area) rather than
        /// re-derived from the current zone each time — a card sitting on
        /// a shared Battlefield still belongs to whoever played it.
        var owner: Player?
    }

    private var history: [TrackedObjectID: ObjectHistory] = [:]

    /// Consecutive frames a candidate zone/rotation must hold before it's
    /// confirmed and reported. Matches the brief's worked example (2
    /// stable frames after the transitional `.unknown` frames).
    public let confirmationFrames: Int
    /// Rotation is bucketed to the nearest multiple of this many degrees
    /// before comparison — raw per-frame rotation jitter shouldn't cause
    /// spurious `.objectRotated` events. 90° matches Exhaust/Ready, which
    /// is the only rotation state this layer currently cares about
    /// (591–593); finer-grained rotation tracking can lower this later.
    public let rotationBucketDegrees: CGFloat

    public init(confirmationFrames: Int = 2, rotationBucketDegrees: CGFloat = 90) {
        self.confirmationFrames = confirmationFrames
        self.rotationBucketDegrees = rotationBucketDegrees
    }

    private func rotationBucket(_ radians: CGFloat) -> Int {
        let degrees = radians * 180 / .pi
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        return Int((positive / rotationBucketDegrees).rounded()) % Int(360 / rotationBucketDegrees)
    }

    /// Feed one frame's tracker output in; returns however many confirmed
    /// `VisionEvent`s resulted (usually zero — most frames confirm
    /// nothing new).
    ///
    /// `zoneMapper` is used to resolve *which physical instance* of a zone
    /// an object settled in (e.g. Player 1's Base vs Player 2's Base both
    /// report `Zone.base` — `BoardZone.owner`/`battlefieldSlot` is what
    /// disambiguates them), re-queried at confirmation time rather than
    /// carried on `TrackedObject` since `Zone` alone is ambiguous for
    /// per-player/per-Battlefield zones.
    public func process(_ result: TrackerUpdateResult, zoneMapper: ZoneMapper, timestamp: TimeInterval) -> [VisionEvent] {
        var events: [VisionEvent] = []
        let objectsByID = Dictionary(uniqueKeysWithValues: result.objects.map { ($0.id, $0) })

        for object in result.objects {
            let rawRotationBucket = rotationBucket(object.rotation)
            let currentBoardZone = zoneMapper.boardZone(for: object.center)

            guard var record = history[object.id] else {
                // First time this ID has been observed by this detector —
                // start its history but don't emit `.objectAppeared` here;
                // that's gated on `result.appearedIDs` below so a track
                // that's actually a re-match (matched by the tracker
                // after occlusion) never double-fires appearance.
                history[object.id] = ObjectHistory(
                    confirmedZone: object.currentZone,
                    candidateZone: object.currentZone,
                    candidateZoneStreak: 1,
                    confirmedRotationBucket: rawRotationBucket,
                    candidateRotationBucket: rawRotationBucket,
                    candidateRotationStreak: 1,
                    hasReportedAppearance: false,
                    owner: currentBoardZone?.owner ?? object.currentZone.impliedOwner
                )
                continue
            }

            if let resolvedOwner = currentBoardZone?.owner ?? object.currentZone.impliedOwner {
                record.owner = resolvedOwner
            }

            // --- Zone confirmation ---
            if object.currentZone == record.candidateZone {
                record.candidateZoneStreak += 1
            } else {
                record.candidateZone = object.currentZone
                record.candidateZoneStreak = 1
            }
            if record.candidateZoneStreak >= confirmationFrames,
               record.candidateZone != record.confirmedZone,
               record.candidateZone != .unknown {
                events.append(VisionEvent(
                    type: .objectMoved,
                    objectID: object.id,
                    objectType: object.type,
                    player: record.owner,
                    previousZone: record.confirmedZone,
                    currentZone: record.candidateZone,
                    battlefieldSlot: currentBoardZone?.battlefieldSlot,
                    previousPosition: nil,
                    currentPosition: object.center,
                    previousRotation: nil,
                    currentRotation: nil,
                    timestamp: timestamp,
                    confidence: object.confidence
                ))
                record.confirmedZone = record.candidateZone
            }

            // --- Rotation confirmation ---
            if rawRotationBucket == record.candidateRotationBucket {
                record.candidateRotationStreak += 1
            } else {
                record.candidateRotationBucket = rawRotationBucket
                record.candidateRotationStreak = 1
            }
            if record.candidateRotationStreak >= confirmationFrames,
               record.candidateRotationBucket != record.confirmedRotationBucket {
                let previousRadians = CGFloat(record.confirmedRotationBucket) * rotationBucketDegrees * .pi / 180
                let currentRadians = CGFloat(record.candidateRotationBucket) * rotationBucketDegrees * .pi / 180
                events.append(VisionEvent(
                    type: .objectRotated,
                    objectID: object.id,
                    objectType: object.type,
                    player: record.owner,
                    previousZone: object.currentZone,
                    currentZone: object.currentZone,
                    battlefieldSlot: currentBoardZone?.battlefieldSlot,
                    previousPosition: nil,
                    currentPosition: nil,
                    previousRotation: previousRadians,
                    currentRotation: currentRadians,
                    timestamp: timestamp,
                    confidence: object.confidence
                ))
                record.confirmedRotationBucket = record.candidateRotationBucket
            }

            history[object.id] = record
        }

        for id in result.appearedIDs {
            guard let object = objectsByID[id], var record = history[id], !record.hasReportedAppearance else { continue }
            record.hasReportedAppearance = true
            history[id] = record
            let boardZone = zoneMapper.boardZone(for: object.center)
            events.append(VisionEvent(
                type: .objectAppeared,
                objectID: id,
                objectType: object.type,
                player: record.owner,
                previousZone: nil,
                currentZone: object.currentZone,
                battlefieldSlot: boardZone?.battlefieldSlot,
                previousPosition: nil,
                currentPosition: object.center,
                previousRotation: nil,
                currentRotation: object.rotation,
                timestamp: timestamp,
                confidence: object.confidence
            ))
        }

        for id in result.disappearedIDs {
            let lastKnownZone = history[id]?.confirmedZone
            let lastKnownOwner = history[id]?.owner
            history.removeValue(forKey: id)
            events.append(VisionEvent(
                type: .objectDisappeared,
                objectID: id,
                objectType: .unknown,
                player: lastKnownOwner,
                previousZone: lastKnownZone,
                currentZone: nil,
                previousPosition: nil,
                currentPosition: nil,
                previousRotation: nil,
                currentRotation: nil,
                timestamp: timestamp,
                confidence: 0
            ))
        }

        return events
    }
}
