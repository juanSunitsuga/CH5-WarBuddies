/// The result of Stage 2 (Object Tracking): a physical change on the table,
/// already paired with the card identity from Stage 1. This is still *not*
/// a validated `GameAction` — see docs/architecture.md section 1: OCR/
/// tracking is an untrusted proposer. `ObservedTableEvent` is the shape of
/// what got proposed, before the Ingestion layer maps it onto the engine's
/// closed `GameAction` vocabulary (rule 586–607) and before the
/// `LegalityValidator` accepts or rejects it.
///
/// Deliberately a flat, low-level shape (movement + exhaust/ready state
/// change + zone change) rather than pre-guessing intent ("this looks like
/// a Standard Move") — that inference belongs to `ActionTranslating`
/// (Stage 3), which has the context (whose turn, what state) to disambiguate
/// what a raw movement actually means. A card physically moving from Base
/// to a Battlefield could be a Standard Move, or it could be the visible
/// result of a spell that already resolved — the tracker shouldn't guess.
public struct ObservedTableEvent: Sendable {
    public enum Kind: Sendable, Equatable {
        case cardAppeared(region: TableRegion)
        case cardMoved(from: TableRegion, to: TableRegion)
        case cardOrientationChanged(region: TableRegion, nowExhausted: Bool)
        case cardRemoved(region: TableRegion)  // e.g. physically discarded/trashed
    }

    public let kind: Kind
    public let card: CardIdentification?   // nil if the moved/changed object couldn't be re-identified this frame
    public let observedAt: Double          // monotonic timestamp from the tracking layer, for sequencing simultaneous events (rule 503.2.a)

    public init(kind: Kind, card: CardIdentification?, observedAt: Double) {
        self.kind = kind
        self.card = card
        self.observedAt = observedAt
    }
}

/// The contract OCR + Object Tracking must satisfy. Implemented by the
/// vision pipeline; consumed by `GameEngine`. Kept as a protocol so rule
/// logic can be tested against scripted fixture sequences without a camera
/// running (per CLAUDE.md's testing guidance).
public protocol BoardObserving: Sendable {
    /// A stream of observed events as they happen. `AsyncSequence` rather
    /// than a callback so the engine can process events strictly in
    /// arrival order — ordering matters here (rule 503.2.a) in a way it
    /// wouldn't for, say, a UI event handler.
    func events() -> AsyncStream<ObservedTableEvent>
}
