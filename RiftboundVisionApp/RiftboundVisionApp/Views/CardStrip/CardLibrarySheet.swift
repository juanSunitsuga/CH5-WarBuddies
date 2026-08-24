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
    /// The card whose details are showing in the popup over the result
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
        // The list stays mounted underneath the detail popup rather than
        // being swapped out for it — that's what lets the popup read as
        // something on top of the catalogue you're browsing, and it also
        // means dismissing it can't lose your scroll position or your
        // search, which a swap-and-restore would have had to rebuild.
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                header
                searchField

                if results.isEmpty {
                    Text("No cards match “\(searchText)”.")
                        .riftFont(.body)
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
            // Padding on the list, not on the `ZStack` — the scrim is a
            // sibling, so anything inset out here would inset the dimming
            // too and leave an undimmed 20pt frame around the sheet.
            .padding(20)
            // Claims the sheet's full height and pins to the top, which
            // has to be stated rather than left to the content: the
            // results branch holds a `ScrollView` that grows to fill on
            // its own, but the "No cards match" branch is a single line
            // of text with nothing greedy in it, so the whole column
            // collapsed to its own height and the `ZStack` obligingly
            // centred it. Typing one more letter into the search field
            // sent the header and search box sliding down the sheet.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let detailPrinting {
                detailPopup(for: detailPrinting)
            }
        }
        .frame(width: 520, height: 620)
        .background(RiftboundPalette.mainBackground)
    }

    /// Opening springs; closing just gets out of the way.
    ///
    /// Deliberately asymmetric. Appearing is the app showing you
    /// something and can afford a little overshoot; dismissing is you
    /// having already moved on, and the same spring played backwards
    /// keeps a panel you're finished with on screen longer than it's
    /// wanted.
    private func setDetail(_ printing: CardPrinting?) {
        withAnimation(
            printing == nil
                ? .easeOut(duration: 0.16)
                : .spring(response: 0.34, dampingFraction: 0.84)
        ) {
            detailPrinting = printing
        }
    }

    @ViewBuilder
    private func detailPopup(for printing: CardPrinting) -> some View {
        // Same scrim the guided tour dims with, for the same reason: the
        // list underneath has to visibly stop being the thing in focus
        // while the popup is up. Tapping it closes, which is what people
        // try first on a floating panel.
        RiftboundPalette.tourScrim
            .contentShape(Rectangle())
            .onTapGesture { setDetail(nil) }
            .transition(.opacity)

        CardDetailView(
            printing: printing,
            description: description(printing),
            onClose: { setDetail(nil) }
        )
        // Grows out of a slightly smaller copy of itself rather than just
        // fading, so the popup reads as having come *from* the row that
        // was clicked instead of appearing over it from nowhere. Scaled
        // from near-full size — starting much smaller turns a response
        // into a flourish and makes the list behind it visibly lurch.
        .transition(.scale(scale: 0.94).combined(with: .opacity))
        // Keyed by card, so tapping a different result while one popup is
        // already open swaps the contents outright instead of cross-fading
        // one card's art and text into another's.
        .id(printing.id)
    }

    private var header: some View {
        HStack {
            Text("Card Library")
                .riftFont(.heading)
                .foregroundStyle(RiftboundPalette.regularText)
            Spacer()
            Button("Close", action: onClose)
                .buttonStyle(RiftSecondaryButtonStyle())
                // Only while no popup is up. Both are `.cancelAction`, and
                // with the popup showing Escape should dismiss *it* —
                // closing the whole library out from under a card the
                // player just opened is a bigger undo than they asked for.
                .keyboardShortcut(detailPrinting == nil ? .cancelAction : nil)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RiftboundPalette.regularText.opacity(0.7))
            TextField("Search for card…", text: $searchText)
                .textFieldStyle(.plain)
                .riftFont(.body)
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
            setDetail(printing)
        } label: {
            HStack(spacing: 12) {
                CardArtView(
                    printing: printing,
                    cornerRadius: 4,
                    contentMode: .fill,
                    showsFailureLabel: false,
                    // Battlefields print landscape; stood upright here so
                    // one of them doesn't break the column of thumbnails.
                    uprightsLandscapeArt: true
                )
                .frame(width: 44, height: 62)
                VStack(alignment: .leading, spacing: 2) {
                    Text(printing.name)
                        .riftFont(.heading)
                        .foregroundStyle(RiftboundPalette.regularText)
                    Text(printing.classification.type)
                        .riftFont(.body)
                        .foregroundStyle(RiftboundPalette.regularText.opacity(0.7))
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LibraryRowButtonStyle())
    }
}

/// Hover and press feedback for one row of the library's result list.
///
/// `.buttonStyle(.plain)` gave a row no reaction at all — the only
/// evidence a click had registered was the popup already being open,
/// which is what made opening a card feel abrupt rather than caused. A
/// row that lights under the pointer and presses in under the click does
/// most of that work before the popup animates at all.
private struct LibraryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LibraryRowBody(configuration: configuration)
    }
}

/// A real `View`, not the style building the label directly — `@State`
/// read from inside a `ButtonStyle` struct doesn't track, the same reason
/// `RiftButtonBody` exists over in `RiftboundTheme`.
private struct LibraryRowBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: RiftboundLayout.buttonCornerRadius, style: .continuous)
                    .fill(RiftboundPalette.highlightOverlay.opacity(backgroundOpacity))
            )
            // Shallow on purpose: the row is full-width, so even 2% moves
            // its edges a long way — the same reason `GameToggleButton`
            // scales less than the compact buttons do.
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }

    private var backgroundOpacity: Double {
        if configuration.isPressed { return 0.28 }
        return isHovering ? 0.14 : 0
    }
}
