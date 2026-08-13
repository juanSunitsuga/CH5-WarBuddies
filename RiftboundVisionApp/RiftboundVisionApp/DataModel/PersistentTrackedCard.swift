//
//  PersistentTrackedCard.swift
//  RiftboundVisionApp
//
//  Created by I Gusti Ngurah Bagus Ferry Mahayudha on 12/08/26.
//

import Foundation
import SwiftData

/// SwiftData record for one *on-board* tracked card instance — the physical
/// card sitting on the table right now, NOT the card definition (that's
/// `RiftboundCard` in `RiftboundTextProcessing`, and it must never be
/// deleted when a unit dies).
///
/// The live tracking/occlusion/z-index work is done by
/// `RiftboundVision.ObjectTracker` + `UnderlayResolver` in memory every
/// frame; this type is only the durable projection of that state, so board
/// contents survive an app relaunch and so "card entered the Trash zone"
/// can be a real database deletion (see `CameraPipelineController`).
///
/// Keyed by `trackingID` (the `TrackedObjectID` the tracker assigns), so a
/// card that's merely occluded/re-matched keeps its row instead of spawning
/// a duplicate — the whole point of the persistent-identity design.
@Model
final class PersistentTrackedCard {
    /// The `RiftboundVision.TrackedObjectID` this row mirrors. Unique so
    /// upserts match an existing row instead of inserting duplicates.
    @Attribute(.unique) var trackingID: Int

    /// Assigned card identity (`CardPrinting.riftboundID`), or `nil` while
    /// still unidentified — recognition doesn't exist yet, so this is set
    /// when the user manually assigns a card in the sidebar.
    var cardID: String?
    var displayName: String?

    /// Last resolved `Zone.rawValue` and `CardOrientation.rawValue`. Stored
    /// as strings to keep this model free of a `RiftboundVision` import.
    var zoneRaw: String
    var orientationRaw: String

    /// Stacking state mirrored from the in-memory `TrackedObject`.
    var zIndex: Int
    var underlaidTrackingIDs: [Int]

    var lastSeenFrame: Int
    var updatedAt: Date

    init(
        trackingID: Int,
        cardID: String? = nil,
        displayName: String? = nil,
        zoneRaw: String = "unknown",
        orientationRaw: String = "ready",
        zIndex: Int = 0,
        underlaidTrackingIDs: [Int] = [],
        lastSeenFrame: Int = 0,
        updatedAt: Date = .now
    ) {
        self.trackingID = trackingID
        self.cardID = cardID
        self.displayName = displayName
        self.zoneRaw = zoneRaw
        self.orientationRaw = orientationRaw
        self.zIndex = zIndex
        self.underlaidTrackingIDs = underlaidTrackingIDs
        self.lastSeenFrame = lastSeenFrame
        self.updatedAt = updatedAt
    }
}
