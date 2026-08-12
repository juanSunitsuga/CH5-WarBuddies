import CoreGraphics

/// Whether a card is standing Ready (upright) or Exhausted (tapped 90°).
/// These are the Riftbound rules terms (591–593) for what the physical
/// world calls "vertical" vs "horizontal."
///
/// Inferred from bounding-box aspect ratio rather than tracked rotation:
/// the rectangle detector re-initializes a card's bounding box relative to
/// the screen frame whenever the card rotates, so raw `rotation` can be
/// unreliable across a tap, whereas "is the box taller than it is wide"
/// survives that re-initialization. See `CGRect.cardOrientation`.
public enum CardOrientation: String, Sendable, Equatable, Codable {
    /// Vertical — the card is upright and available to act.
    case ready
    /// Horizontal (tapped) — the card has been rotated 90°.
    case exhausted
}

public extension CGRect {
    /// Orientation heuristic from the box's own proportions: a standard TCG
    /// card is taller than it is wide when Ready, and wider than tall once
    /// tapped. A near-square box (`|Δ| < squareTolerance` of the larger
    /// side) is ambiguous and reported as `.ready` — the conservative
    /// default, since a mid-rotation frame shouldn't read as Exhausted;
    /// `TemporalEventDetector`-style confirmation smooths the transition.
    func cardOrientation(squareTolerance: CGFloat = 0.05) -> CardOrientation {
        let longSide = Swift.max(width, height)
        guard longSide > 0 else { return .ready }
        // Within the deadzone around square, don't commit to Exhausted.
        if abs(height - width) < longSide * squareTolerance { return .ready }
        return height >= width ? .ready : .exhausted
    }

    /// Convenience with the default tolerance, usable as a property.
    var cardOrientation: CardOrientation { cardOrientation() }

    /// Intersection-over-Union with another rect: shared area divided by
    /// combined area, in `[0, 1]`. `0` when they don't overlap (or either
    /// is empty). Used by `UnderlayResolver` to decide when two detections
    /// overlap enough to be a deliberate stack rather than two adjacent
    /// cards touching at the edges.
    func intersectionOverUnion(_ other: CGRect) -> CGFloat {
        let intersection = self.intersection(other)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = width * height + other.width * other.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
