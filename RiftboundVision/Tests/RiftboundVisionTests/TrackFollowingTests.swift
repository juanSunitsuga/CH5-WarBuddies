import Testing
import CoreGraphics
@testable import RiftboundVision

/// Following a card once it has been identified — the half of tracking that
/// only becomes possible after `ObjectTracker` commits an identity.
@Suite("Track Following")
struct TrackFollowingTests {

    private static func zoneMapper() -> ZoneMapper {
        ZoneMapper(zones: [
            BoardZone(
                type: .base,
                polygon: [CGPoint(x: 0, y: 0), CGPoint(x: 900, y: 0), CGPoint(x: 900, y: 900), CGPoint(x: 0, y: 900)],
                owner: .player1
            )
        ])
    }

    private static func detection(_ label: String, x: CGFloat, y: CGFloat = 300, confidence: Float = 0.9) -> Detection {
        Detection(
            type: .card,
            center: CGPoint(x: x, y: y),
            boundingBox: CGRect(x: x - 40, y: y - 55, width: 80, height: 110),
            rotation: 0,
            confidence: confidence,
            recognizedLabel: label
        )
    }

    /// Runs a script of per-poll detection sets and returns the final tracks.
    private static func run(_ frames: [[Detection]]) -> [TrackedObject] {
        let tracker = ObjectTracker()
        let mapper = zoneMapper()
        var last: TrackerUpdateResult?
        for (index, batch) in frames.enumerated() {
            last = tracker.update(
                detections: batch,
                zoneMapper: mapper,
                frameIndex: index + 1,
                timestamp: Double(index) * 0.1,
                previousTimestamp: index == 0 ? nil : Double(index - 1) * 0.1
            )
        }
        return last?.objects ?? []
    }

    /// Two identified cards close enough that the *cross* pairing is
    /// geometrically closer than the correct one.
    ///
    /// Annie settles at x=300 and the Officer at x=340. Next poll they are
    /// seen at 322 and 318 — so Annie's track is 18 away from the Officer's
    /// detection and 22 away from Annie's own. Nearest-neighbour takes the
    /// 18 and the two swap identities, with nothing on the table having
    /// moved by more than a few pixels. The detector said which was which
    /// the whole time; now that each track has committed to a label, that
    /// agreement is allowed to outrank a four-pixel difference.
    @Test("Adjacent cards don't swap tracks when geometry alone would cross them")
    func adjacentCardsKeepTheirIdentities() {
        var frames: [[Detection]] = (0..<12).map { _ in
            [Self.detection("Annie Fiery", x: 300), Self.detection("Petty Officer", x: 340)]
        }
        frames += (0..<6).map { _ in
            [Self.detection("Annie Fiery", x: 322), Self.detection("Petty Officer", x: 318)]
        }

        let tracks = Self.run(frames)
        #expect(tracks.count == 2)

        let annie = tracks.first { $0.recognizedLabel == "Annie Fiery" }
        let officer = tracks.first { $0.recognizedLabel == "Petty Officer" }
        #expect(annie != nil)
        #expect(officer != nil)
        // Each track ends up on the detection carrying its own label.
        #expect(annie?.center.x == 322)
        #expect(officer?.center.x == 318)
    }

    /// A hand resting over a card in the Base covers it for longer than the
    /// 15 polls an anonymous track is given. Dropping it loses the settled
    /// identity, which a rebuilt track then has to earn all over again.
    @Test("An identified card survives being covered for longer than an anonymous one")
    func committedTracksAreWaitedFor() {
        let settle: [[Detection]] = (0..<12).map { _ in [Self.detection("Annie Fiery", x: 300)] }
        let covered: [[Detection]] = Array(repeating: [], count: 30)

        let survived = Self.run(settle + covered)
        #expect(survived.count == 1)
        #expect(survived.first?.recognizedLabel == "Annie Fiery")
        #expect(survived.first?.isIdentityCommitted == true)

        // The same gap kills a track that never settled on an identity —
        // two readings is nowhere near the commit threshold.
        let unsettled = Self.run(Array(repeating: [Self.detection("Annie Fiery", x: 300)], count: 2) + covered)
        #expect(unsettled.isEmpty)
    }

    /// The identity bias reorders candidates; it must not let a card match
    /// something on the far side of the table. The hard distance gate is
    /// still the hard gate.
    @Test("Identity agreement never matches across the table")
    func identityDoesNotDefeatDistance() {
        var frames: [[Detection]] = (0..<12).map { _ in [Self.detection("Annie Fiery", x: 200)] }
        frames.append([Self.detection("Annie Fiery", x: 820)])

        let tracks = Self.run(frames)
        // Same label, but far outside the match radius: that is a different
        // physical card, not the tracked one teleporting.
        #expect(tracks.contains { $0.center.x > 700 })
    }
}
