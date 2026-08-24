import SwiftUI
import RiftboundVision

/// A · B · C · D — rule 515's fixed script as four lit-or-unlit pips.
///
/// Its own type because it's read at a glance from across a table and has
/// nothing to do with the buttons beneath it; the two change for different
/// reasons.
struct PhasePipRow: View {
    let current: GamePhase

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
                        // Matched to the unlit pip's ring rather than the
                        // fainter 0.4 it had, so the chain is one weight
                        // throughout instead of links dimmer than dots.
                        .fill(RiftboundPalette.elementStroke.opacity(0.5))
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

    private func pip(for phase: GamePhase) -> some View {
        let isCurrent = current == phase
        return Text(RiftboundPhaseCopy.pipLetter(for: phase))
            .riftFont(.heading)
            .foregroundStyle(isCurrent ? RiftboundPalette.elementShadow : RiftboundPalette.regularText.opacity(0.7))
            .frame(width: Self.pipDiameter, height: Self.pipDiameter)
            .background(Circle().fill(isCurrent ? RiftboundPalette.highlightOverlay : Color.clear))
            .overlay(Circle().stroke(RiftboundPalette.elementStroke.opacity(isCurrent ? 0 : 0.5), lineWidth: 1))
            .accessibilityLabel(phase.displayName)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
