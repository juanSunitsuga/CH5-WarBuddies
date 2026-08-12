import CoreGraphics

/// One zone's shape on the *template* — normalized to a unit square,
/// (0,0) at the top-left corner and (1,1) at the bottom-right, matching
/// the corner order `PlaymatCalibration` uses. Not a measurement of any
/// specific physical mat; `PlaymatCalibration` maps this onto wherever
/// the user aligns it against the camera feed.
public struct PlaymatZoneTemplate: Sendable {
    public let zone: Zone
    /// `nil` for zones not owned by either seat until something is
    /// actually placed there (a Battlefield's Control is tracked at the
    /// `GameState` level, not by this geometry).
    public let owner: Player?
    public let normalizedPolygon: [CGPoint]
    /// Which physical Battlefield this is, for mats with more than one
    /// Battlefield slot (this template's single-player layout has two,
    /// side by side) — carried per-zone rather than applied externally,
    /// since a single mat can have several Battlefield regions that need
    /// telling apart.
    public let battlefieldSlot: Int?

    public init(zone: Zone, owner: Player?, normalizedPolygon: [CGPoint], battlefieldSlot: Int? = nil) {
        self.zone = zone
        self.owner = owner
        self.normalizedPolygon = normalizedPolygon
        self.battlefieldSlot = battlefieldSlot
    }
}

/// Normalized playmat zone geometry. Two layouts are provided:
///
///   - `singlePlayerZones(owner:)` — a one-player accessory mat: three
///     stacked full-width bands (Battlefield, Base, Runes) with a right-
///     hand column of accessory boxes (Legend+Champion beside Battlefield,
///     Main Deck beside Base, Trash beside Runes) and Rune Deck inline at
///     the left of the Runes band — matches the reference mat photo this
///     was transcribed from (a numbered-score-track accessory mat, not
///     the official 2-player Riftbound mat). This is the default/active
///     template — calibrating one player's half at a time, per the
///     current scope.
///   - `twoPlayerZones` — the original official-mat layout (mirrored
///     halves sharing one Battlefield band). Kept for when 2-player
///     calibration is worth adding back; not currently wired into the app.
///
/// Both are *templates* — exact proportions are approximate, not
/// pixel-measured. `PlaymatCalibration` (drag-to-align 4 corners against
/// the live camera feed) is what makes either one accurate for a specific
/// physical setup; the template's proportions don't need to be perfect
/// since it's never used un-calibrated.
public enum RiftboundPlaymatTemplate {
    private static func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    /// The mat's true proportion (646 × 502 — see `singlePlayerZones`'s
    /// derivation), so a calibration quad can be built at the same shape
    /// the border artwork was drawn for. Drawing into a quad of any other
    /// proportion is exactly what stretched the frames before.
    public static let matAspectRatio: CGFloat = 646.0 / 502.0

    // MARK: - Single player (active default)

