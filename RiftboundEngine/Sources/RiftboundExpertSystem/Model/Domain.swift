/// The six Domains (rule 133). Most cards belong to one or more.
public enum Domain: String, Codable, Sendable, CaseIterable {
    case fury   // red, rule 133.2.a
    case calm   // green, rule 133.2.b
    case mind   // blue, rule 133.2.c
    case body   // orange, rule 133.2.d
    case chaos  // purple, rule 133.2.e
    case order  // yellow, rule 133.2.f
}

/// Power produced by Runes has a Domain, OR is Universal and can pay for
/// any Domain's Power cost (rule 156.2.b).
public enum PowerType: Codable, Sendable, Equatable {
    case domain(Domain)
    case universal
}
