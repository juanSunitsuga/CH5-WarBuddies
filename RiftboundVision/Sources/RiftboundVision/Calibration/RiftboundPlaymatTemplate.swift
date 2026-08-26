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
///   - `singlePlayerZones(owner:)` — a one-player accessory mat, in four
///     rows:
///       1. Battlefield, then Legend and Champion
///       2. Rune Deck, Base, Main Deck
///       3. Rune Area, alone and full width
///       4. Hand, then Trash
///     This is the default/active template — calibrating one player's
///     half at a time, per the current scope.
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

    /// The mat's true proportion (433 × 450 — see `singlePlayerZones`'s
    /// derivation), so a calibration quad can be built at the same shape
    /// the border artwork was drawn for. Drawing into a quad of any other
    /// proportion is exactly what stretched the frames before.
    public static let matAspectRatio: CGFloat = 433.0 / 450.0

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
        // The row assets share height 110 (Runes' is 111) and their
        // widths compose into an exact grid once you allow a 3pt gutter:
        //     small  =  81 × 110   Legend, Champion, Deck, Rune Deck, Trash
        //     medium = 265 × 110   Battlefield, Base
        //     large  = 349 × 110   Hand
        //     wide   = 434 × 111   Runes
        //   row 1  265 + 3 +  81 + 3 +  81 = 433
        //   row 2   81 + 3 + 265 + 3 +  81 = 433
        //   row 3                      434 = 433 (+1, see below)
        //   row 4  349 + 3 +  81           = 433
        // That rows 1, 2 and 4 land on the same 433 total is what fixes
        // the gutter at exactly 3 — it isn't a tuning knob, it's the only
        // value that makes the artwork tile. Keep these numbers in sync
        // with the SVGs; if the art is ever re-exported at a different
        // size, re-derive rather than nudging the normalized values.
        //
        // See `PlaymatOverlayView`'s frame table for which named asset
        // each of these widths is.
        //
        // **Runes gets the widest frame and a row to itself**, which is
        // the point of this layout: a rune area only as wide as the
        // Battlefield forced players to stack runes deep enough that the
        // detector stopped telling them apart. Detection accuracy here is
        // a function of how much table the zone gives you, so the fix is
        // geometric, not a threshold to tune.
        let small: CGFloat = 81, medium: CGFloat = 265, large: CGFloat = 349, wide: CGFloat = 434
        let rowHeight: CGFloat = 110
        // Runes' art is a point taller than the other rows. Carried as
        // its own number rather than rounded to `rowHeight`, for the same
        // reason its width isn't rounded to the mat's: the zone box is
        // the artwork's real size or the frame stretches in it.
        let runesHeight: CGFloat = 111
        let gutter: CGFloat = 3

        let matWidth = medium + gutter + small + gutter + small      // 433
        let matHeight = rowHeight * 3 + runesHeight + gutter * 3      // 450

        func x(_ pixels: CGFloat) -> CGFloat { pixels / matWidth }
        func y(_ pixels: CGFloat) -> CGFloat { pixels / matHeight }
        /// A zone box placed by its real pixel origin and its artwork's
        /// real pixel size, then normalized — never by a guessed fraction.
        func box(_ px: CGFloat, _ py: CGFloat, _ width: CGFloat, _ height: CGFloat = rowHeight) -> [CGPoint] {
            rect(x(px), y(py), x(px + width), y(py + height))
        }

        let row1Y: CGFloat = 0
        let row2Y = rowHeight + gutter                                // 113
        let row3Y = (rowHeight + gutter) * 2                          // 226
        let row4Y = row3Y + runesHeight + gutter                      // 340

        // Column origins, accumulated left to right per row.
        let row1LegendX = medium + gutter                             // 268
        let row1ChampionX = row1LegendX + small + gutter              // 352
        let row2BaseX = small + gutter                                //  84
        let row2DeckX = row2BaseX + medium + gutter                   // 352
        let row4TrashX = large + gutter                               // 352

        return [
            // Row 1: Battlefield + the two character slots.
            PlaymatZoneTemplate(zone: .battlefield, owner: nil, normalizedPolygon: box(0, row1Y, medium), battlefieldSlot: 0),
            PlaymatZoneTemplate(zone: .legend, owner: owner, normalizedPolygon: box(row1LegendX, row1Y, small)),
            PlaymatZoneTemplate(zone: .champion, owner: owner, normalizedPolygon: box(row1ChampionX, row1Y, small)),

            // Row 2: Base, with a deck box either side of it.
            PlaymatZoneTemplate(zone: .runeDeck, owner: owner, normalizedPolygon: box(0, row2Y, small)),
            PlaymatZoneTemplate(zone: .base, owner: owner, normalizedPolygon: box(row2BaseX, row2Y, medium)),
            PlaymatZoneTemplate(zone: .mainDeck, owner: owner, normalizedPolygon: box(row2DeckX, row2Y, small)),

            // Row 3: Runes, alone and full width. 434 against the mat's
            // 433, so it overhangs half a point at each edge rather than
            // being rounded to fit — using the artwork's real width is
            // what keeps the frame from stretching.
            PlaymatZoneTemplate(
                zone: .runeArea,
                owner: owner,
                normalizedPolygon: box((matWidth - wide) / 2, row3Y, wide, runesHeight)
            ),

            // Row 4: Hand + Trash.
            //
            // Hand is inside the mat now, where it used to hang below the
            // template's bottom edge (y > 1) on the reasoning that a hand
            // of physical cards needs room on the bare table. This layout
            // gives it a real printed row, so the calibration quad covers
            // it like every other zone — no extrapolation, and the
            // detector's ROI (that quad's bounding rect) contains it by
            // construction rather than by the user remembering to drag
            // the bottom corners out past the mat.
            PlaymatZoneTemplate(zone: handZone, owner: owner, normalizedPolygon: box(0, row4Y, large)),
            PlaymatZoneTemplate(zone: .trash, owner: owner, normalizedPolygon: box(row4TrashX, row4Y, small))
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
