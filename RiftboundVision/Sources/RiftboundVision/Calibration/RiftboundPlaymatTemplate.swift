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

    // MARK: - Single player (active default)

    /// `owner` is whichever seat this specific physical mat belongs to —
    /// defaults to `.player1` since a single camera/mat calibration is
    /// inherently "whoever's mat this is," not necessarily the near seat.
    public static func singlePlayerZones(owner: Player = .player1) -> [PlaymatZoneTemplate] {
        // Which `Zone` case names this owner's Hand — kept consistent with
        // `owner` rather than hardcoded, since this template can be
        // calibrated for either seat's physical mat.
        let handZone: Zone = owner == .player1 ? .player1Hand : .player2Hand

        // Shared column bounds — the printed mat is 3 full-width bands
        // (Battlefield/Base/Runes) on the left with one consistent
        // right-hand accessory column (Legend+Champion, then Main Deck,
        // then Trash, top to bottom); Rune Deck is the one box that
        // breaks the pattern, sitting inline at the *left* of the Runes
        // band instead of in that right column.
        let mainX0: CGFloat = 0.06
        let mainX1: CGFloat = 0.62
        let accessoryX0: CGFloat = 0.66
        let accessoryX1: CGFloat = 0.90

        return [
            // Battlefield band — two independent slots side by side (the
            // print shows one undivided band; the internal split is this
            // app's own bookkeeping for multiple Battlefields in play,
            // rule 111).
            PlaymatZoneTemplate(zone: .battlefield, owner: nil, normalizedPolygon: rect(mainX0, 0.08, 0.335, 0.30), battlefieldSlot: 0),
            PlaymatZoneTemplate(zone: .battlefield, owner: nil, normalizedPolygon: rect(0.345, 0.08, mainX1, 0.30), battlefieldSlot: 1),
            PlaymatZoneTemplate(zone: .legend, owner: owner, normalizedPolygon: rect(accessoryX0, 0.08, 0.775, 0.30)),
            PlaymatZoneTemplate(zone: .champion, owner: owner, normalizedPolygon: rect(0.785, 0.08, accessoryX1, 0.30)),

            // Base band.
            PlaymatZoneTemplate(zone: .base, owner: owner, normalizedPolygon: rect(mainX0, 0.36, mainX1, 0.58)),
            PlaymatZoneTemplate(zone: .mainDeck, owner: owner, normalizedPolygon: rect(accessoryX0, 0.36, accessoryX1, 0.58)),

            // Runes band — Rune Deck inline at the left instead of in the
            // accessory column.
            PlaymatZoneTemplate(zone: .runeDeck, owner: owner, normalizedPolygon: rect(mainX0, 0.64, 0.175, 0.86)),
            PlaymatZoneTemplate(zone: .runeArea, owner: owner, normalizedPolygon: rect(0.185, 0.64, mainX1, 0.86)),
            PlaymatZoneTemplate(zone: .trash, owner: owner, normalizedPolygon: rect(accessoryX0, 0.64, accessoryX1, 0.86)),

            // Hand — no printed box on the physical mat itself (a hand is
            // normally held, not laid on the table), but this project is
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
            PlaymatZoneTemplate(zone: handZone, owner: owner, normalizedPolygon: rect(mainX0, 0.92, accessoryX1, 1.34))
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
