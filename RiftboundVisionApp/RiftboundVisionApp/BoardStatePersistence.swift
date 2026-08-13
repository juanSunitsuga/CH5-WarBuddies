import Foundation
import SwiftData
import RiftboundVision

/// Mirrors the tracked board into SwiftData, and removes a card once it has
/// settled in the Trash.
///
/// Extracted from `CameraPipelineController`, which had grown to own the
/// camera, detection, tracking, the rules engine, the logs, *and* this. The
/// controller's job is to sequence the pipeline; deciding what a durable row
/// should look like is a separate concern with its own rules (dirty
/// checking, trash confirmation, a row cache) and no reason to share state
/// with the rest.
///
/// Consumes tracked objects rather than raw detections on purpose: this used
/// to run its own second `ObjectTracker` over the same frames, so the app
/// carried two independent sets of `TrackedObjectID`s — the ones drawn on
/// screen and the ones written to disk were different numbers for the same
/// physical card, and only one of them followed the live calibration.
@MainActor
final class BoardStatePersistence {
    private let context: ModelContext
    private let cardDatabase: CardDatabase
    private let underlayResolver = UnderlayResolver()

    /// Rows already known this session, so the steady state is a dictionary
    /// hit rather than a fetch per card per poll.
    private var persistedCards: [TrackedObjectID: PersistentTrackedCard] = [:]
    /// Consecutive polls each card has been seen in the Trash. A card only
    /// gets deleted after `trashConfirmationPolls`, so a hand passing over
    /// the trash zone can't wipe the board.
    private var trashPollCounts: [TrackedObjectID: Int] = [:]
    private let trashConfirmationPolls = 3

    init(context: ModelContext, cardDatabase: CardDatabase) {
        self.context = context
        self.cardDatabase = cardDatabase
    }

    /// Result of one poll: whatever the underlay pass flagged as physically
    /// impossible stacking, for the caller to surface.
    struct SyncResult {
        let illegalOverlaps: [IllegalOverlap]
    }

    /// Mirrors this poll's cards into the store.
    ///
    /// - Parameters:
    ///   - objects: the tracker's current objects — the *same* ones the
    ///     overlay draws, so screen and disk agree on identity.
    ///   - disappearedIDs: tracks dropped this poll; their bookkeeping is
    ///     released, though the row is left as last-known state. Only
    ///     settling in the Trash deletes a row.
    ///   - zoneMapper: built from the live calibration by the caller.
    @discardableResult
    func sync(
        objects: [TrackedObject],
        disappearedIDs: [TrackedObjectID],
        zoneMapper: ZoneMapper
    ) -> SyncResult {
        // The tracker knows geometry; card *roles* come from what the
        // detector recognized, resolved against the card database here.
        let resolution = underlayResolver.resolve(objects) { [self] id in
            role(for: id, in: objects)
        }

        for id in disappearedIDs {
            trashPollCounts[id] = nil
            persistedCards[id] = nil
        }

        for object in resolution.objects where object.type == .card {
            let zone = zoneMapper.zone(for: object.center)

            if zone == .trash {
                let count = (trashPollCounts[object.id] ?? 0) + 1
                trashPollCounts[object.id] = count
                if count >= trashConfirmationPolls {
                    delete(trackingID: object.id)
                    trashPollCounts[object.id] = nil
                    continue
                }
            } else {
                trashPollCounts[object.id] = nil
            }

            upsert(object, in: resolution.objects, zone: zone)
        }

        return SyncResult(illegalOverlaps: resolution.illegalOverlaps)
    }

    /// Forgets this session's caches. The rows stay on disk — they're
    /// last-known board state, not scratch data.
    func reset() {
        persistedCards = [:]
        trashPollCounts = [:]
    }

    // MARK: - Card identity

    /// The coarse stacking role `UnderlayResolver` needs, via the
    /// recognizer's class label. `.unknown` while nothing has recognized the
    /// card yet, which the resolver treats as "never link, never flag."
    private func role(for id: TrackedObjectID, in objects: [TrackedObject]) -> CardRole {
        guard let printing = printing(for: id, in: objects) else { return .unknown }
        switch printing.classification.type {
        case "Unit": return .unit
        case "Gear", "Rune": return .attachment
        default: return .other
        }
    }

    private func printing(for id: TrackedObjectID, in objects: [TrackedObject]) -> CardPrinting? {
        guard let label = objects.first(where: { $0.id == id })?.recognizedLabel else { return nil }
        return cardDatabase.printing(approximatelyNamed: label)
    }

    // MARK: - Store writes

    /// Insert-or-update one row, saving only when a field actually changed —
    /// cards sitting still shouldn't churn the disk every poll.
    private func upsert(_ object: TrackedObject, in objects: [TrackedObject], zone: Zone) {
        let printing = printing(for: object.id, in: objects)
        let zoneRaw = zone.rawValue
        // Prefer the printing-aware Exhaust check once the card is
        // recognized: a Battlefield is printed landscape and would read as
        // permanently tapped under the geometry-only fallback.
        let stance: CardStance = printing.map {
            $0.isExhausted(observedBoundingBox: object.boundingBox) ? .exhausted : .ready
        } ?? object.stance
        let orientationRaw = stance.rawValue
        let underlaid = object.underlaidCardIDs

        guard let card = existingCard(for: object.id) else {
            let inserted = PersistentTrackedCard(
                trackingID: object.id,
                cardID: printing?.riftboundID,
                displayName: printing?.name,
                zoneRaw: zoneRaw,
                orientationRaw: orientationRaw,
                zIndex: object.zIndex,
                underlaidTrackingIDs: underlaid,
                lastSeenFrame: object.lastSeenFrame
            )
            context.insert(inserted)
            persistedCards[object.id] = inserted
            save()
            return
        }

        let changed = card.cardID != printing?.riftboundID
            || card.displayName != printing?.name
            || card.zoneRaw != zoneRaw
            || card.orientationRaw != orientationRaw
            || card.zIndex != object.zIndex
            || card.underlaidTrackingIDs != underlaid
        card.lastSeenFrame = object.lastSeenFrame
        guard changed else { return }

        card.cardID = printing?.riftboundID
        card.displayName = printing?.name
        card.zoneRaw = zoneRaw
        card.orientationRaw = orientationRaw
        card.zIndex = object.zIndex
        card.underlaidTrackingIDs = underlaid
        card.updatedAt = .now
        save()
    }

    /// Cache first, then a fetch for rows written in an earlier session.
    private func existingCard(for trackingID: TrackedObjectID) -> PersistentTrackedCard? {
        if let cached = persistedCards[trackingID] { return cached }
        guard let fetched = fetch(trackingID: trackingID) else { return nil }
        persistedCards[trackingID] = fetched
        return fetched
    }

    private func fetch(trackingID: TrackedObjectID) -> PersistentTrackedCard? {
        let descriptor = FetchDescriptor<PersistentTrackedCard>(
            predicate: #Predicate { $0.trackingID == trackingID }
        )
        return try? context.fetch(descriptor).first
    }

    private func delete(trackingID: TrackedObjectID) {
        if let card = existingCard(for: trackingID) {
            context.delete(card)
            save()
        }
        persistedCards[trackingID] = nil
    }

    /// Board state is re-derived from the camera on the next poll, so a
    /// failed save costs one frame of durability, not correctness.
    private func save() {
        try? context.save()
    }
}
