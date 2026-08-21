import SwiftUI
import AppKit

/// Draws the Riftbound playmat's zone outlines over the camera feed — the
/// "overlay is a Riftbound playmat" piece. In `isEditable` mode, 4 corner
/// handles let the user drag the template into alignment with their
/// physical mat; that's the entire calibration UI, matching the
/// "calibrated once, not detected by ML" approach used throughout this
/// layer.
/// The bundle holding this package's own resources. `Bundle.module` is
/// only synthesized inside the target that declares the resources, so a
/// test target can't reach the border-art PNGs without this — see
/// `PlaymatArtworkFitTests`, which measures them.
enum RiftboundVisionResources {
    static let bundle = Bundle.module
}

/// The handful of design-board colours this package draws with.
///
/// The app target owns the naming layer (`RiftboundPalette` in
/// `RiftboundTheme.swift`), but `RiftboundVision` is a package the app
/// depends on and can't import back the other way — nor can it read the
/// app's `Assets.xcassets`, which is a target resource, not a shared one.
///
/// So this module ships `Resources/Palette.xcassets`: the same swatch
/// names, the same values, loaded through `Bundle.module`. Two catalogues
/// is a real duplication and the honest cost of the module boundary; what
/// keeps it from drifting silently is that both are *named* catalogues
/// with identical colour-set names, so changing a swatch in one and not
/// the other is a visible diff rather than a buried literal. Grep both
/// when the board moves.
enum PlaymatPalette {
    /// #1C3449 — shadow/stroke for elements.
    static let elementShadow = Color("MainBackground", bundle: .module)
    /// #CEA73F — highlight overlay.
    static let highlightOverlay = Color("HighlightOverlay", bundle: .module)
    /// #D5A250 — playmat overlay.
    static let playmatOverlay = Color("PlaymatOverlay", bundle: .module)
    /// #CBCBCB — disabled element stroke.
    static let disabledElementStroke = Color("DisabledElementStroke", bundle: .module)
    /// #FFF2D6 — regular text.
    static let regularText = Color("RegularText", bundle: .module)
    /// #FFFFFF — pure white, for overlay marks that sit on the photograph
    /// itself rather than on any of the board's own colours.
    static let pureWhite = Color("PureWhite", bundle: .module)
    /// #000000 at 20% — the board's one darkening value.
    static let scrim = Color("Scrim", bundle: .module)
}

public struct PlaymatOverlayView: View {
    @Binding private var calibration: PlaymatCalibration
    private let isEditable: Bool
    private let showLabels: Bool
    /// Which zone layout to draw — defaults to the single-player mat
    /// (`RiftboundPlaymatTemplate.singlePlayerZones()`), the one
    /// currently in active use. Pass `.twoPlayerZones` to go back to the
    /// shared-mat layout.
    private let template: [PlaymatZoneTemplate]

    public init(
        calibration: Binding<PlaymatCalibration>,
        isEditable: Bool,
        showLabels: Bool = true,
        template: [PlaymatZoneTemplate] = RiftboundPlaymatTemplate.singlePlayerZones()
    ) {
        self._calibration = calibration
        self.isEditable = isEditable
        self.showLabels = showLabels
        self.template = template
    }

    /// The "RiftChamps" mockup's hand-drawn gold border frames — not
    /// shape-locked art in principle (each is just a sketchy-line texture
    /// stretched to whatever box it's drawn into), but stretching one
    /// *far* past its own native aspect visibly smears its corner accents
    /// (confirmed against a real render: Rectangle 1 — a narrow,
    /// near-square 121×164 texture — stretched across the full-width Hand
    /// zone turned its corner strokes into long vertical streaks). So the
    /// mapping is by actual zone shape, not a single default:
    ///   - Rectangle 2 (394×164, landscape): Battlefield
    ///   - Rectangle 3 (520×164, wider landscape): Base and Rune Area —
    ///     both wide rows the same general proportions as Base
    ///   - Rectangle 4 (645×164, widest): Hand — wider than either of the
    ///     above, and the zone most prone to the stretching artifact
    ///   - Rectangle 1 (121×164, narrow/near-square): everything else
    ///     (Legend, Champion, Main Deck, Rune Deck, Trash) — zones that
    ///     are actually close to this texture's own native aspect
    private static let battlefieldFrame = loadFrame("Rectangle 2")
    private static let baseFrame = loadFrame("Rectangle 3")
    private static let handFrame = loadFrame("Rectangle 4")
    private static let defaultFrame = loadFrame("Rectangle 1")

