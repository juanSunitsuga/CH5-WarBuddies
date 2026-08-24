import SwiftUI
import RiftboundVision

/// One card in the table strip: the art, and whether it's the selected one.
///
/// Its own type because the strip's job is arrangement and this one's is
/// appearance — the selected ring, the hit area, the accessibility traits.
/// Keeping them apart is what lets the strip read as a list of cards rather
/// than a list of styling.
struct TableCardThumbnail: View {
    let printing: CardPrinting
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            CardArtView(
                printing: printing,
                cornerRadius: 4,
                contentMode: .fill,
                showsFailureLabel: false,
                // Battlefields print landscape; stood upright so the
                // strip stays one row of same-shaped cards.
                uprightsLandscapeArt: true
            )
            .frame(width: RiftboundLayout.stripCardWidth, height: RiftboundLayout.stripCardHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(
                        isSelected ? RiftboundPalette.highlightOverlay : RiftboundPalette.elementStroke.opacity(0.5),
                        lineWidth: isSelected ? 3 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(printing.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
