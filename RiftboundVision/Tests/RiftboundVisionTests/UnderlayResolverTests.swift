import Testing
import CoreGraphics
@testable import RiftboundVision

private func object(id: TrackedObjectID, box: CGRect) -> TrackedObject {
    TrackedObject(
        id: id,
        type: .card,
        center: CGPoint(x: box.midX, y: box.midY),
        boundingBox: box,
        rotation: 0,
        confidence: 0.9,
        isVisible: true,
        lastSeenFrame: 0
    )
}

/// Builds a role classifier from an explicit id→role map; anything not in
/// the map is `.unknown`, mirroring "not yet assigned a card."
private func roles(_ map: [TrackedObjectID: CardRole]) -> (TrackedObjectID) -> CardRole {
    { map[$0] ?? .unknown }
}

struct UnderlayResolverTests {
    private let overlapping = CGRect(x: 0, y: 0, width: 20, height: 30)

    @Test("An Equipment overlapping a Unit is tucked under it, Unit on top")
    func attachmentUnderUnit() {
        let unit = object(id: 1, box: overlapping)
        let gear = object(id: 2, box: overlapping)
        let resolution = UnderlayResolver().resolve([unit, gear], role: roles([1: .unit, 2: .attachment]))

        let resolvedUnit = resolution.objects.first { $0.id == 1 }!
        let resolvedGear = resolution.objects.first { $0.id == 2 }!
        #expect(resolvedUnit.underlaidCardIDs == [2])
        #expect(resolvedUnit.zIndex == 1)
        #expect(resolvedGear.zIndex == 0)
        #expect(resolution.illegalOverlaps.isEmpty)
        #expect(resolution.linkages == [UnderlayLinkage(unitID: 1, underlaidIDs: [2])])
    }

    @Test("The order of arguments doesn't change who ends up on top")
    func attachmentUnderUnitOrderIndependent() {
        let gear = object(id: 2, box: overlapping)
        let unit = object(id: 1, box: overlapping)
        // Gear first this time.
        let resolution = UnderlayResolver().resolve([gear, unit], role: roles([1: .unit, 2: .attachment]))
        #expect(resolution.objects.first { $0.id == 1 }!.underlaidCardIDs == [2])
    }

    @Test("Two overlapping Units are flagged as an illegal overlap, never linked")
    func unitOnUnitIsIllegal() {
        let a = object(id: 1, box: overlapping)
        let b = object(id: 2, box: overlapping)
        let resolution = UnderlayResolver().resolve([a, b], role: roles([1: .unit, 2: .unit]))

        #expect(resolution.linkages.isEmpty)
        #expect(resolution.illegalOverlaps.count == 1)
        #expect(resolution.objects.allSatisfy { $0.underlaidCardIDs.isEmpty })
    }

    @Test("Cards that don't overlap enough are never stacked")
    func noOverlapNoLink() {
        let unit = object(id: 1, box: CGRect(x: 0, y: 0, width: 20, height: 30))
        let gear = object(id: 2, box: CGRect(x: 500, y: 500, width: 20, height: 30))
        let resolution = UnderlayResolver().resolve([unit, gear], role: roles([1: .unit, 2: .attachment]))

        #expect(resolution.linkages.isEmpty)
        #expect(resolution.illegalOverlaps.isEmpty)
    }

    @Test("An unidentified overlapping card is never linked or flagged")
    func unknownRoleNeverLinks() {
        let unit = object(id: 1, box: overlapping)
        let mystery = object(id: 2, box: overlapping)
        let resolution = UnderlayResolver().resolve([unit, mystery], role: roles([1: .unit]))

        #expect(resolution.linkages.isEmpty)
        #expect(resolution.illegalOverlaps.isEmpty)
        #expect(resolution.objects.first { $0.id == 1 }!.underlaidCardIDs.isEmpty)
    }

    @Test("Multiple attachments under one Unit are all recorded, sorted")
    func multipleAttachmentsUnderUnit() {
        let unit = object(id: 1, box: overlapping)
        let gearA = object(id: 3, box: overlapping)
        let gearB = object(id: 2, box: overlapping)
        let resolution = UnderlayResolver().resolve(
            [unit, gearA, gearB],
            role: roles([1: .unit, 2: .attachment, 3: .attachment])
        )
        #expect(resolution.objects.first { $0.id == 1 }!.underlaidCardIDs == [2, 3])
    }

    @Test("Just-below-threshold overlap does not stack")
    func belowThresholdNoLink() {
        // IoU of these two 20×30 boxes offset by 15 in x:
        // intersection 5×30 = 150, union 600+600-150 = 1050 → ~0.143 < 0.6.
        let unit = object(id: 1, box: CGRect(x: 0, y: 0, width: 20, height: 30))
        let gear = object(id: 2, box: CGRect(x: 15, y: 0, width: 20, height: 30))
        let resolution = UnderlayResolver().resolve([unit, gear], role: roles([1: .unit, 2: .attachment]))
        #expect(resolution.linkages.isEmpty)
    }
}
