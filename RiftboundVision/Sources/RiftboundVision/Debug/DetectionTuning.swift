import CoreGraphics
import Vision

/// The six detection and tracking numbers worth varying between
/// measurement runs, in one value.
///
/// One struct rather than six separate knobs because a run is defined by
/// all six together: "P95 was 42 ms" means nothing without the settings it
/// was measured under, and six loose properties cannot be recorded, reset
/// or compared as a set.
///
/// **Only the six.** Four other constants in this layer look equally
/// tunable and are deliberately left out:
///
/// - `ObjectTracker.matchDistanceThreshold` is used only as a floor, via
///   `max(60, longest side × matchRadiusInCardLengths)`. Whenever a card's
///   longest side exceeds 50 px — which it does at any usable framing —
///   the card-scaled term wins and this value changes nothing.
/// - `ObjectTracker.labelSwitchMargin` works as a pair with
///   `labelCommitThreshold`. Varying both independently multiplies the
///   combinations and makes neither one's effect separable, so it stays
///   at 3.0.
/// - `ObjectTracker.committedOcclusionToleranceFrames` only applies to a
///   card whose identity is already locked *and* which stays hidden for
///   more than 15 polls.
/// - `ObjectTracker.settledOcclusionToleranceFrames` only applies in the
///   Battlefield, Rune Area and Rune Deck, where 300 polls is about 60
///   seconds of continuous occlusion. An ordinary recording almost never
///   contains that, so every value gives the same result.
///
/// The last two would need a recording made specifically to provoke them.
/// Until there is one, varying them measures nothing.
public struct DetectionTuning: Equatable, Codable, Sendable {

    // MARK: - Detection

    /// Per-detection confidence floor, on top of the model's own NMS.
    public var minimumConfidence: Float

    /// Accepted `max(side) / min(side)` of a detection box. A real card is
    /// about 1.4; a near-square box is some other object the model was
    /// confident about.
    ///
    /// Stored as two numbers rather than a `ClosedRange` because a range
    /// cannot be edited one end at a time — setting the lower bound above
    /// the current upper bound traps. `aspectRatioRange` rebuilds it in
    /// the right order.
    public var aspectRatioLowerBound: CGFloat
    public var aspectRatioUpperBound: CGFloat

    // MARK: - Tracking

    /// Card-lengths of travel tolerated between polls when matching a
    /// detection to an existing track.
    public var matchRadiusInCardLengths: CGFloat

    /// Consecutive polls an anonymous track may go unseen before it is
    /// reported as having disappeared rather than treated as occluded.
    public var occlusionToleranceFrames: Int

    /// Accumulated vote weight a label needs before a track's identity is
    /// committed to it.
    public var labelCommitThreshold: Float

    // MARK: - Event formation

    /// Consecutive polls a candidate zone or rotation must hold before the
    /// change is reported as an event.
    public var confirmationFrames: Int

    /// The values the app ships with — each one the default of the
    /// property it feeds, so a fresh install behaves exactly as it did
    /// before any of this was adjustable.
    public static let `default` = DetectionTuning(
        minimumConfidence: 0.75,
        aspectRatioLowerBound: 1.2,
        aspectRatioUpperBound: 1.8,
        matchRadiusInCardLengths: 1.2,
        occlusionToleranceFrames: 15,
        labelCommitThreshold: 6.0,
        confirmationFrames: 2
    )

    public init(
        minimumConfidence: Float = 0.75,
        aspectRatioLowerBound: CGFloat = 1.2,
        aspectRatioUpperBound: CGFloat = 1.8,
        matchRadiusInCardLengths: CGFloat = 1.2,
        occlusionToleranceFrames: Int = 15,
        labelCommitThreshold: Float = 6.0,
        confirmationFrames: Int = 2
    ) {
        self.minimumConfidence = minimumConfidence
        self.aspectRatioLowerBound = aspectRatioLowerBound
        self.aspectRatioUpperBound = aspectRatioUpperBound
        self.matchRadiusInCardLengths = matchRadiusInCardLengths
        self.occlusionToleranceFrames = occlusionToleranceFrames
        self.labelCommitThreshold = labelCommitThreshold
        self.confirmationFrames = confirmationFrames
    }

    /// The aspect bounds as a range, lower end first whichever way round
    /// they were set.
    ///
    /// Sorting rather than trusting the caller: `1.8...1.2` is a runtime
    /// trap, and the two bounds are edited separately in the UI, so
    /// passing through an inverted pair at the moment between two edits is
    /// normal rather than exceptional.
    public var aspectRatioRange: ClosedRange<CGFloat> {
        let lower = min(aspectRatioLowerBound, aspectRatioUpperBound)
        let upper = max(aspectRatioLowerBound, aspectRatioUpperBound)
        return lower...upper
    }

    /// `minimumConfidence` as Vision's own type.
    public var visionConfidence: VNConfidence { VNConfidence(minimumConfidence) }

    /// One line naming every value, for the measurement export's session
    /// label — so a CSV says which settings produced it.
    public var summary: String {
        String(
            format: "conf %.2f · aspect %.2f-%.2f · radius %.2f · occl %d · commit %.1f · confirm %d",
            minimumConfidence,
            aspectRatioRange.lowerBound,
            aspectRatioRange.upperBound,
            matchRadiusInCardLengths,
            occlusionToleranceFrames,
            labelCommitThreshold,
            confirmationFrames
        )
    }
}
