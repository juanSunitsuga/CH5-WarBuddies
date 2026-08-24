import SwiftUI
import RiftboundVision

/// What the *engine* believes you can spend — the first thing on screen
/// derived from `GameState` rather than from a second read of the table.
///
/// That distinction is the point of this view existing. Every other line in
/// the app comes from `PhaseAutoDetector` looking at the mat again; this one
/// comes from the ledger the engine keeps as it accepts actions. When the
/// two disagree, the disagreement is now visible — which is the only way it
/// ever gets fixed, and the reason a played card being rejected for cost
/// used to be baffling.
///
/// Energy arrives here by exactly one route: turning a rune sideways
/// (157.2.a). If this stays at zero while runes are being exhausted on the
/// table, the orientation event isn't reaching the engine.
struct EnergySection: View {
    let energy: Int?
    let readyRunes: Int?
    let totalRunes: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Energy")
                .riftFont(.heading)
                .foregroundStyle(RiftboundPalette.regularText)

            if let energy {
                Text(explanation(energy: energy))
                    .riftFont(.body)
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    counter("Energy", energy)
                    if let readyRunes, let totalRunes {
                        counter("Runes upright", readyRunes, of: totalRunes)
                    }
                }
            } else {
                // Distinct from "0": the engine hasn't seen anything yet, so
                // there is no number to report rather than a number that
                // happens to be nothing.
                Text("Start the game and I'll track what you can spend.")
                    .riftFont(.body)
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func explanation(energy: Int) -> String {
        guard energy == 0 else {
            return "Enough to pay a cost of \(energy). Turn another rune sideways for one more."
        }
        return "Turn a rune sideways to get Energy — that's what pays a card's cost."
    }

    private func counter(_ title: String, _ value: Int, of total: Int? = nil) -> some View {
        VStack(spacing: 2) {
            Text(total.map { "\(value)/\($0)" } ?? "\(value)")
                .riftFont(.iconic2)
                .foregroundStyle(RiftboundPalette.elementShadow)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(title)
                .riftFont(.body)
                .foregroundStyle(RiftboundPalette.elementShadow.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RiftboundPalette.highlightOverlay, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
