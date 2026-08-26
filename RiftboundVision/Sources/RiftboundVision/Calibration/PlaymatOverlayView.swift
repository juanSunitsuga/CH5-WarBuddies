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
    /// #000000 — pure black. Only the zone-label stroke uses it: text drawn
    /// directly over an arbitrary camera photograph needs a stroke that
    /// reads against any background, which is exactly the exception
    /// `RiftboundTheme.swift` carves out for `Color.black` (never for a
    /// fill or background — those read as a hole in the palette).
    static let pureBlack = Color("PureBlack", bundle: .module)
    /// #000000 at 20% — the board's one darkening value.
    static let scrim = Color("Scrim", bundle: .module)
}

public struct PlaymatOverlayView: View {
    @Binding private var calibration: PlaymatCalibration
    /// The mat's rect when a move-drag began, held for the length of that
    /// drag. `DragGesture.translation` is measured from the drag's start,
    /// so it can only be applied to the rect the drag started from.
    @State private var dragStartRect: CGRect?
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

    /// The hand-drawn border frames, one asset per zone shape.
    ///
    /// The asset names are the designer's own (`Rectangle 1`…`7`), so
    /// which is which is not guessable from the name — that's what this
    /// table is for, and it's the only place the mapping is written down.
    /// It was decoded from a labelled reference export of the same
    /// artwork, matching each frame by its pixel size and stroke colour:
    ///
    ///   | asset       | size    | stroke  | zones                 |
    ///   |-------------|---------|---------|-----------------------|
    ///   | Rectangle 1 | 265×110 | #D5A250 | Battlefield, Base     |
    ///   | Rectangle 2 | 349×110 | #D5A250 | Hand                  |
    ///   | Rectangle 3 | 434×111 | #D5A250 | Rune Area             |
    ///   | Rectangle 4 |  81×110 | #CEA73F | Main Deck             |
    ///   | Rectangle 5 |  81×110 | #CEA73F | Rune Deck             |
    ///   | Rectangle 6 |  81×110 | black   | Trash                 |
    ///   | Rectangle 7 |  81×110 | #9C650B | Legend, Champion      |
    ///
    /// Where two zones share a frame they are the same size *and* the
    /// same colour in the reference — not an approximation. Stretching a
    /// frame past its own aspect visibly smears its corner accents, which
    /// is why the shapes are matched rather than one default reused:
    /// `RiftboundPlaymatTemplate` lays the grid out from these very
    /// numbers so each frame draws at exactly its native proportions.
    private static let mediumFrame = loadFrame("Rectangle 1")   // 265 × 110
    private static let largeFrame = loadFrame("Rectangle 2")    // 349 × 110
    private static let wideFrame = loadFrame("Rectangle 3")     // 434 × 111
    private static let deckFrame = loadFrame("Rectangle 4")     //  81 × 110
    private static let runeDeckFrame = loadFrame("Rectangle 5") //  81 × 110
    private static let trashFrame = loadFrame("Rectangle 6")    //  81 × 110
    private static let legendFrame = loadFrame("Rectangle 7")   //  81 × 110
    /// The corner grab handle. A drawn asset rather than a `Circle()`, so
    /// the one control the player physically drags is drawn by the same
    /// hand as everything it's aligning.
    static let handleImage = loadFrame("Ellipse")

