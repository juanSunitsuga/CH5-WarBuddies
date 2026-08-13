import CoreGraphics
import Foundation

/// The stacking role of a card, as far as underlay rules care. Deliberately
/// coarser than the full card type — the only distinction that changes
/// stacking behaviour is "is this a Unit (the thing that sits on top and
/// can't share a stack with another Unit)" vs "is this something that
/// tucks under a Unit (Gear/Equipment, or a Rune channelled beneath it)."
///
/// The `RiftboundVision` package can't derive this itself: its tracker only
/// knows CARD/RUNE/UNKNOWN geometry, not card identity. The app resolves a
/// `TrackedObjectID` to a role from its own card assignments / recognition
/// and hands the mapping to `UnderlayResolver.resolve`.
public enum CardRole: Sendable, Equatable {
    /// A Unit — sits on top of its stack; two Units may not stack.
    case unit
    /// Something that legally sits *under* a Unit (Gear/Equipment/Rune).
    case attachment
    /// A known card that is neither (e.g. a Battlefield or Spell that
    /// shouldn't participate in unit/attachment stacking).
    case other
    /// Identity not yet known for this track — treated conservatively
    /// (never linked, never flagged illegal).
    case unknown
}

/// A resolved parent→children stacking link for one frame: `unitID` sits on
/// top, with `underlaidIDs` tucked beneath it.
public struct UnderlayLinkage: Sendable, Equatable {
    public let unitID: TrackedObjectID
    public let underlaidIDs: [TrackedObjectID]

    public init(unitID: TrackedObjectID, underlaidIDs: [TrackedObjectID]) {
        self.unitID = unitID
        self.underlaidIDs = underlaidIDs
    }
}

/// Two overlapping cards that the rules forbid from stacking (currently
/// only Unit-on-Unit). Surfaced so the app can warn the player rather than
/// silently mis-model the board.
public struct IllegalOverlap: Sendable, Equatable {
    public let firstID: TrackedObjectID
    public let secondID: TrackedObjectID
    public let reason: String

    public init(firstID: TrackedObjectID, secondID: TrackedObjectID, reason: String) {
        self.firstID = firstID
        self.secondID = secondID
        self.reason = reason
    }
}

public struct UnderlayResolution: Sendable {
    /// The input objects with `zIndex` and `underlaidCardIDs` recomputed
    /// for this frame. Same order as the input.
    public let objects: [TrackedObject]
    public let linkages: [UnderlayLinkage]
    public let illegalOverlaps: [IllegalOverlap]

    public init(objects: [TrackedObject], linkages: [UnderlayLinkage], illegalOverlaps: [IllegalOverlap]) {
        self.objects = objects
        self.linkages = linkages
        self.illegalOverlaps = illegalOverlaps
    }
}

/// Turns "these two bounding boxes overlap a lot" into a parent/child
/// stacking relationship, applying Riftbound's stacking rules via a
/// caller-supplied role classifier.
///
/// Stateless and pure: it recomputes `zIndex`/`underlaidCardIDs` from
/// scratch each frame off current geometry, so a card slid out from under a
/// Unit simply stops being linked next frame — no stale links to expire.
/// Identity persistence (surviving occlusion) is `ObjectTracker`'s job; this
/// only decides who's on top of whom *right now*.
public struct UnderlayResolver: Sendable {
    /// Minimum Intersection-over-Union for two cards to count as a
    /// deliberate stack rather than two adjacent cards touching. 0.6 per
    /// the design brief — high enough that a Unit merely placed beside an
    /// Equipment isn't mistaken for one sitting on top of it.
    public let overlapThreshold: CGFloat

    public init(overlapThreshold: CGFloat = 0.6) {
        self.overlapThreshold = overlapThreshold
    }

    public func resolve(_ objects: [TrackedObject], role: (TrackedObjectID) -> CardRole) -> UnderlayResolution {
        // Fresh state every frame: clear any prior linking, then rebuild.
        var byID: [TrackedObjectID: TrackedObject] = [:]
        for var object in objects {
            object.zIndex = 0
            object.underlaidCardIDs = []
            byID[object.id] = object
        }

        var underlaidByUnit: [TrackedObjectID: [TrackedObjectID]] = [:]
        var illegalOverlaps: [IllegalOverlap] = []

        let sorted = objects.sorted { $0.id < $1.id }
        for i in sorted.indices {
            for j in (i + 1)..<sorted.count {
                let a = sorted[i]
                let b = sorted[j]
                guard a.boundingBox.intersectionOverUnion(b.boundingBox) >= overlapThreshold else { continue }

                let roleA = role(a.id)
                let roleB = role(b.id)

                switch (roleA, roleB) {
                case (.unit, .unit):
                    illegalOverlaps.append(IllegalOverlap(
                        firstID: a.id, secondID: b.id, reason: "Units cannot stack on each other"
                    ))
                case (.unit, .attachment):
                    underlaidByUnit[a.id, default: []].append(b.id)
                case (.attachment, .unit):
                    underlaidByUnit[b.id, default: []].append(a.id)
                default:
                    // Unit+other, attachment+attachment, anything unknown:
                    // no stacking relationship we can commit to.
                    break
                }
            }
        }

        var linkages: [UnderlayLinkage] = []
        for (unitID, underlaid) in underlaidByUnit {
            let ordered = underlaid.sorted()
            byID[unitID]?.zIndex = 1
            byID[unitID]?.underlaidCardIDs = ordered
            linkages.append(UnderlayLinkage(unitID: unitID, underlaidIDs: ordered))
        }
        linkages.sort { $0.unitID < $1.unitID }

        // Preserve caller's original ordering.
        let resolvedObjects = objects.map { byID[$0.id] ?? $0 }
        return UnderlayResolution(objects: resolvedObjects, linkages: linkages, illegalOverlaps: illegalOverlaps)
    }
}
