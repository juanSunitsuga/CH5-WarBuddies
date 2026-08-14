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
    /// See `TrackedObject.recognizedLabel` — carried through unchanged by
    /// the tracker onto whichever track this detection matches.
    public let recognizedLabel: String?

    public init(type: ObjectType, center: CGPoint, boundingBox: CGRect, rotation: CGFloat, confidence: Float, recognizedLabel: String? = nil) {
        self.type = type
        self.center = center
        self.boundingBox = boundingBox
        self.rotation = rotation
        self.confidence = confidence
        self.recognizedLabel = recognizedLabel
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

    public init(objects: [TrackedObject], appearedIDs: [TrackedObjectID], disappearedIDs: [TrackedObjectID]) {
        self.objects = objects
        self.appearedIDs = appearedIDs
        self.disappearedIDs = disappearedIDs
    }
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
    /// Same idea, but for objects whose current zone is
    /// `Zone.isPositionallyStable` (Battlefield/Rune Area/Rune Deck) — a
    /// much longer grace period, since a card there genuinely doesn't move
    /// and a run of missed detections (e.g. the pipeline's settled-mode
    /// throttle skipping frames entirely, or a hand briefly resting over
    /// it) shouldn't read as "left play." Still finite, not infinite — a
    /// card that's actually been physically removed must eventually be
    /// reported disappeared so its cached identity gets evicted (see
    /// `CameraPipelineController.process(_:)`'s Trash handling) rather
    /// than haunting `tracked` forever.
    public let settledOcclusionToleranceFrames: Int
    /// Maximum center-to-center distance (same units as `Detection.center`)
    /// for a detection to be considered "the same object" as an existing
    /// track. Tune against your calibrated table's pixel/point scale.
    public let matchDistanceThreshold: CGFloat

    public init(
        occlusionToleranceFrames: Int = 15,
        settledOcclusionToleranceFrames: Int = 300,
        matchDistanceThreshold: CGFloat = 60,
        identityMemoryFrames: Int = 1_800,
        discardZones: Set<Zone> = [.trash],
        discardConfirmationFrames: Int = 3
    ) {
        self.occlusionToleranceFrames = occlusionToleranceFrames
        self.settledOcclusionToleranceFrames = settledOcclusionToleranceFrames
        self.matchDistanceThreshold = matchDistanceThreshold
        self.identityMemoryFrames = identityMemoryFrames
        self.discardZones = discardZones
        self.discardConfirmationFrames = discardConfirmationFrames
    }

    /// Records a card as discarded, keyed by identity so the same card
    /// re-detected in the pile doesn't pile up duplicate rows.
    private func discard(_ track: TrackedObject, atFrame frameIndex: Int) {
        tracked.removeValue(forKey: track.id)
        discardStreaks[track.id] = nil
        // Don't let identity memory resurrect it — being in the Trash is
        // the one case where a re-detection should *not* reclaim its ID.
        retired.removeAll { $0.id == track.id }

        if let label = track.recognizedLabel, discarded.contains(where: { $0.label == label }) { return }
        discarded.append(DiscardedObject(
            id: track.id,
            label: track.recognizedLabel,
            zone: track.currentZone,
            discardedAtFrame: frameIndex
        ))
    }

    // MARK: - Identity memory

    /// A track that timed out, remembered by the card it was recognized as.
    private struct RetiredIdentity {
        let id: TrackedObjectID
        let label: String
        let type: ObjectType
        let center: CGPoint
        let retiredAtFrame: Int
    }

    /// Cards whose tracks timed out but whose identity is still worth
    /// keeping.
    ///
    /// Without this, a dropped track erased its identity permanently: a
    /// card the recognizer names with 94% confidence, occluded by a hand
    /// for longer than the tolerance, came back as a brand-new number. On a
    /// nine-card table that produced IDs in the forties — the tracker
    /// wasn't following anything, it was renaming everything. Re-detecting
    /// a card we can *name* should reclaim the number it already had.
    private var retired: [RetiredIdentity] = []

    /// A card that reached a discard zone and is no longer tracked.
    public struct DiscardedObject: Sendable, Equatable, Identifiable {
        public let id: TrackedObjectID
        /// Recognizer label, e.g. `"Noxian Drummer"`. `nil` if the card
        /// reached the Trash without ever being identified.
        public let label: String?
        public let zone: Zone
        public let discardedAtFrame: Int
    }

    /// Cards that have reached a discard zone this session, oldest first.
    public private(set) var discarded: [DiscardedObject] = []

    /// Zones where an object stops being tracked entirely.
    ///
    /// A card in the Trash is out of play: it will sit in that pile for the
    /// rest of the game, and every poll spent following it is work that
    /// buys nothing. Dropping the track also stops the pile from consuming
    /// tracking IDs.
    ///
    /// Detections *inside* a discard zone never create a track at all —
    /// without that rule the pile would mint a fresh ID every poll, which
    /// is worse than tracking it.
    public let discardZones: Set<Zone>

    /// Consecutive polls a card must hold a discard zone before its track
    /// is dropped, so a card passing *over* the Trash on its way somewhere
    /// else isn't retired mid-flight.
    public let discardConfirmationFrames: Int

    /// Tracks currently accumulating time in a discard zone.
    private var discardStreaks: [TrackedObjectID: Int] = [:]

    /// How long a retired identity stays claimable, in polls. Long enough
    /// to survive a hand resting on the table or a card lifted to be read,
    /// bounded so a card genuinely removed from play eventually stops
    /// haunting the store.
    public let identityMemoryFrames: Int

    private func retire(_ track: TrackedObject, atFrame frameIndex: Int) {
        // Only identities worth reclaiming: an unrecognized blob has
        // nothing to match a future detection against.
        guard let label = track.recognizedLabel else { return }
        retired.removeAll { $0.id == track.id }
        retired.append(RetiredIdentity(
            id: track.id,
            label: label,
            type: track.type,
            center: track.center,
            retiredAtFrame: frameIndex
        ))
    }

    /// The ID a reappearing detection should reclaim, if it's recognizably
    /// a card that recently timed out.
    ///
    /// Among several retired copies of the same card the nearest wins, so
    /// two identical Runes can't trade numbers. Never returns an ID that is
    /// currently live.
    private func reclaimedID(for detection: Detection, atFrame frameIndex: Int) -> TrackedObjectID? {
        retired.removeAll { frameIndex - $0.retiredAtFrame > identityMemoryFrames }

        guard let label = detection.recognizedLabel else { return nil }
        let candidates = retired.enumerated().filter { _, entry in
            entry.label == label && entry.type == detection.type && tracked[entry.id] == nil
        }
        guard let best = candidates.min(by: { lhs, rhs in
            hypot(detection.center.x - lhs.element.center.x, detection.center.y - lhs.element.center.y)
                < hypot(detection.center.x - rhs.element.center.x, detection.center.y - rhs.element.center.y)
        }) else { return nil }

        let id = best.element.id
        retired.remove(at: best.offset)
        return id
    }

    /// Folds a matched detection into an existing track, whichever pass
    /// matched it. Shared so identity re-association can't drift out of
    /// step with distance matching — notably `previousZone`/`currentZone`,
    /// which is what makes a zone change observable downstream.
    private func adopt(
        detection: Detection,
        into trackID: TrackedObjectID,
        zoneMapper: ZoneMapper,
        frameIndex: Int,
        timestamp: TimeInterval,
        previousTimestamp: TimeInterval?
    ) {
        guard var track = tracked[trackID] else { return }
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
        // A recognizer's label is trusted the moment it's supplied; a `nil`
        // from a non-recognizing detector should not erase a
        // previously-recognized label for the same physical object.
        if let recognizedLabel = detection.recognizedLabel {
            track.recognizedLabel = recognizedLabel
        }
        tracked[trackID] = track
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
        //
        // Distance is measured to whichever anchor is closer: where the
        // track was last seen, or where its velocity says it should be by
        // now. Velocity was computed and stored but never actually used to
        // match, so a card mid-slide was always compared against a stale
        // position and could outrun the threshold in a single poll. Taking
        // the better of the two keeps prediction from hurting the opposite
        // case, where a moving card stops dead and the prediction
        // overshoots.
        let elapsed = previousTimestamp.map { timestamp - $0 } ?? 0
        var candidatePairs: [(distance: CGFloat, trackID: TrackedObjectID, detectionIndex: Int)] = []
        for (existingID, existing) in tracked {
            let predicted = CGPoint(
                x: existing.center.x + existing.velocity.dx * elapsed,
                y: existing.center.y + existing.velocity.dy * elapsed
            )
            for (index, detection) in remainingDetections {
                guard detection.type == existing.type else { continue }
                let toLastSeen = hypot(detection.center.x - existing.center.x, detection.center.y - existing.center.y)
                let toPredicted = hypot(detection.center.x - predicted.x, detection.center.y - predicted.y)
                let distance = min(toLastSeen, toPredicted)
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
            adopt(
                detection: detections[pair.detectionIndex],
                into: pair.trackID,
                zoneMapper: zoneMapper,
                frameIndex: frameIndex,
                timestamp: timestamp,
                previousTimestamp: previousTimestamp
            )
        }
        remainingDetections.removeAll { claimedDetectionIndices.contains($0.offset) }

        // Second pass: re-associate by card IDENTITY, ignoring distance.
        //
        // Distance matching alone can only follow a card that *slides*
        // across the table. The way a card is actually played — picked up,
        // carried (occluded by the hand), set down somewhere else — moves
        // it far past `matchDistanceThreshold` in a single detection poll,
        // so the track was dropped and a new one created. Downstream that
        // reads as `.objectAppeared` with no origin rather than
        // `.objectMoved(from: hand)`, and an origin-less appearance can't
        // be translated into a Play at all — which meant essentially no
        // real play was ever recognized.
        //
        // The recognizer already tells us *which card* each detection is,
        // so a reappearing card with the same label as a track that just
        // went missing is that same physical card. Restricted to tracks
        // not matched this frame; among several copies of the same card
        // (`recognizedLabel` is a card name, not a per-copy identity) the
        // nearest is taken, which keeps two Fury Runes sitting side by
        // side from swapping identities.
        if !remainingDetections.isEmpty {
            var identityPairs: [(distance: CGFloat, trackID: TrackedObjectID, detectionIndex: Int)] = []
            for (existingID, existing) in tracked where !matchedTrackIDs.contains(existingID) {
                guard let trackLabel = existing.recognizedLabel else { continue }
                for (index, detection) in remainingDetections {
                    guard detection.type == existing.type,
                          detection.recognizedLabel == trackLabel else { continue }
                    let distance = hypot(detection.center.x - existing.center.x, detection.center.y - existing.center.y)
                    identityPairs.append((distance, existingID, index))
                }
            }
            identityPairs.sort { $0.distance < $1.distance }

            var identityClaimed = Set<Int>()
            for pair in identityPairs {
                guard !matchedTrackIDs.contains(pair.trackID), !identityClaimed.contains(pair.detectionIndex) else { continue }
                matchedTrackIDs.insert(pair.trackID)
                identityClaimed.insert(pair.detectionIndex)
                adopt(
                    detection: detections[pair.detectionIndex],
                    into: pair.trackID,
                    zoneMapper: zoneMapper,
                    frameIndex: frameIndex,
                    timestamp: timestamp,
                    previousTimestamp: previousTimestamp
                )
            }
            remainingDetections.removeAll { identityClaimed.contains($0.offset) }
        }

        // Unmatched detections are either a card coming back after its
        // track was retired, or something genuinely new.
        for (_, detection) in remainingDetections {
            let id = reclaimedID(for: detection, atFrame: frameIndex) ?? {
                let fresh = nextID
                nextID += 1
                return fresh
            }()
            let zone = zoneMapper.zone(for: detection.center)

            // A card detected inside a discard zone is never tracked. The
            // Trash pile would otherwise mint a fresh ID every single poll,
            // which costs more than tracking it would.
            if discardZones.contains(zone) {
                discard(
                    TrackedObject(
                        id: id, type: detection.type, center: detection.center,
                        boundingBox: detection.boundingBox, rotation: detection.rotation,
                        previousZone: zone, currentZone: zone, confidence: detection.confidence,
                        isVisible: true, lastSeenFrame: frameIndex,
                        recognizedLabel: detection.recognizedLabel
                    ),
                    atFrame: frameIndex
                )
                continue
            }

            // A brand-new track was, by definition, seen this frame. Without
            // this the occlusion sweep below — which walks every track *not*
            // in `matchedTrackIDs` — immediately marked each new object
            // invisible on its own first frame, so a card was drawn dimmed
            // the moment it appeared and never counted as seen.
            matchedTrackIDs.insert(id)
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
                lastSeenFrame: frameIndex,
                recognizedLabel: detection.recognizedLabel
            )
            appearedIDs.append(id)
        }

        // Cards that have settled in a discard zone stop being tracked.
        // Confirmed over several polls so a card carried *across* the Trash
        // on its way somewhere else isn't retired mid-flight.
        for (id, track) in tracked where matchedTrackIDs.contains(id) {
            guard discardZones.contains(track.currentZone) else {
                discardStreaks[id] = nil
                continue
            }
            let streak = (discardStreaks[id] ?? 0) + 1
            discardStreaks[id] = streak
            if streak >= discardConfirmationFrames {
                discard(track, atFrame: frameIndex)
            }
        }

        // Unmatched existing tracks: still-occluded, or finally dropped.
        var disappearedIDs: [TrackedObjectID] = []
        for (id, track) in tracked where !matchedTrackIDs.contains(id) {
            let tolerance = track.currentZone.isPositionallyStable ? settledOcclusionToleranceFrames : occlusionToleranceFrames
            if frameIndex - track.lastSeenFrame > tolerance {
                disappearedIDs.append(id)
                tracked.removeValue(forKey: id)
                retire(track, atFrame: frameIndex)
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
