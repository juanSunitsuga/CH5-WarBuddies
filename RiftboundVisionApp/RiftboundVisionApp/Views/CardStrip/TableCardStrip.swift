import SwiftUI
import RiftboundVision

/// The row of cards currently on the table, along the top of the window.
///
/// Selecting one reveals its details **beside it**, in place, rather than
/// in a far-away panel: the card you tapped and the words about it are in
/// the same glance, so you don't have to hold "which card was I asking
/// about" in your head while your eyes travel across the screen.
///
/// Selection is shared with the camera view through `ContentView`, so
/// tapping a detection box on the feed highlights the same card here and
/// opens the same panel. One selection, two ways in.
///
/// Composed from `TableCardThumbnail`, `InlineCardDetail` and
/// `CardLibraryButton` — this type only arranges them and owns the
/// scrolling.
struct TableCardStrip: View {
    /// Distinct printings the pipeline can currently see.
    var cards: [CardPrinting]
    @Binding var selection: CardPrinting?
    let onOpenLibrary: () -> Void
    /// Resolves a printing's rules text — `simple_text` where the database
    /// has one, falling back through the tag-resolved copy to the raw
    /// printed text. Taken as a closure rather than a `CameraPipelineController`
    /// reference so this view doesn't need to know the pipeline exists.
    let description: (CardPrinting) -> String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Not inside `scrollingCards`'s `ScrollView`: a horizontally
            // scrolling container sizes its content to exactly what needs
            // to scroll, so a `maxWidth: .infinity` text placed inside it
            // never actually gets the width to centre itself in. As a
            // normal flexible sibling here it can claim the row's leftover
            // space (same as `scrollingCards` does when there are cards).
            // The tour points at the row of cards and at the Library
            // button in separate beats, so they anchor separately. Both
            // are declared here rather than on `TableCardStrip` from the
            // outside, which would have measured one rectangle covering
            // both plus the row's `columnInset` padding.
            //
            // `ZStack` rather than `Group`: `Group` is transparent to
            // layout, so `.tourRegion` on it would attach to whichever
            // branch is showing individually instead of to the pair as
            // one measurable box.
            ZStack {
                if cards.isEmpty {
                    emptyState
                } else {
                    scrollingCards
                }
            }
            .tourRegion(.table)

            // Outside the ScrollView so it stays put. See
            // `CardLibraryButton` for why.
            CardLibraryButton(action: onOpenLibrary)
                .tourRegion(.cardLibrary)
        }
        .frame(height: RiftboundLayout.stripCardHeight + 24)
        .padding(.horizontal, RiftboundLayout.columnInset)
    }

    private var scrollingCards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(cards) { printing in
                        TableCardThumbnail(
                            printing: printing,
                            isSelected: selection?.id == printing.id,
                            // Tapping the open card closes it, so the
                            // strip toggles rather than only ever opening.
                            onTap: { selection = selection?.id == printing.id ? nil : printing }
                        )
                        .id(printing.id)

                        // Immediately after the card it belongs to, so
                        // the row reads left-to-right as "this card,
                        // and here's what it is".
                        if selection?.id == printing.id {
                            InlineCardDetail(printing: printing, description: description(printing))
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .onChange(of: selection?.id) { _, newID in
                // Opening a detail can push the selected card out of view,
                // which makes the panel look like it belongs to whatever
                // card ended up beside it. Scrolling it back is what keeps
                // "beside the card" true.
                guard let newID else { return }
                withAnimation { proxy.scrollTo(newID, anchor: .leading) }
            }
        }
    }

    private var emptyState: some View {
        Text("No cards on the table yet.")
            .riftFont(.body)
            .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
            // `maxHeight: .infinity` is what actually centres this: the
            // outer `HStack` is `alignment: .top`, so without claiming the
            // full row height itself, a child sized only to its text sits
            // pinned to the top rather than centred in it.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