    /// `owner` is whichever seat this specific physical mat belongs to —
    /// defaults to `.player1` since a single camera/mat calibration is
    /// inherently "whoever's mat this is," not necessarily the near seat.
    public static func singlePlayerZones(owner: Player = .player1) -> [PlaymatZoneTemplate] {
        // Which `Zone` case names this owner's Hand — kept consistent with
        // `owner` rather than hardcoded, since this template can be
        // calibrated for either seat's physical mat.
        let handZone: Zone = owner == .player1 ? .player1Hand : .player2Hand

        // Derived from the border-art assets' REAL pixel dimensions, not
        // from eyeballing the mockup — every zone's aspect ratio here is
        // exactly its artwork's own, so `PlaymatOverlayView` can draw each
        // frame into its zone rect with zero stretching. (Previously these
        // were hand-transcribed approximations, which is why the art
        // smeared.)
        //
        // The four assets all share height 164 and their widths compose
        // into an exact grid once you allow a 5pt gutter:
        //     Rectangle 1: 121 × 164   Legend, Champion, Deck, Rune Deck, Trash
        //     Rectangle 2: 394 × 164   Battlefield, Runes
        //     Rectangle 3: 520 × 164   Base
        //     Rectangle 4: 645 × 164   Hand
        //   row 1  394 + 5 + 121 + 5 + 121 = 646
        //   row 2  520 + 5 + 121           = 646
        //   row 3  121 + 5 + 394 + 5 + 121 = 646
        // That the three rows land on the same 646 total is what fixes the
        // gutter at exactly 5 — it isn't a tuning knob, it's the only
        // value that makes the artwork tile. Keep these numbers in sync
        // with the PNGs; if the art is ever re-exported at a different
        // size, re-derive rather than nudging the normalized values.
        let small: CGFloat = 121, medium: CGFloat = 394, large: CGFloat = 520, hand: CGFloat = 645
        let rowHeight: CGFloat = 164
        let gutter: CGFloat = 5

        // The unit square is the *mat* (rows 1–3). Hand lives below it and
        // is deliberately allowed past y = 1 — see its own comment below.
        let matWidth = medium + gutter + small + gutter + small      // 646
        let matHeight = rowHeight * 3 + gutter * 2                    // 502

        func x(_ pixels: CGFloat) -> CGFloat { pixels / matWidth }
        func y(_ pixels: CGFloat) -> CGFloat { pixels / matHeight }
        /// A zone box placed by its real pixel origin and its artwork's
        /// real pixel size, then normalized — never by a guessed fraction.
        func box(_ px: CGFloat, _ py: CGFloat, _ width: CGFloat, _ height: CGFloat = rowHeight) -> [CGPoint] {
            rect(x(px), y(py), x(px + width), y(py + height))
        }

        let row1Y: CGFloat = 0
        let row2Y = rowHeight + gutter                                // 169
        let row3Y = (rowHeight + gutter) * 2                          // 338

        // Column origins, accumulated left to right per row.
        let row1LegendX = medium + gutter                             // 399
        let row1ChampionX = row1LegendX + small + gutter              // 525
        let row2DeckX = large + gutter                                // 525
        let row3RunesX = small + gutter                               // 126
        let row3TrashX = row3RunesX + medium + gutter                 // 525

        return [
            // Row 1: Battlefield — a single zone (no more internal slot
            // split; this mat only calibrates one physical Battlefield
            // card) + Legend + Champion.
            PlaymatZoneTemplate(zone: .battlefield, owner: nil, normalizedPolygon: box(0, row1Y, medium), battlefieldSlot: 0),
            PlaymatZoneTemplate(zone: .legend, owner: owner, normalizedPolygon: box(row1LegendX, row1Y, small)),
            PlaymatZoneTemplate(zone: .champion, owner: owner, normalizedPolygon: box(row1ChampionX, row1Y, small)),

            // Row 2: Base (the widest band — only one accessory box beside
            // it) + Main Deck.
            PlaymatZoneTemplate(zone: .base, owner: owner, normalizedPolygon: box(0, row2Y, large)),
            PlaymatZoneTemplate(zone: .mainDeck, owner: owner, normalizedPolygon: box(row2DeckX, row2Y, small)),

            // Row 3: Rune Deck (inline at the left, not in the accessory
            // column) + Rune Area (same artwork, so same width, as
            // Battlefield) + Trash.
            PlaymatZoneTemplate(zone: .runeDeck, owner: owner, normalizedPolygon: box(0, row3Y, small)),
            PlaymatZoneTemplate(zone: .runeArea, owner: owner, normalizedPolygon: box(row3RunesX, row3Y, medium)),
            PlaymatZoneTemplate(zone: .trash, owner: owner, normalizedPolygon: box(row3TrashX, row3Y, small)),

            // Hand — spans the same outer left/right bounds as everything
            // else above (`leftMargin`/`accessoryX1`), so it stays aligned
            // to the grid's actual full width regardless of how the zones
            // between those edges are laid out. No printed box on the
            // physical mat itself (a hand is normally held, not laid on
            // the table), but this project is
            // playing Open Hand: cards are laid face-up in front of the
            // player instead of held concealed, which is exactly what
            // makes camera-based tracking of hand cards feasible at all.
            // Deliberately extends past the template's own bottom edge
            // (y > 1) rather than being squeezed into the last sliver of
            // the printed mat — a hand of physical cards needs real room,
            // and `PlaymatCalibration.map`'s bilinear interpolation
            // extrapolates cleanly past y=1. In practice this means
            // dragging the calibration quad's *bottom* corners down past
            // the mat's actual printed edge, out onto the bare table in
            // front of the player, so this zone (and the detector's ROI,
            // which is this same quad's bounding rect) actually covers
            // where the hand is laid out.
            // Hand is 645 wide against the mat's 646, so it sits half a
            // point in from each edge rather than spanning exactly 0...1 —
            // using the artwork's real width instead of rounding it to the
            // full mat width is the whole point of this rewrite.
            PlaymatZoneTemplate(
                zone: handZone,
                owner: owner,
                normalizedPolygon: box((matWidth - hand) / 2, matHeight + gutter, hand)
            )
        ]
    }

