import SwiftUI
import RiftboundVision

/// Right-hand sidebar: the score, and details for one card.
///
/// The card it shows is chosen by tapping a detection box on the camera
/// view — `selection` is owned by `ContentView` so the picture and this
/// panel agree on what's being looked at. Search is the way to inspect a
/// card that isn't currently on the table.
///
/// Previously this also carried an on-camera list, a tracking log, an
/// event log and a trash list. Those were debugging surfaces built while
/// tracking was being fixed; with tracking working they crowded out the
/// one thing a player actually wants mid-game, which is what the card in
/// front of them does.
struct DetectedCardsPanel: View {
    @ObservedObject var pipeline: CameraPipelineController
    /// The card tapped on the camera view, or picked from search.
    @Binding var selection: CardPrinting?

    @State private var searchText = ""
    @State private var isScoreExpanded = true
    @State private var isShowingSettings = false

    private static let panelBackground = Color(red: 0.11, green: 0.23, blue: 0.33)

    /// Typing searches the whole catalogue rather than only what's on
    /// camera — otherwise the field could only ever narrow a list that's
    /// already visible.
    private var searchResults: [CardPrinting] {
        pipeline.cardDatabase.search(searchText)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    scoreSection
                    Divider().overlay(.white.opacity(0.15))
                    detailsSection
                }
                .padding(16)
            }

            bottomBar
        }
        .frame(width: 362)
        .background(Self.panelBackground)
        .popover(isPresented: $isShowingSettings) {
            PipelineSettingsView(pipeline: pipeline)
        }
    }

    // MARK: - Score

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Score", isExpanded: $isScoreExpanded)
            if isScoreExpanded {
                ScoreTracker(
                    playerScore: $pipeline.playerScore,
                    opponentScore: $pipeline.opponentScore
                )
            }
        }
    }

    // MARK: - Card details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Card Details")
                .font(.headline)
                .foregroundStyle(.white)

            if isSearching {
                searchResultsList
            } else if let card = selection {
                cardDetail(card)
            } else {
                Text("Tap a card on the camera to see its details.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cardDetail(_ printing: CardPrinting) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                artwork(for: printing, width: 150, height: 202)

                VStack(alignment: .leading, spacing: 8) {
                    Text(printing.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    attribute("Type", printing.classification.type)
                    if let supertype = printing.classification.supertype, !supertype.isEmpty {
                        attribute("Super", supertype)
                    }
                    if let energy = printing.attributes.energy {
                        attribute("Energy", "\(energy)")
                    }
                    if let might = printing.attributes.might {
                        attribute("Might", "\(might)")
                    }
                    if let rarity = printing.classification.rarity {
                        attribute("Rarity", rarity)
                    }
                }
            }

            // The panel is only about one card now, so there's room for the
            // thing that actually decides play: the printed rules text.
            if !printing.text.plain.isEmpty {
                Text(printing.text.plain)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }

            if let flavour = printing.text.flavour, !flavour.isEmpty {
                Text(flavour)
                    .font(.caption.italic())
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func attribute(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if searchResults.isEmpty {
                Text("No cards match “\(searchText)”.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ForEach(searchResults) { printing in
                    Button {
                        selection = printing
                        searchText = ""
                    } label: {
                        HStack(spacing: 8) {
                            artwork(for: printing, width: 32, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(printing.name)
                                    .font(.callout)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(printing.classification.type)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                        }
                        .padding(6)
                        .background(.white.opacity(0.06))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Chrome

    private func sectionHeader(_ title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
        } label: {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.8))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.7))
                TextField("Search for card…", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                if isSearching {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))

            circleButton(systemName: "gearshape.fill") { isShowingSettings = true }
            circleButton(systemName: "xmark") { selection = nil; searchText = "" }
        }
        .padding(16)
    }

    private func circleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func artwork(for printing: CardPrinting, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let url = printing.media.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.black.opacity(0.55)
                }
            } else {
                Color.black.opacity(0.55)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
