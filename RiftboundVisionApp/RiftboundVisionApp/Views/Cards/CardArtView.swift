import SwiftUI
import RiftboundVision

/// A card's artwork, with each outcome looking like itself.
///
/// Defined once and used by both the sidebar list and the detail panel.
/// They had grown separate copies, and both made the same mistake: the
/// two-closure `AsyncImage` collapses "still loading" and "failed" into one
/// placeholder, so a fetch that never succeeds is indistinguishable from
/// one still in flight. Both placeholders were dark fills, so on a dark
/// panel every card rendered as a black rectangle whether the network was
/// slow, the URL was missing, or — as was actually the case — the App
/// Sandbox was denying the request outright for want of
/// `com.apple.security.network.client`.
///
/// A failure that looks like loading is a bug you can stare straight at
/// without seeing, which is the argument for splitting the phases even
/// though the entitlement is now fixed.
struct CardArtView: View {
    let printing: CardPrinting
    var cornerRadius: CGFloat = 6
    /// `.fit` shows the whole card (detail panel); `.fill` crops to a tile
    /// (list thumbnails).
    var contentMode: ContentMode = .fit
    /// Thumbnails are too small for an icon and a caption, so they get the
    /// plain fill.
    var showsFailureLabel = true

    var body: some View {
        Group {
            if let url = printing.media.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholder(icon: "wifi.exclamationmark", label: "Art unavailable")
                    case .empty:
                        ZStack {
                            fill
                            ProgressView().controlSize(.small)
                        }
                    @unknown default:
                        placeholder(icon: "photo", label: "No art")
                    }
                }
            } else {
                placeholder(icon: "photo", label: "No art")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var fill: some View {
        RoundedRectangle(cornerRadius: cornerRadius).fill(Color.gray.opacity(0.2))
    }

    @ViewBuilder
    private func placeholder(icon: String, label: String) -> some View {
        ZStack {
            fill
            if showsFailureLabel {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
