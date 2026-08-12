import SwiftUI
import RiftboundVision

/// Right-hand sidebar, laid out to match the RiftChamps mockup: a
/// collapsible score tracker on top, a collapsible card-details section
/// below it, and a persistent search / settings / close bar pinned to the
/// bottom.
///
/// The card list is deliberately just a live view of `pipeline.detections`
/// — this architecture has no persistent per-object identity (see
/// `CameraPipelineController`'s doc comment), so there's no stable "row"
/// to track across polls the way the old tracked-pipeline sidebar had. The
/// list refreshes every ~0.35s along with detection itself, and can show
/// the same card twice if it's genuinely detected twice in one frame (two
/// physical copies on the table, or a momentary double-detection) — no
/// dedup logic tries to paper over that, since without tracking there's no
/// principled way to tell those two cases apart.
struct DetectedCardsPanel: View {
    @ObservedObject var pipeline: CameraPipelineController
    @State private var detailPrinting: CardPrinting?
    @State private var selected: CardPrinting?
    @State private var searchText = ""
    @State private var isScoreExpanded = true
    @State private var isDetailsExpanded = true
    @State private var isShowingSettings = false

    private static let panelBackground = Color(red: 0.11, green: 0.23, blue: 0.33)

    /// Runes are excluded — this panel is specifically about card
    /// identity/text lookup, same scope as the tracked-pipeline sidebar
    /// it replaces.
    private var recognizedCards: [(detection: Detection, printing: CardPrinting)] {
        pipeline.detections
            .filter { $0.type == .card }
            .compactMap { detection in
                guard let label = detection.recognizedLabel,
                      let printing = pipeline.cardDatabase.printing(approximatelyNamed: label) else {
                    return nil
                }
                return (detection, printing)
            }
    }

    /// When the user types, the panel searches the whole card database
    /// rather than only what's currently on camera — otherwise the search
    /// field could only ever narrow a list that's already visible.
    private var searchResults: [CardPrinting] {
        pipeline.cardDatabase.search(searchText)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whichever card the detail section should describe: an explicit
    /// selection wins, otherwise the first thing currently detected.
    private var focusedCard: CardPrinting? {
        selected ?? recognizedCards.first?.printing
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
        .sheet(item: $detailPrinting) { printing in
            CardDetailView(printing: printing, onClose: { detailPrinting = nil })
        }
        .popover(isPresented: $isShowingSettings) {
            PipelineSettingsView(pipeline: pipeline)
        }
    }

    // MARK: - Sections

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

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Card Details", isExpanded: $isDetailsExpanded)

            if isDetailsExpanded {
                if isSearching {
                    searchResultsList
                } else if let card = focusedCard {
                    cardDetail(card)
                } else {
                    Text("No cards recognized right now.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }

                if !isSearching && !recognizedCards.isEmpty {
                    detectedList
                }
            }
        }
    }

    private func cardDetail(_ printing: CardPrinting) -> some View {
        HStack(alignment: .top, spacing: 14) {
            artwork(for: printing, width: 158, height: 213)

            VStack(alignment: .leading, spacing: 8) {
                Text(printing.name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                attribute("Type", printing.classification.type)
                if let energy = printing.attributes.energy {
                    attribute("Energy", "\(energy)")
                }
                if let might = printing.attributes.might {
                    attribute("Might", "\(might)")
                }
                if let rarity = printing.classification.rarity {
                    attribute("Rarity", rarity)
                }

                Button("More details") { detailPrinting = printing }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 1))
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

    private var detectedList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ON CAMERA")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 6)

            ForEach(Array(recognizedCards.enumerated()), id: \.offset) { _, entry in
                row(
                    printing: entry.printing,
                    subtitle: "\(Int((entry.detection.confidence * 100).rounded()))% confidence"
                )
            }
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
                    row(printing: printing, subtitle: printing.classification.type)
                }
            }
        }
    }

    private func row(printing: CardPrinting, subtitle: String) -> some View {
        Button {
            selected = printing
        } label: {
            HStack(spacing: 8) {
                artwork(for: printing, width: 32, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(printing.name)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(6)
            .background(printing.id == selected?.id ? .white.opacity(0.14) : .white.opacity(0.06))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
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
            circleButton(systemName: "xmark") { selected = nil; searchText = "" }
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
