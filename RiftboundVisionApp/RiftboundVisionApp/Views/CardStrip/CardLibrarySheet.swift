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
    let onClose: () -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var results: [CardPrinting] {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
            ? database.allPrintings
            : database.search(searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Card Library")
                    .font(RiftboundFont.heading)
                    .foregroundStyle(RiftboundPalette.regularText)
                Spacer()
                Button("Close", action: onClose)
                    .buttonStyle(RiftSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }

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
        .padding(20)
        .frame(width: 520, height: 620)
        .background(RiftboundPalette.mainBackground)
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
            selection = printing
            onClose()
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
