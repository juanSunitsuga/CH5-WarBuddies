import SwiftUI
import RiftboundVision

/// The row of cards currently on the table, along the top of the window.
///
/// Selecting one reveals its details **beside it**, in place, rather than
/// in a far-away panel. That's the point of the layout: the card you tapped
/// and the words about it are in the same glance, so you don't have to hold
/// "which card was I asking about" in your head while your eyes travel to
/// the other side of the screen.
///
/// Selection is shared with the camera view through `ContentView`, so
/// tapping a detection box on the feed highlights the same card here and
/// opens the same panel. One selection, two ways in.
struct TableCardStrip: View {
    /// Distinct printings the pipeline can currently see, in a stable
    /// order — see `CameraPipelineController.cardsOnTable`.
    var cards: [CardPrinting]
    @Binding var selection: CardPrinting?

    private static let cardWidth: CGFloat = 96
    private static let cardHeight: CGFloat = 134

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    if cards.isEmpty {
                        emptyState
                    } else {
                        ForEach(cards) { printing in
                            cardButton(printing)
                            // The detail sits immediately after the card it
                            // belongs to, so the row reads left-to-right as
                            // "this card, and here's what it is".
                            if selection?.id == printing.id {
                                CardDetailView(printing: printing) { selection = nil }
                                    .frame(width: 320)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
            .frame(height: Self.cardHeight + 40)
            .onChange(of: selection?.id) { _, newID in
                // Opening a detail can push the selected card off-screen,
                // which makes the panel look like it belongs to whatever
                // card ended up beside it. Scrolling it back into view is
                // what keeps "beside the card" true.
                guard let newID else { return }
                withAnimation { proxy.scrollTo(newID, anchor: .leading) }
            }
        }
    }

    private func cardButton(_ printing: CardPrinting) -> some View {
        let isSelected = selection?.id == printing.id
        return Button {
            // Tapping the open card closes it, so the strip is a toggle
            // rather than something that can only ever be opened.
            selection = isSelected ? nil : printing
        } label: {
            CardArtView(printing: printing, cornerRadius: 4, contentMode: .fill, showsFailureLabel: false)
                .frame(width: Self.cardWidth, height: Self.cardHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(
                            isSelected ? RiftboundPalette.highlightOverlay : RiftboundPalette.elementStroke.opacity(0.5),
                            lineWidth: isSelected ? 3 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .id(printing.id)
        .accessibilityLabel(printing.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var emptyState: some View {
        Text("No cards on the table yet.")
            .font(RiftboundFont.body)
            .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
            .frame(height: Self.cardHeight, alignment: .center)
    }
}