    /// Drawn much larger than the asset's own 23pt. It's a drag target on
    /// a live camera picture, scaled down with everything else by the
    /// stage's aspect-fit factor before it reaches the screen — so its
    /// export size is no guide at all to how big it ends up.
    private static let handleDiameter: CGFloat = 34

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
        // SVG, not PNG: `NSImage` reads SVG directly on macOS, and the
        // frames are line art that gets scaled to whatever the calibrated
        // quad turns out to be — a raster would soften at any size but
        // its own.
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
              let nsImage = NSImage(contentsOf: url) else {
            // Shouldn't happen — these are bundled resources, not
            // user-supplied data — but a missing/renamed asset shouldn't
            // crash the calibration overlay; fall back to a visible
            // placeholder instead.
            return Image(systemName: "questionmark.square.dashed")
        }
        return Image(nsImage: nsImage)
    }

    /// One frame per zone, matched to that zone's own artwork.
    ///
    /// Exhaustive on purpose — no `default:`. Every zone this template
    /// can produce has a frame drawn at its exact proportions, and a new
    /// one should fail the build until someone says which art it wears
    /// rather than silently inheriting a texture drawn for a different
    /// shape. (The zones not in this template — the ones only a
    /// two-player mat has — still need an answer, and take the frame of
    /// whichever single-player zone is their size.)
    private func frame(for zone: Zone) -> Image {
        switch zone {
        case .battlefield, .base: return Self.mediumFrame
        case .player1Hand, .player2Hand: return Self.largeFrame
        case .runeArea: return Self.wideFrame
        case .mainDeck: return Self.deckFrame
        case .runeDeck: return Self.runeDeckFrame
        case .trash: return Self.trashFrame
        case .legend, .champion: return Self.legendFrame
        // Never reaches here: `.unknown` is what the zone mapper returns
        // for a detection that landed outside every calibrated region,
        // and no template ever emits it as a region to draw. Answered
        // explicitly rather than swept up by a `default:` so a genuinely
        // new zone still has to be given art.
        case .unknown: return Self.mediumFrame
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
                        // Black halo (offsets) under a cream centre, so the
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
                        let text = Text(label(for: zoneTemplate)).font(.custom("Sora-Bold", size: Self.labelFontSize))
                        for offset in [CGPoint(x: -1.5, y: -1.5), CGPoint(x: 1.5, y: -1.5), CGPoint(x: -1.5, y: 1.5), CGPoint(x: 1.5, y: 1.5)] {
                            context.draw(
                                text.foregroundStyle(PlaymatPalette.pureBlack),
                                at: CGPoint(x: anchorPoint.x + offset.x, y: anchorPoint.y + offset.y)
                            )
                        }
                        context.draw(text.foregroundStyle(PlaymatPalette.regularText), at: anchorPoint)
                    }
                }

                // Intentionally remove the bright yellow outer boundary
                // stroke used for debugging; the reference overlay is
                // visually quieter.
            }
            .allowsHitTesting(false)

            if isEditable {
                // Order matters: the drag surface covers the whole mat,
                // so the handles have to be layered *after* it to win the
                // hit test where they overlap at the corners.
                matDragSurface
                handle(.topLeft)
                handle(.topRight)
                handle(.bottomRight)
                handle(.bottomLeft)
            }
        }
    }

    /// Which corner a handle drives. Dragging one resizes the rectangle
    /// with the *opposite* corner pinned, so the mat only ever gets wider
    /// or taller — it can never be sheared into a parallelogram.
    ///
    /// All four are built. The reference only draws the top-left one, and
    /// matching that was tried — but a single grip means the *opposite*
    /// corner is always the pinned one, so growing the mat downward or to
    /// the right meant dragging the top-left away and then dragging the
    /// whole mat back. Four grips is one more thing on screen and a lot
    /// less work at the table.
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
        // The drawn `Ellipse` asset, not a `Circle()` built here. Same
        // reason the zone borders are art: the handle sits *on* the mat
        // it resizes, and a crisp system circle among hand-drawn frames
        // reads as UI chrome that landed on the picture by accident.
        return Self.handleImage
            .resizable()
            .frame(width: Self.handleDiameter, height: Self.handleDiameter)
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    resize(corner: corner, to: value.location)
                }
            )
    }

    /// Drags the whole mat without changing its size.
    ///
    /// An invisible surface over the mat rather than the move puck that
    /// used to sit in the middle of it. Moving is the *body* and resizing
    /// is the *corner* — which is how every window on the platform
    /// already behaves, so it needs no affordance of its own to be
    /// discoverable, and it keeps the visible controls down to the four
    /// grips that actually need to be aimed at.
    private var matDragSurface: some View {
        let rect = currentRect
        return Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Anchored to where the drag *started*, not to the
                        // live rect. Offsetting the current rect by each
                        // update's translation would re-apply the whole
                        // accumulated distance every frame and send the
                        // mat flying off the screen.
                        let start = dragStartRect ?? rect
                        if dragStartRect == nil { dragStartRect = rect }
                        apply(start.offsetBy(dx: value.translation.width, dy: value.translation.height))
                    }
                    .onEnded { _ in dragStartRect = nil }
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

    /// The label's point size — in the *camera frame's* pixel space, not
    /// the design system's 15pt, since this is scaled by `ContentView`'s
    /// aspect-fit factor afterward and has no fixed relationship to
    /// on-screen points. Named so `labelAnchor` can size its clearance off
    /// the same number the text is actually drawn at.
    private static let labelFontSize: CGFloat = 24

    /// Where a zone's label sits: horizontally centred, sitting just above
    /// the zone's *bottom* border.
    ///
    /// This used to be the polygon's centroid, which put every label in
    /// the middle of its box — directly over the part of the mat where
    /// cards actually get placed, so the label and the cards it describes
    /// competed for the same pixels. On the bottom border it labels the
    /// zone from its edge and leaves the interior clear, which is what the
    /// reference does.
    ///
    /// `Canvas.draw(_:at:)` anchors at the text's centre by default, so
    /// `maxY` on its own straddled the text across the border line — half
    /// the glyph hanging down into the zone below rather than sitting on
    /// top of the border like the reference. Lifting the anchor by roughly
    /// half the label's own line height clears the border entirely instead
    /// of centring on it.
    private func labelAnchor(of rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.maxY - Self.labelFontSize * 0.65)
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
