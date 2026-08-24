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
    /// Turn a Battlefield's landscape art upright so it fills a portrait
    /// slot like every other card.
    ///
    /// Opt-in, because it's only right where cards are shown as a
    /// *uniform row* — the library list and the table strip, where one
    /// card printed the other way round makes the whole row look broken.
    /// Somewhere a card is shown on its own, like the library's detail
    /// popup, it should stay the shape it is actually printed
    /// (`CardOrientation` notes Battlefields as the one landscape type),
    /// because there is no row for it to disagree with.
    var uprightsLandscapeArt = false

    private var isRotated: Bool {
        uprightsLandscapeArt && printing.orientation == .landscape
    }

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
        .modifier(UprightLandscapeArt(isActive: isRotated))
        // Claims the caller's slot as this view's own layout size before
        // clipping to it. `aspectRatio(contentMode: .fill)` reports a
        // layout size that *overflows* the proposal on one axis, and the
        // clip shape is built from whatever bounds it's handed — so
        // without this the rounded rect was being cut at the overflowed
        // size and a landscape card visibly spilled out past the ends of
        // its row instead of being cropped into it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Rotates landscape art a quarter turn so it stands upright in a
/// portrait slot, swapping the frame's axes so it still *occupies* the
/// portrait slot rather than the landscape one it was drawn at.
///
/// `.rotationEffect` alone would not do: it's a render-time transform
/// that leaves the view's reported layout size unrotated, so the art
/// would turn but the space it reserves would stay landscape-shaped and
/// push the row around it out of line. Drawing into the *swapped* frame
/// first and then centring the result with `.position` is what makes the
/// footprint match what you see — `.position` places a view by its
/// centre and ignores its layout size, which is exactly the mismatch
/// being worked around here.
private struct UprightLandscapeArt: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            GeometryReader { geo in
                content
                    .frame(width: geo.size.height, height: geo.size.width)
                    .rotationEffect(.degrees(90))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        } else {
            content
        }
    }
}
