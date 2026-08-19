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
    /// Fallback maximum center-to-center distance, in pixels, used only
    /// when a detection carries no usable size. See
    /// `matchRadius(for:)` — the real gate scales with the card.
    ///
    /// A fixed pixel budget can't be right at two resolutions at once: 60pt
    /// is generous on a 720p frame and less than half a card on 4K, where
    /// it rejects matches a human would call obvious and forces a new
    /// track instead.
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

    /// Records a discard for a detection that was never tracked, so noting
    /// it costs no `TrackedObjectID`.
    private func noteDiscarded(label: String?, zone: Zone, atFrame frameIndex: Int) {
        guard let label else { return }
        guard !discarded.contains(where: { $0.label == label }) else { return }
        discarded.append(DiscardedObject(id: 0, label: label, zone: zone, discardedAtFrame: frameIndex))
    }

    /// Records a card as discarded, keyed by identity so the same card
    /// re-detected in the pile doesn't pile up duplicate rows.
    private func discard(_ track: TrackedObject, atFrame frameIndex: Int) {
        tracked.removeValue(forKey: track.id)
        discardStreaks[track.id] = nil
        labelVotes[track.id] = nil
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

    /// Cumulative recognizer confidence per label, per track.
    ///
    /// The detector re-runs on every poll and its top label can wobble
    /// between neighbours — the on-screen name and percentage changed
    /// several times a second even for a card lying perfectly still. A
    /// track's identity shouldn't be whatever the last frame happened to
    /// say: votes accumulate, and the label with the most evidence wins.
    /// A momentary misread is outvoted by the history behind it, while a
    /// genuinely different card still takes over once it has been seen
    /// enough times.
    private var labelVotes: [TrackedObjectID: [String: Float]] = [:]

    /// Records this poll's reading and returns the label with the most
    /// accumulated evidence.
    private func stabilizedLabel(
        for id: TrackedObjectID,
        observing label: String?,
        confidence: Float
    ) -> String? {
        guard let label else { return labelVotes[id]?.max(by: { $0.value < $1.value })?.key }
        var votes = labelVotes[id] ?? [:]
        votes[label, default: 0] += confidence
        // Bounded so a long session can't let an early misread become
        // unbeatable, and so a real swap eventually wins.
        if let peak = votes.values.max(), peak > 50 {
            for key in votes.keys { votes[key]! *= 0.5 }
        }
        labelVotes[id] = votes
        return votes.max(by: { $0.value < $1.value })?.key
    }

    /// How far a card may travel between two polls and still be considered
    /// the same card, expressed as a multiple of its own size.
    ///
    /// Scaling with the card rather than using a fixed pixel budget makes
    /// this resolution-independent: a card is about the same fraction of a
    /// frame whatever the camera, so "moved less than about one card
    /// width" means the same thing on 720p and on 4K.
    private func matchRadius(for detection: Detection) -> CGFloat {
        let size = max(detection.boundingBox.width, detection.boundingBox.height)
        guard size > 0 else { return matchDistanceThreshold }
        return max(matchDistanceThreshold, size * matchRadiusInCardLengths)
    }

    /// How many card-lengths of travel to tolerate between polls. Slightly
    /// over one, so a card nudged a little further than its own length
    /// still matches, while two cards a clear gap apart never do.
    private let matchRadiusInCardLengths: CGFloat = 1.2

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
        // Identity is the winner of accumulated votes, not this frame's
        // reading — see `labelVotes`. A `nil` from a non-recognizing
        // detector never erases what's already been established.
        track.recognizedLabel = stabilizedLabel(
            for: trackID,
            observing: detection.recognizedLabel,
            confidence: detection.confidence
        ) ?? track.recognizedLabel
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
                guard distance <= matchRadius(for: detection) else { continue }
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
            let zone = zoneMapper.zone(for: detection.center)

            // A card detected inside a discard zone is never tracked, and
            // — decided *before* an ID is allocated — never consumes one
            // either. Allocating first meant the Trash burned a fresh ID on
            // every detection on every poll: at ~8 Hz that reached four
            // figures within a minute, and a mis-calibrated mat that put
            // ordinary cards in the Trash zone made every card do it.
            if discardZones.contains(zone) {
                noteDiscarded(label: detection.recognizedLabel, zone: zone, atFrame: frameIndex)
                continue
            }

            let id = reclaimedID(for: detection, atFrame: frameIndex) ?? {
                let fresh = nextID
                nextID += 1
                return fresh
            }()

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
                labelVotes[id] = nil
                // Was left behind: `discardStreaks` was only cleared on the
                // discard path, so every track that instead timed out left
                // one entry keyed by an ID that will never be seen again.
                // Small each time, unbounded over a session.
                discardStreaks[id] = nil
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
