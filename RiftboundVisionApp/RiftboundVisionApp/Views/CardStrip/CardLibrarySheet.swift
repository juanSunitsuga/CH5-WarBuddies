import SwiftUI
import RiftboundVision

/// The searchable catalogue, behind the strip's Card Library button.
///
/// Searches the whole database rather than only what's on camera — the
/// strip already shows what's on the table, so a search that could only
/// narrow that list would have nothing left to do.
struct CardLibrarySheet: View {
    let database: CardDatabase
    @Binding var selection: CardPrinting?
    /// Resolves a printing's rules text for `CardDetailView`'s Ability row
    /// — the same resolver `TableCardStrip` passes to `InlineCardDetail`,
    /// so a card's Ability doesn't read differently depending on where you
    /// looked it up. See `CameraPipelineController.description(for:)`.
    let description: (CardPrinting) -> String
    let onClose: () -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    /// The card whose full details are showing in place of the result
    /// list. Kept local rather than routed through `selection` — that
    /// binding drives the on-table strip's inline panel, which only shows
    /// anything for a card the camera can currently see; browsing the full
    /// database needs its detail page to work regardless.
    @State private var detailPrinting: CardPrinting?

    private var results: [CardPrinting] {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
            ? database.allPrintings
            : database.search(searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let detailPrinting {
                ScrollView {
                    // `CardDetailView` centres its own content — nothing
                    // extra needed here to keep art/name/rows aligned.
                    CardDetailView(printing: detailPrinting, description: description(detailPrinting))
                }
            } else {
                searchField

                if results.isEmpty {
                    Text("No cards match “\(searchText)”.")
                        .font(RiftboundFont.body)
                        .foregroundStyle(RiftboundPalette.regularText.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(results) { printing in
                                resultRow(printing)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 620)
        .background(RiftboundPalette.mainBackground)
    }

    private var header: some View {
        HStack {
            if let detailPrinting {
                Button("Back") { self.detailPrinting = nil }
                    .buttonStyle(RiftSecondaryButtonStyle())
                Text(detailPrinting.name)
                    .font(RiftboundFont.heading)
                    .foregroundStyle(RiftboundPalette.regularText)
                    .lineLimit(1)
            } else {
                Text("Card Library")
                    .font(RiftboundFont.heading)
                    .foregroundStyle(RiftboundPalette.regularText)
            }
            Spacer()
            Button("Close", action: onClose)
                .buttonStyle(RiftSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RiftboundPalette.regularText.opacity(0.7))
            TextField("Search for card…", text: $searchText)
                .textFieldStyle(.plain)
                .font(RiftboundFont.body)
                .foregroundStyle(RiftboundPalette.regularText)
                .focused($isSearchFocused)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(RiftboundPalette.regularText.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(RiftboundPalette.elementShadow)
        )
        .onAppear { isSearchFocused = true }
    }

    private func resultRow(_ printing: CardPrinting) -> some View {
        Button {
            // Also updates `selection`, harmless when the card isn't on
            // the table (`TableCardStrip` simply has nothing to highlight)
            // and a small bonus when it is — browsing the library then
            // highlights that card back in the strip underneath.
            selection = printing
            detailPrinting = printing
        } label: {
            HStack(spacing: 12) {
                CardArtView(printing: printing, cornerRadius: 4, contentMode: .fill, showsFailureLabel: false)
                    .frame(width: 44, height: 62)
                VStack(alignment: .leading, spacing: 2) {
                    Text(printing.name)
                        .font(RiftboundFont.heading)
                        .foregroundStyle(RiftboundPalette.regularText)
                    Text(printing.classification.type)
                        .font(RiftboundFont.body)
                        .foregroundStyle(RiftboundPalette.regularText.opacity(0.7))
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
