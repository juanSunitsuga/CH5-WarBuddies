import SwiftUI
import RiftboundVision

/// Right-hand column: the score, then the Card Library.
///
/// The card it shows is chosen by tapping a detection box on the camera
/// view — `selection` is owned by `ContentView` so the picture and this
/// panel agree on what's being looked at. Search is the way to inspect a
/// card that isn't currently on the table.
///
/// V3 renames the lower half from "Card Details" to "Card Library" and
/// that rename carries a behaviour change: a library isn't empty when
/// nothing is selected. With no selection and no search it now lists the
/// cards the pipeline can currently see on the table, so the column always
/// has something in it and tapping a box *refines* the list rather than
/// filling a blank. The search field, which used to sit in a permanent
/// bottom bar, is now behind the magnifier in the section header exactly
/// as the mockup draws it.
struct DetectedCardsPanel: View {
    @ObservedObject var pipeline: CameraPipelineController
    /// The card tapped on the camera view, or picked from search.
    @Binding var selection: CardPrinting?

    @State private var searchText = ""
    @State private var isSearchFieldShown = false
    @FocusState private var isSearchFocused: Bool

    /// Typing searches the whole catalogue rather than only what's on
    /// camera — otherwise the field could only ever narrow a list that's
    /// already visible.
    private var searchResults: [CardPrinting] {
        pipeline.cardDatabase.search(searchText)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Distinct printings behind the currently-*tracked* cards, oldest
    /// track first. Deduped because several boxes can resolve to the same
    /// printing (two copies of the same rune) and the library should list
    /// a card once.
    ///
    /// Reads `pipeline.trackedObjects`, not `pipeline.detections`, on
    /// purpose. `detections` is the raw, per-poll detector output — no
    /// identity, no occlusion tolerance, and (by design, for the live
    /// on-camera overlay) not run through `ObjectTracker`'s label-vote
    /// stabilization at all. Building this list from it meant every card's
    /// row flickered in and out, and renamed itself, at the raw detector's
    /// own noise level — several times a second, even for a card lying
    /// dead still — because that's exactly what `detections` is supposed
    /// to expose for the overlay. `trackedObjects` is the stabilized
    /// output of the same poll: a card keeps its row through brief
    /// occlusion (a hand passing over it) and its name only changes when
    /// the evidence for a different card is actually decisive, not on
    /// every ambiguous frame.
    ///
    /// Sorted by `TrackedObjectID` rather than relying on the underlying
    /// dictionary's iteration order, which Swift doesn't guarantee stable
    /// across mutations — IDs are assigned in increasing order as cards
    /// first appear, so this reproduces "in detection order" deterministically
    /// instead of by accident.
    private var cardsOnTable: [CardPrinting] {
        var seen = Set<String>()
        var result: [CardPrinting] = []
        for object in pipeline.trackedObjects.sorted(by: { $0.id < $1.id }) {
            guard let label = object.recognizedLabel,
                  let printing = pipeline.cardDatabase.printing(approximatelyNamed: label),
                  seen.insert(printing.id).inserted else { continue }
            result.append(printing)
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                scoreSection
                Rectangle()
                    .fill(RiftboundPalette.elementStroke.opacity(0.25))
                    .frame(height: 1)
                librarySection
            }
            .padding(20)
        }
        // The column now starts level with the header rather than below
        // it, so its own top padding is what keeps "Score" aligned with
        // "Current Turn" instead of riding up against the toolbar.
        .scrollContentBackground(.hidden)
        .frame(width: 362)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RiftboundPalette.secondaryBackground)
    }

    // MARK: - Score

    /// Not collapsible. The reference shows Score and Card Library both
    /// open, one above the other, for the whole game — and a disclosure
    /// chevron on a two-row panel buys nothing: there is no content below
    /// it that collapsing would reveal, so the control could only ever
    /// hide the score from the person trying to read it across a table.
    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Score")
                .font(RiftboundFont.heading)
                .foregroundStyle(RiftboundPalette.regularText)
            ScoreTracker(
                playerScore: $pipeline.playerScore,
                opponentScore: $pipeline.opponentScore
            )
        }
    }

    // MARK: - Card Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Card Library")
                    .font(RiftboundFont.heading)
                    .foregroundStyle(RiftboundPalette.regularText)

                Spacer()

                // Only the magnifier here. Pipeline settings used to sit
                // beside it, which put a developer control in the middle
                // of a player-facing panel and gave this header two
                // unrelated jobs. It lives in the toolbar's diagnostics
                // menu now, with the other two developer affordances.
                iconButton(systemName: "magnifyingglass", label: "Search the card catalogue") {
                    isSearchFieldShown.toggle()
                    if isSearchFieldShown {
                        isSearchFocused = true
                    } else {
                        searchText = ""
                    }
                }
            }

            if isSearchFieldShown {
                searchField
            }

            if isSearching {
                searchResultsList
            } else if let card = selection {
                cardEntry(card, isDetailed: true)
            } else if !cardsOnTable.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(cardsOnTable) { printing in
                        Button {
                            selection = printing
                        } label: {
                            cardEntry(printing, isDetailed: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Tap a card on the camera to see its details, or search the catalogue.")
                    .font(RiftboundFont.body)
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One library row: artwork on the left, name and printed attributes
    /// on the right — the mockup's Type / Rarity / Cost / Ability stack.
    /// `isDetailed` adds the flavour text, which is what the selected card
    /// gets and a browsing row doesn't.
    private func cardEntry(_ printing: CardPrinting, isDetailed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                artwork(for: printing, width: 132, height: 178)

                VStack(alignment: .leading, spacing: 6) {
                    Text(printing.name)
                        .font(RiftboundFont.heading)
                        .foregroundStyle(RiftboundPalette.regularText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)

                    attribute("Type", printing.classification.type)
                    if let rarity = printing.classification.rarity {
                        attribute("Rarity", rarity)
                    }
                    if let energy = printing.attributes.energy {
                        attribute("Cost", "\(energy)")
                    }
                    if let might = printing.attributes.might {
                        attribute("Might", "\(might)")
                    }
                    if !printing.text.plain.isEmpty {
                        attribute("Ability", printing.text.plain, isMultiline: true)
                    }
                }
            }

            if isDetailed, let flavour = printing.text.flavour, !flavour.isEmpty {
                Text(flavour)
                    .font(RiftboundFont.body)
                    .italic()
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
    }

    /// Label column is a fixed width so Type/Rarity/Cost/Ability line up
    /// down the panel the way they do in the mockup — with an intrinsic
    /// width they stagger as soon as one label is longer than the rest.
    private func attribute(_ label: String, _ value: String, isMultiline: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(RiftboundFont.heading)
                .foregroundStyle(RiftboundPalette.regularText)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(RiftboundFont.body)
                .foregroundStyle(RiftboundPalette.regularText.opacity(0.8))
                .lineLimit(isMultiline ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RiftboundPalette.regularText.opacity(0.7))
            TextField("Search for card…", text: $searchText)
                .textFieldStyle(.plain)
                .font(RiftboundFont.body)
                .foregroundStyle(RiftboundPalette.regularText)
                .focused($isSearchFocused)
            if isSearching {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(RiftboundPalette.regularText.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(Capsule().stroke(RiftboundPalette.elementStroke, lineWidth: 1))
    }

    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if searchResults.isEmpty {
                Text("No cards match “\(searchText)”.")
                    .font(RiftboundFont.body)
                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.55))
            } else {
                ForEach(searchResults) { printing in
                    Button {
                        selection = printing
                        searchText = ""
                        isSearchFieldShown = false
                    } label: {
                        HStack(spacing: 8) {
                            artwork(for: printing, width: 32, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(printing.name)
                                    .font(RiftboundFont.subheading)
                                    .foregroundStyle(RiftboundPalette.regularText)
                                    .lineLimit(1)
                                Text(printing.classification.type)
                                    .font(RiftboundFont.body)
                                    .foregroundStyle(RiftboundPalette.regularText.opacity(0.55))
                            }
                            Spacer()
                        }
                        .padding(6)
                        .background(RiftboundPalette.elementShadow.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Chrome

    private func iconButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RiftboundPalette.regularText)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Uses main's `CardArtView`, which distinguishes "still loading" from
    /// "fetch failed" — a distinction worth keeping, since collapsing them
    /// into one dark placeholder is what hid the sandbox entitlement bug.
    /// The `elementStroke` frame around it is the mockup's own hairline,
    /// which is what stops dark artwork from bleeding into the panel blue.
    private func artwork(for printing: CardPrinting, width: CGFloat, height: CGFloat) -> some View {
        CardArtView(
            printing: printing,
            cornerRadius: 4,
            contentMode: .fill,
            showsFailureLabel: width > 64
        )
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(RiftboundPalette.elementStroke, lineWidth: 2)
        )
    }
}
