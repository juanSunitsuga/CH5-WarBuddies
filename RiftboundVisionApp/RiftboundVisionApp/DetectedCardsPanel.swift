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
    @State private var isTrackingExpanded = true
    /// Collapsed by default — tracking is what's being debugged right now,
    /// and the rules-engine verdicts are downstream noise until it's right.
    @State private var isLogExpanded = false
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
                    Divider().overlay(.white.opacity(0.15))
                    trackingSection
                    Divider().overlay(.white.opacity(0.15))
                    logSection
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

    /// The vision layer's own log: track identity and zone transitions, as
    /// the tracker actually saw them. Shown above the Event Log because
    /// the Event Log is downstream of a filter — it can't show a card
    /// entering the Rune Area or Trash at all, so an empty Event Log next
    /// to a busy Tracking Log localises the problem immediately.
    private var trackingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Tracking Log", isExpanded: $isTrackingExpanded)
                Text("\(pipeline.liveTrackCount) tracked")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }

            if isTrackingExpanded {
                if pipeline.trackingEvents.isEmpty {
                    Text("No tracking events yet. Press Start, then move a card.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    ForEach(pipeline.trackingEvents) { entry in
                        trackingRow(entry)
                    }
                }
            }
        }
    }

    private func trackingRow(_ entry: TrackingLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon(for: entry.kind))
                .font(.caption)
                .foregroundStyle(color(for: entry.kind))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Track identity — the number to watch. A card that
                    // gets a new one every time it's touched is being
                    // re-created instead of followed.
                    Text("#\(entry.trackID)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))

                    Text(entry.card)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text(entry.transition)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(color(for: entry.kind))
                    .fixedSize(horizontal: false, vertical: true)

                if !entry.wasForwarded {
                    Text("not sent to the rules engine — this zone has no representation yet")
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                Text("\(Int((entry.confidence * 100).rounded()))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(8)
        .background(.white.opacity(entry.wasForwarded ? 0.05 : 0.09), in: RoundedRectangle(cornerRadius: 6))
    }

    private func icon(for kind: TrackingLogEntry.Kind) -> String {
        switch kind {
        case .appeared: return "plus.circle.fill"
        case .moved: return "arrow.right.circle.fill"
        case .rotated: return "rotate.right.fill"
        case .disappeared: return "minus.circle.fill"
        }
    }

    private func color(for kind: TrackingLogEntry.Kind) -> Color {
        switch kind {
        case .appeared: return .green
        case .moved: return .cyan
        case .rotated: return .purple
        case .disappeared: return .orange
        }
    }

    /// Every table event the pipeline produced, newest first, paired with
    /// what the engine decided about it. The two halves are shown
    /// separately on purpose: when the camera clearly saw a move but the
    /// verdict is "nothing to do", the disagreement between the two lines
    /// is what points at the stage that's wrong.
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Event Log", isExpanded: $isLogExpanded)
                if !pipeline.instructions.isEmpty {
                    Text("\(pipeline.instructions.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if isLogExpanded {
                if pipeline.instructions.isEmpty {
                    Text("No table events yet. Move a card on the mat to see one.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    ForEach(pipeline.instructions) { entry in
                        logRow(entry)
                    }
                }
            }
        }
    }

    private func logRow(_ entry: InstructionLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.verdict.iconName)
                .font(.caption)
                .foregroundStyle(entry.verdict.tint)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                // What the camera saw.
                Text(entry.eventSummary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                // What the engine made of it.
                Text(entry.headline)
                    .font(.caption2)
                    .foregroundStyle(entry.verdict.tint.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = entry.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
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
                    subtitle: "\(Int((entry.detection.confidence * 100).rounded()))% confidence",
                    // Rules 592–593. Uses the printing-aware check, not the
                    // identity-free `CGRect.cardStance` fallback — this row
                    // already knows which card it is, so a landscape
                    // Battlefield isn't misread as tapped.
                    isExhausted: entry.printing.isExhausted(observedBoundingBox: entry.detection.boundingBox)
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

    private func row(printing: CardPrinting, subtitle: String, isExhausted: Bool = false) -> some View {
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
                    HStack(spacing: 6) {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                        if isExhausted {
                            badge("Exhausted", color: .orange)
                        }
                    }
                }
                Spacer()
            }
            .padding(6)
            .background(printing.id == selected?.id ? .white.opacity(0.14) : .white.opacity(0.06))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.25))
            .foregroundStyle(color)
            .clipShape(Capsule())
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
