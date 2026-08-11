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
///   - `singlePlayerZones(owner:)` — a one-player accessory mat with two
///     side-by-side Battlefield slots, a Champion/Legend/Base/Main Deck
///     row, and a Rune Deck/Runes/Trash row (matches the reference mat
///     photo this was transcribed from — an Epic Upgrades-style mat, not
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

        return [
            // Battlefield row — two independent slots, side by side.
            PlaymatZoneTemplate(zone: .battlefield, owner: nil, normalizedPolygon: rect(0.09, 0.10, 0.505, 0.37), battlefieldSlot: 0),
            PlaymatZoneTemplate(zone: .battlefield, owner: nil, normalizedPolygon: rect(0.515, 0.10, 0.94, 0.37), battlefieldSlot: 1),

            // Champion / Legend / Base / Main Deck row.
            PlaymatZoneTemplate(zone: .champion, owner: owner, normalizedPolygon: rect(0.09, 0.40, 0.205, 0.62)),
            PlaymatZoneTemplate(zone: .legend, owner: owner, normalizedPolygon: rect(0.215, 0.40, 0.335, 0.62)),
            PlaymatZoneTemplate(zone: .base, owner: owner, normalizedPolygon: rect(0.345, 0.40, 0.825, 0.62)),
            PlaymatZoneTemplate(zone: .mainDeck, owner: owner, normalizedPolygon: rect(0.835, 0.40, 0.94, 0.62)),

            // Rune Deck / Runes / Trash row.
            PlaymatZoneTemplate(zone: .runeDeck, owner: owner, normalizedPolygon: rect(0.09, 0.635, 0.205, 0.855)),
            PlaymatZoneTemplate(zone: .runeArea, owner: owner, normalizedPolygon: rect(0.215, 0.635, 0.825, 0.855)),
            PlaymatZoneTemplate(zone: .trash, owner: owner, normalizedPolygon: rect(0.835, 0.635, 0.94, 0.855)),

            // Hand — no printed box on the physical mat itself (a hand is
            // normally held, not laid on the table), but this project is
            // playing Open Hand: cards are laid face-up in front of the
            // player instead of held concealed, which is exactly what
            // makes camera-based tracking of hand cards feasible at all.
            // This band sits along the mat's near edge (highest y, closest
            // to the player, matching the row ordering above) so the user
            // can calibrate it to wherever they actually lay their hand.
            PlaymatZoneTemplate(zone: handZone, owner: owner, normalizedPolygon: rect(0.09, 0.865, 0.94, 0.995))
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
