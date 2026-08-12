import SwiftUI
import RiftboundVision

/// Right-hand sidebar: every tracked card, grouped "You" / "Opponent" by
/// which half of the calibrated mat it's currently on — the SpellTable-
/// style panel from the reference screenshot. Tap a row to either assign
/// it a card (if unidentified — real recognition doesn't exist yet, see
/// `CameraPipelineController.cardAssignments`) or see its full info (if
/// already assigned).
struct TrackedCardsPanel: View {
    @ObservedObject var pipeline: CameraPipelineController
    @State private var assigningObjectID: TrackedObjectID?
    @State private var detailPrinting: CardPrinting?

    private var mine: [CameraPipelineController.TrackedCardEntry] {
        pipeline.trackedCards.filter { $0.owner == .player1 }
    }
    private var opponents: [CameraPipelineController.TrackedCardEntry] {
        pipeline.trackedCards.filter { $0.owner == .player2 }
    }
    private var unplaced: [CameraPipelineController.TrackedCardEntry] {
        pipeline.trackedCards.filter { $0.owner == nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section(title: "You", entries: mine)
                section(title: "Opponent", entries: opponents)
                if !unplaced.isEmpty {
                    section(title: "Off-mat / uncalibrated", entries: unplaced)
                }
            }
            .padding(12)
        }
        .frame(width: 260)
        .background(.black.opacity(0.85))
        .sheet(item: Binding(
            get: { assigningObjectID.map { AssignmentTarget(objectID: $0) } },
            set: { assigningObjectID = $0?.objectID }
        )) { target in
            CardAssignmentSheet(database: pipeline.cardDatabase) { printing in
                pipeline.assignCard(printing, to: target.objectID)
                assigningObjectID = nil
            } onCancel: {
                assigningObjectID = nil
            }
        }
        .sheet(item: $detailPrinting) { printing in
            CardDetailView(printing: printing) { detailPrinting = nil }
        }
    }

    @ViewBuilder
    private func section(title: String, entries: [CameraPipelineController.TrackedCardEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.6))
                ForEach(entries) { entry in
                    row(for: entry)
                }
            }
        }
    }

    private func row(for entry: CameraPipelineController.TrackedCardEntry) -> some View {
        Button {
            if let printing = entry.printing {
                detailPrinting = printing
            } else {
                assigningObjectID = entry.id
            }
        } label: {
            HStack(spacing: 8) {
                thumbnail(for: entry.printing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.printing?.name ?? "Unidentified (#\(entry.id))")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if entry.printing == nil {
                            Text("Tap to assign")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        if entry.object.orientation == .exhausted {
                            badge("Exhausted", color: .orange)
                        }
                        if !entry.object.underlaidCardIDs.isEmpty {
                            badge("+\(entry.object.underlaidCardIDs.count) under", color: .blue)
                        }
                    }
                }
                Spacer()
            }
            .padding(6)
            .background(.white.opacity(0.06))
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

    @ViewBuilder
    private func thumbnail(for printing: CardPrinting?) -> some View {
        if let url = printing?.media.imageURL {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 32, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 32, height: 44)
        }
    }
}

private struct AssignmentTarget: Identifiable {
    let objectID: TrackedObjectID
    var id: TrackedObjectID { objectID }
}

/// Manual "which card is this" picker — stands in for real recognition.
/// Searches `CardDatabase.search(_:)`, which is a plain case-insensitive
/// name substring match over the bundled proving-ground decks; only cards
/// in one of those 4 decks are findable here (see `CardDatabaseLoader`).
private struct CardAssignmentSheet: View {
    let database: CardDatabase
    let onSelect: (CardPrinting) -> Void
    let onCancel: () -> Void

    @State private var query = ""

    private var results: [CardPrinting] {
        query.isEmpty ? database.allPrintings : database.search(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Assign a Card").font(.headline)
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            }
            TextField("Search by name…", text: $query)
                .textFieldStyle(.roundedBorder)

            List(results) { printing in
                Button {
                    onSelect(printing)
                } label: {
                    HStack {
                        Text(printing.name)
                        Spacer()
                        Text(printing.classification.type).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 420)
    }
}