    /// Prefers the host app's asset catalog (`Assets.xcassets`), falling
    /// back to this package's own bundled copy. `NSImage(named:)` searches
    /// the *main* bundle, so in `RiftboundVisionApp` this picks up the
    /// catalog entry; in tests and previews — where there is no app
    /// catalog — it falls through to `Bundle.module`, which is why the
    /// package keeps its copies rather than deleting them.
    private static func loadFrame(_ name: String) -> Image {
        if let catalogImage = NSImage(named: name) {
            return Image(nsImage: catalogImage)
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let nsImage = NSImage(contentsOf: url) else {
            // Shouldn't happen — these are bundled resources, not
            // user-supplied data — but a missing/renamed asset shouldn't
            // crash the calibration overlay; fall back to a visible
            // placeholder instead.
            return Image(systemName: "questionmark.square.dashed")
        }
        return Image(nsImage: nsImage)
    }

    private func frame(for zone: Zone) -> Image {
        switch zone {
        case .battlefield: return Self.battlefieldFrame
        case .base, .runeArea: return Self.baseFrame
        case .player1Hand, .player2Hand: return Self.handFrame
        default: return Self.defaultFrame
        }
    }

    public var body: some View {
        ZStack {
            Canvas { context, _ in
                for zoneTemplate in template {
                    let points = zoneTemplate.normalizedPolygon.map(calibration.map)
                    // Draw a subtle light-beige filled background for the
                    // zone, matching the lighter playmat look in the
                    // reference image, then draw the textured border frame
                    // on top.
                    let rect = boundingRect(of: points)
                    context.draw(frame(for: zoneTemplate.zone), in: rect)

                    if showLabels {
                        let anchorPoint = labelAnchor(of: rect)
                        // Cream halo (offsets) under a dark centre, so the
                        // label survives being drawn over both pale mat and
                        // dark card art.
                        //
                        // `Font.custom` silently falls back to the system
                        // face when Sora isn't registered, which is the
                        // right behaviour here: this package is also built
                        // by the test target, which has no app bundle to
                        // load fonts from.
                        //
                        // 24pt, not the design system's 15 — this is drawn
                        // in the *camera frame's* pixel space and then
                        // scaled by `ContentView`'s aspect-fit factor, so
                        // its number has no fixed relationship to on-screen
                        // points. Sizing it at 15 made it illegible.
                        let text = Text(label(for: zoneTemplate)).font(.custom("Sora-Bold", size: 24))
                        for offset in [CGPoint(x: -1.5, y: -1.5), CGPoint(x: 1.5, y: -1.5), CGPoint(x: -1.5, y: 1.5), CGPoint(x: 1.5, y: 1.5)] {
                            context.draw(
                                text.foregroundStyle(PlaymatPalette.regularText),
                                at: CGPoint(x: anchorPoint.x + offset.x, y: anchorPoint.y + offset.y)
                            )
                        }
                        context.draw(text.foregroundStyle(PlaymatPalette.elementShadow), at: anchorPoint)
                    }
                }

                // Intentionally remove the bright yellow outer boundary
                // stroke used for debugging; the reference overlay is
                // visually quieter.
            }
            .allowsHitTesting(false)

            if isEditable {
                handle(.topLeft)
                handle(.topRight)
                handle(.bottomRight)
                handle(.bottomLeft)
                moveHandle
            }
        }
    }

    /// Which corner a handle drives. Dragging one resizes the rectangle
    /// with the *opposite* corner pinned, so the mat only ever gets wider
    /// or taller — it can never be sheared into a parallelogram.
    private enum Corner {
        case topLeft, topRight, bottomRight, bottomLeft
    }

    /// Corner drags used to set that corner's raw location, which let the
    /// four points form any quadrilateral at all. One nudge and the mat
    /// went crooked, every zone inside it sheared with it, and the
    /// calibrated regions stopped matching what the camera saw — the
    /// overlay "disorienting" on every move. Resizing an axis-aligned
    /// rectangle instead keeps the grid square by construction.
    ///
    /// This gives up free-quad perspective correction for a camera mounted
    /// at an angle. `PlaymatCalibration.map` still interpolates all four
    /// corners, so restoring it later is a UI change, not a model one.
    private func handle(_ corner: Corner) -> some View {
        let position = point(for: corner)
        return Circle()
            .fill(PlaymatPalette.highlightOverlay)
            .overlay(Circle().stroke(PlaymatPalette.elementShadow, lineWidth: 1))
            .frame(width: 18, height: 18)
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    resize(corner: corner, to: value.location)
                }
            )
    }

    /// Drags the whole mat without changing its size — separate from the
    /// corners so repositioning can't accidentally reshape it.
    private var moveHandle: some View {
        let rect = currentRect
        return Circle()
            .fill(PlaymatPalette.highlightOverlay.opacity(0.85))
            .overlay(Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").font(.system(size: 11, weight: .bold)).foregroundStyle(PlaymatPalette.elementShadow))
            .frame(width: 26, height: 26)
            .position(x: rect.midX, y: rect.midY)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let dx = value.location.x - rect.midX
                    let dy = value.location.y - rect.midY
                    apply(rect.offsetBy(dx: dx, dy: dy))
                }
            )
    }

    private var currentRect: CGRect {
        let xs = [calibration.topLeft.x, calibration.topRight.x, calibration.bottomRight.x, calibration.bottomLeft.x]
        let ys = [calibration.topLeft.y, calibration.topRight.y, calibration.bottomRight.y, calibration.bottomLeft.y]
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func point(for corner: Corner) -> CGPoint {
        let rect = currentRect
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        }
    }

    private func resize(corner: Corner, to location: CGPoint) {
        let rect = currentRect
        // A minimum keeps a fast drag past the opposite edge from
        // inverting the mat (which would mirror every zone).
        let minimumSize: CGFloat = 40
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY

        switch corner {
        case .topLeft:
            minX = min(location.x, maxX - minimumSize)
            minY = min(location.y, maxY - minimumSize)
        case .topRight:
            maxX = max(location.x, minX + minimumSize)
            minY = min(location.y, maxY - minimumSize)
        case .bottomRight:
            maxX = max(location.x, minX + minimumSize)
            maxY = max(location.y, minY + minimumSize)
        case .bottomLeft:
            minX = min(location.x, maxX - minimumSize)
            maxY = max(location.y, minY + minimumSize)
        }

        apply(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    private func apply(_ rect: CGRect) {
        calibration = PlaymatCalibration(
            topLeft: CGPoint(x: rect.minX, y: rect.minY),
            topRight: CGPoint(x: rect.maxX, y: rect.minY),
            bottomRight: CGPoint(x: rect.maxX, y: rect.maxY),
            bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        )
    }

    /// Whether zone labels need a "(P1)"/"(P2)" suffix.
    ///
    /// Only the two-player template puts both seats' zones on one mat; in
    /// the single-player layout every owned zone belongs to the same
    /// person, so the suffix repeats the same fact on every box and tells
    /// the reader nothing. Derived from the template rather than hardcoded
    /// so switching to `twoPlayerZones` brings the suffix back on its own.
    private var showsSeatSuffix: Bool {
        // `Player` is Equatable but not Hashable, so this asks the
        // question directly rather than counting a Set.
        let owners = template.compactMap(\.owner)
        return owners.contains(.player1) && owners.contains(.player2)
    }

    /// Same idea for Battlefield slot numbers: "#0" only earns its place
    /// when there is more than one Battlefield region to tell apart.
    private var showsBattlefieldSlot: Bool {
        template.filter { $0.battlefieldSlot != nil }.count > 1
    }

    private func label(for template: PlaymatZoneTemplate) -> String {
        var text = Self.displayName(for: template.zone)

        if showsBattlefieldSlot, let slot = template.battlefieldSlot {
            text += " #\(slot)"
        }

        guard showsSeatSuffix else { return text }
        switch template.owner {
        case .player1: return "\(text) (P1)"
        case .player2: return "\(text) (P2)"
        case nil: return text
        }
    }

    /// Table-facing zone names, matching the wording printed on the mat
    /// and used in the reference overlay.
    ///
    /// This was `Zone.rawValue`, which is a Swift identifier and reads
    /// like one: "runeDeck", "mainDeck", "runeArea". Those are the
    /// engine's names for these regions and they're correct there — but
    /// the person reading them is looking at a physical mat that says
    /// "Rune Deck", "Deck" and "Runes", so the overlay says that.
    /// Kept as an explicit switch rather than a camel-case splitter: it
    /// isn't a formatting problem, `mainDeck` → "Deck" and `runeArea` →
    /// "Runes" are genuinely different words, and a new `Zone` case
    /// should be a compile error here rather than silently rendering as
    /// its identifier.
    private static func displayName(for zone: Zone) -> String {
        switch zone {
        // Both hand cases collapse to "Hand": the raw value already
        // spells out the seat, which would double up with the "(P1)"
        // suffix above ("player1Hand (P1)").
        case .player1Hand, .player2Hand: return "Hand"
        case .base: return "Base"
        case .battlefield: return "Battlefield"
        case .runeArea: return "Runes"
        case .runeDeck: return "Rune Deck"
        case .mainDeck: return "Deck"
        case .trash: return "Trash"
        case .legend: return "Legend"
        case .champion: return "Champion"
        case .unknown: return "Unknown"
        }
    }

    /// Where a zone's label sits: horizontally centred, vertically on the
    /// zone's *bottom* border.
    ///
    /// This used to be the polygon's centroid, which put every label in
    /// the middle of its box — directly over the part of the mat where
    /// cards actually get placed, so the label and the cards it describes
    /// competed for the same pixels. On the bottom border it labels the
    /// zone from its edge and leaves the interior clear, which is what the
    /// reference does.
    ///
    /// `Canvas.draw(_:at:)` anchors at the text's centre by default, so
    /// returning `maxY` straddles the text across the border line rather
    /// than hanging it below.
    private func labelAnchor(of rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.maxY)
    }

    private func boundingRect(of points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }
}
