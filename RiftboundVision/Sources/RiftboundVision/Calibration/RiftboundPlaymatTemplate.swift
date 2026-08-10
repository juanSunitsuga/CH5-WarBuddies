import CoreGraphics

/// One zone's shape on the *template* — normalized to a unit square,
/// (0,0) at the top-left corner and (1,1) at the bottom-right, matching
/// the corner order `PlaymatCalibration` uses. Not a measurement of any
/// specific physical mat; `PlaymatCalibration` maps this onto wherever
/// the user aligns it against the camera feed.
public struct PlaymatZoneTemplate: Sendable {
    public let zone: Zone
    /// `nil` for the shared Battlefield band, which isn't owned by either
    /// seat until units are actually placed there.
    public let owner: Player?
    public let normalizedPolygon: [CGPoint]

    public init(zone: Zone, owner: Player?, normalizedPolygon: [CGPoint]) {
        self.zone = zone
        self.owner = owner
        self.normalizedPolygon = normalizedPolygon
    }
}

/// Normalized zone geometry for a standard 2-player Riftbound playmat:
/// each seat gets a Rune Deck / Runes / Trash row on their outer edge and
/// a Champion / Legend / Base / Main Deck row nearer the middle, and both
/// seats share one Battlefield band down the center. Transcribed from the
/// official playmat layout (mirrored top/bottom around the Battlefield).
///
/// This is a *template* — exact proportions are approximate, not
/// pixel-measured from a specific mat. `PlaymatCalibration` (drag-to-align
/// 4 corners against the live camera feed) is what makes it accurate for
/// any specific physical setup; getting the template's proportions
/// perfect isn't the point, since it's never used un-calibrated.
public enum RiftboundPlaymatTemplate {
    public static let zones: [PlaymatZoneTemplate] = farRow + [battlefield] + nearRow

    private static func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    /// Player 2's half — the far side of the mat as the camera sees it
    /// (top of frame), rows nearest the top edge first.
    private static let farRow: [PlaymatZoneTemplate] = [
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
    private static let battlefield = PlaymatZoneTemplate(
        zone: .battlefield,
        owner: nil,
        normalizedPolygon: rect(0.00, 0.32, 1.00, 0.68)
    )

    /// Player 1's half — the near side of the mat (bottom of frame),
    /// mirrored from `farRow`.
    private static let nearRow: [PlaymatZoneTemplate] = [
        PlaymatZoneTemplate(zone: .champion, owner: .player1, normalizedPolygon: rect(0.00, 0.68, 0.12, 0.84)),
        PlaymatZoneTemplate(zone: .legend, owner: .player1, normalizedPolygon: rect(0.12, 0.68, 0.24, 0.84)),
        PlaymatZoneTemplate(zone: .base, owner: .player1, normalizedPolygon: rect(0.24, 0.68, 0.76, 0.84)),
        PlaymatZoneTemplate(zone: .mainDeck, owner: .player1, normalizedPolygon: rect(0.76, 0.68, 1.00, 0.84)),
        PlaymatZoneTemplate(zone: .trash, owner: .player1, normalizedPolygon: rect(0.00, 0.84, 0.18, 1.00)),
        PlaymatZoneTemplate(zone: .runeArea, owner: .player1, normalizedPolygon: rect(0.18, 0.84, 0.82, 1.00)),
        PlaymatZoneTemplate(zone: .runeDeck, owner: .player1, normalizedPolygon: rect(0.82, 0.84, 1.00, 1.00))
    ]
}