    // MARK: - Two player (not currently wired in)

    public static let twoPlayerZones: [PlaymatZoneTemplate] = twoPlayerFarRow + [twoPlayerBattlefield] + twoPlayerNearRow

    /// Player 2's half — the far side of the mat as the camera sees it
    /// (top of frame), rows nearest the top edge first.
    private static let twoPlayerFarRow: [PlaymatZoneTemplate] = [
        PlaymatZoneTemplate(zone: .trash, owner: .player2, normalizedPolygon: rect(0.00, 0.00, 0.18, 0.16)),
        PlaymatZoneTemplate(zone: .runeArea, owner: .player2, normalizedPolygon: rect(0.18, 0.00, 0.82, 0.16)),
        PlaymatZoneTemplate(zone: .runeDeck, owner: .player2, normalizedPolygon: rect(0.82, 0.00, 1.00, 0.16)),
        PlaymatZoneTemplate(zone: .champion, owner: .player2, normalizedPolygon: rect(0.00, 0.16, 0.12, 0.32)),
        PlaymatZoneTemplate(zone: .legend, owner: .player2, normalizedPolygon: rect(0.12, 0.16, 0.24, 0.32)),
        PlaymatZoneTemplate(zone: .base, owner: .player2, normalizedPolygon: rect(0.24, 0.16, 0.76, 0.32)),
        PlaymatZoneTemplate(zone: .mainDeck, owner: .player2, normalizedPolygon: rect(0.76, 0.16, 1.00, 0.32))
    ]

    /// Shared, not owned by either seat until a Unit is actually placed —
    /// Control (181) is tracked per-Battlefield at the `GameState` level,
    /// not by this geometry.
    private static let twoPlayerBattlefield = PlaymatZoneTemplate(
        zone: .battlefield,
        owner: nil,
        normalizedPolygon: rect(0.00, 0.32, 1.00, 0.68),
        battlefieldSlot: 0
    )

    /// Player 1's half — the near side of the mat (bottom of frame),
    /// mirrored from `twoPlayerFarRow`.
    private static let twoPlayerNearRow: [PlaymatZoneTemplate] = [
        PlaymatZoneTemplate(zone: .champion, owner: .player1, normalizedPolygon: rect(0.00, 0.68, 0.12, 0.84)),
        PlaymatZoneTemplate(zone: .legend, owner: .player1, normalizedPolygon: rect(0.12, 0.68, 0.24, 0.84)),
        PlaymatZoneTemplate(zone: .base, owner: .player1, normalizedPolygon: rect(0.24, 0.68, 0.76, 0.84)),
        PlaymatZoneTemplate(zone: .mainDeck, owner: .player1, normalizedPolygon: rect(0.76, 0.68, 1.00, 0.84)),
        PlaymatZoneTemplate(zone: .trash, owner: .player1, normalizedPolygon: rect(0.00, 0.84, 0.18, 1.00)),
        PlaymatZoneTemplate(zone: .runeArea, owner: .player1, normalizedPolygon: rect(0.18, 0.84, 0.82, 1.00)),
        PlaymatZoneTemplate(zone: .runeDeck, owner: .player1, normalizedPolygon: rect(0.82, 0.84, 1.00, 1.00))
    ]
}
