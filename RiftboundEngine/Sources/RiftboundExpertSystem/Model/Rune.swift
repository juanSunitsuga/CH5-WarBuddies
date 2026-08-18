/// A Rune on the board (rule 153–157), sitting in its controller's Rune
/// Area after being Channeled there from the Rune Deck (606.1).
///
/// This is a `GameObject` but explicitly **not** a Permanent (154.1.a), and
/// the `RuneCard` it came from is a `Card` per rule 052 — same
/// object/card/permanent split CLAUDE.md point 1 insists on for Units.
/// `card` is kept whole rather than reduced to a `CardDefID` because
/// Recycling puts *that card* back on the bottom of the Rune Deck (154.2.b),
/// so the identity has to survive the round trip.
///
/// Why this type exists at all: a Rune's stance is the physical record of
/// payment. Rule 157.2.a is `[T]: Add [1]` — Energy enters the Rune Pool by
/// **Exhausting** a Rune, not by Channeling one. Modeling Channel as "+1
/// Energy" (which this engine previously did) collapses those two distinct
/// physical acts into one and makes the camera's most legible signal — a
/// rune rotated sideways — unrepresentable. It also silently granted a
/// player Energy they hadn't paid for: a rune channeled during the Channel
/// Phase is Ready, and its Energy does not exist until someone turns it.
public struct Rune: GameObject, Sendable, Identifiable, Equatable {
    public var id: ObjectID
    public var owner: PlayerID
    public var controller: PlayerID
    /// The Rune Deck card this was Channeled from — returned to the bottom
    /// of that deck verbatim on Recycle (154.2.b/594.1.b).
    public var card: RuneCard
    /// Rule 606.2: Runes normally enter Ready, but an effect may specify
    /// "Channel 1 rune exhausted."
    public var isExhausted: Bool

    /// Rule 156.2.a.1: the Power this Rune produces when Recycled carries
    /// this Domain (157.2.b.1).
    public var domain: Domain { card.domain }

    public init(
        id: ObjectID = ObjectID(),
        owner: PlayerID,
        controller: PlayerID? = nil,
        card: RuneCard,
        isExhausted: Bool = false
    ) {
        self.id = id
        self.owner = owner
        self.controller = controller ?? owner
        self.card = card
        self.isExhausted = isExhausted
    }
}
