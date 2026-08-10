/// The keyword glossary (rule 716–729). Values with a magnitude (Assault,
/// Shield, Deflect) carry an associated Int; if a printed card omits the
/// number, treat it as 1 per the relevant rule (e.g. 719.1.b.3).
///
/// This is intentionally an exhaustive enum, not a string/dictionary bag —
/// new keywords from future sets should be a compile error until handled,
/// not silently ignored. See CLAUDE.md point 4 for the same rationale
/// applied to effects.
public enum Keyword: Codable, Sendable, Hashable {
    case accelerate                 // 717
    case action                     // 718
    case assault(Int)               // 719
    case deathknell                 // 720 — carries no magnitude; the effect
                                     //       text lives on the card, not here
    case deflect(Int)               // 721
    case ganking                    // 722
    case hidden                     // 723
    case legion                     // 724
    case reaction                   // 725
    case shield(Int)                // 726
    case tank                       // 727
    case temporary                  // 728
    case vision                     // 729

    /// Rule 719.2 / 721.2: when a unit is granted the same keyword from
    /// multiple sources, magnitudes sum. Non-magnitude keywords are
    /// idempotent (multiple instances are redundant — e.g. 717.4, 722.2).
    public static func combine(_ lhs: Keyword, _ rhs: Keyword) -> Keyword? {
        switch (lhs, rhs) {
        case let (.assault(a), .assault(b)): return .assault(a + b)
        case let (.deflect(a), .deflect(b)): return .deflect(a + b)
        case let (.shield(a), .shield(b)): return .shield(a + b)
        default: return nil // caller should treat non-magnitude duplicates as redundant
        }
    }
}
