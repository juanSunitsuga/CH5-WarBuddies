import SwiftUI
import RiftboundVision

/// A · B · C · D — rule 515's fixed script as four lit-or-unlit pips.
///
/// Its own type because it's read at a glance from across a table and has
/// nothing to do with the buttons beneath it; the two change for different
/// reasons.
struct PhasePipRow: View {
    let current: GamePhase

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(RiftboundPhaseCopy.startOfTurnPhases.enumerated()), id: \.element) { index, phase in
                if index > 0 {
                    Rectangle()
                        .fill(RiftboundPalette.elementStroke.opacity(0.4))
                        .frame(width: 14, height: 1)
                }
                pip(for: phase)
            }
        }
    }

    private func pip(for phase: GamePhase) -> some View {
        let isCurrent = current == phase
        return Text(RiftboundPhaseCopy.pipLetter(for: phase))
            .font(RiftboundFont.heading)
            .foregroundStyle(isCurrent ? RiftboundPalette.elementShadow : RiftboundPalette.regularText.opacity(0.7))
            .frame(width: 38, height: 38)
            .background(Circle().fill(isCurrent ? RiftboundPalette.highlightOverlay : Color.clear))
            .overlay(Circle().stroke(RiftboundPalette.elementStroke.opacity(isCurrent ? 0 : 0.5), lineWidth: 1))
            .accessibilityLabel(phase.displayName)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
