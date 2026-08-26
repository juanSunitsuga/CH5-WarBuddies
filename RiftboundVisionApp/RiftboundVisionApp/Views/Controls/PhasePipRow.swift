import SwiftUI
import RiftboundVision

/// A · B · C · D — rule 515's fixed script as four lit-or-unlit pips.
///
/// Its own type because it's read at a glance from across a table and has
/// nothing to do with the buttons beneath it; the two change for different
/// reasons.
struct PhasePipRow: View {
    let current: GamePhase
    /// Whether a turn is actually under way.
    ///
    /// When it isn't, *no* pip lights — `current` still holds a phase
    /// (Awaken, where a new game will begin), but before Start Game
    /// that's where the turn *would* start, not where it is. Lighting it
    /// anyway claimed a turn was in progress, which is the one thing this
    /// row exists to report.
    var isGameRunning: Bool = true

    /// Diameter of one pip, and the length of the connector between two.
    /// The reference draws a 48pt pip with an 11pt link — the same ratio,
    /// scaled to the pip size this column uses.
    private static let pipDiameter: CGFloat = 38
    private static let connectorLength: CGFloat = 10

    var body: some View {
        // `spacing: 0` is the whole point. The connectors were already
        // here, but a 10pt HStack gap on each side left them floating
        // between the pips rather than joining them, so the row read as
        // four separate dots with a dash in between. At zero spacing the
        // line butts against both rings and the four steps read as one
        // chain, which is what says they run in order.
        HStack(spacing: 0) {
            ForEach(Array(RiftboundPhaseCopy.startOfTurnPhases.enumerated()), id: \.element) { index, phase in
                if index > 0 {
                    Rectangle()
                        // The same #CBCBCB as an unlit pip's ring, at full
                        // strength. It was `elementStroke` at 50% — a
                        // faded warm gold standing in for a flat grey,
                        // which read as a *dimmed* link rather than a
                        // plain one and drifted whenever the stroke colour
                        // moved.
                        .fill(RiftboundPalette.disabledElementStroke)
                        .frame(width: Self.connectorLength, height: 1)
                }
                pip(for: phase)
            }
        }
        // The chain is one object; VoiceOver should read it as the turn's
        // four steps, not walk four unlabelled circles and three lines.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Start of turn phases")
    }

    /// Both states are drawn the same way — filled disc, ring, white
    /// letter — and differ only in which pair of colours they use.
    ///
    /// That symmetry is the change from the previous version, which gave
    /// the lit pip a fill and the unlit ones no fill at all, and set both
    /// letters in cream at two different opacities. Four steps of one
    /// process should look like one component in two states; a hollow
    /// circle beside a solid one reads as two different kinds of thing.
    private func pip(for phase: GamePhase) -> some View {
        let isCurrent = isGameRunning && current == phase
        return Text(RiftboundPhaseCopy.pipLetter(for: phase))
            .riftFont(.heading)
            // #FFFFFF in both states. Not `regularText` — the board's
            // cream is for text on the *board*, and against the lit pip's
            // #A36F18 it reads as slightly stained rather than as a label.
            .foregroundStyle(RiftboundPalette.pureWhite)
            .frame(width: Self.pipDiameter, height: Self.pipDiameter)
            .background(
                Circle().fill(
                    isCurrent
                        ? RiftboundPalette.primaryButton
                        : RiftboundPalette.disabledHighlightOverlay
                )
            )
            .overlay(
                Circle().stroke(
                    isCurrent
                        ? RiftboundPalette.highlightOverlay
                        : RiftboundPalette.disabledElementStroke,
                    lineWidth: RiftboundLayout.hairline
                )
            )
            .accessibilityLabel(phase.displayName)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
