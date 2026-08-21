import SwiftUI

/// Draws the *tracker's* view of the table: one dot at each tracked card's
/// centroid, tagged with its stable `TrackedObjectID`.
///
/// This is deliberately not the same thing as `LiveDetectionOverlayView`,
/// which draws raw per-frame detections and carries no identity at all.
/// The two look nearly identical while tracking is healthy — and that's
/// the point: when it breaks, the boxes stay exactly where they were while
/// the ID under the dot changes, which is invisible unless the ID is drawn.
///
/// The centroid is also the point tracking actually reasons about: zone
/// membership is decided by which calibrated polygon contains this dot
/// (`ZoneMapper.zone(for:)`), not by the bounding box. So a card whose dot
/// sits outside every zone resolves to `.unknown` and its events are
/// dropped, however cleanly the box is drawn around it.
public struct TrackedObjectOverlayView: View {
    let objects: [TrackedObject]
    /// Draws each dot in its zone's colour, so a card that has drifted
    /// into the wrong region is obvious without reading any text.
    let showsZoneColor: Bool

    public init(objects: [TrackedObject], showsZoneColor: Bool = true) {
        self.objects = objects
        self.showsZoneColor = showsZoneColor
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(objects, id: \.id) { object in
                marker(for: object)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func marker(for object: TrackedObject) -> some View {
        let tint = showsZoneColor ? color(for: object.currentZone) : .cyan

        ZStack {
            // Halo, so the dot stays visible over both card art and the
            // pale mat.
            Circle()
                .fill(tint.opacity(0.25))
                .frame(width: 34, height: 34)
            Circle()
                .fill(tint)
                .frame(width: 14, height: 14)
            Circle()
                .stroke(PlaymatPalette.pureWhite, lineWidth: 2)
                .frame(width: 14, height: 14)
        }
        .overlay(alignment: .top) {
            Text("#\(object.id)")
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundStyle(PlaymatPalette.pureWhite)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint, in: Capsule())
                .overlay(Capsule().stroke(PlaymatPalette.scrim, lineWidth: 1))
                .fixedSize()
                .offset(y: -30)
        }
        .position(x: object.center.x, y: object.center.y)
        .opacity(object.isVisible ? 1 : 0.4)
    }

    /// Distinct hue per zone; `.unknown` is red because a dot landing
    /// there means the card is outside every calibrated region and its
    /// events are being dropped.
    private func color(for zone: Zone) -> Color {
        switch zone {
        case .player1Hand, .player2Hand: return .cyan
        case .base: return .green
        case .battlefield: return .yellow
        case .runeArea, .runeDeck: return .purple
        case .mainDeck: return .blue
        case .trash: return .brown
        case .legend, .champion: return .mint
        case .unknown: return .red
        }
    }
}
