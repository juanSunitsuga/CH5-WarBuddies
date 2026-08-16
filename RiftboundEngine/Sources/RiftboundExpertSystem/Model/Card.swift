/// Anything with a printed front face. NOT the same set as `GameObject` —
/// see `GameObject.swift` for the split, and rule 052 for why it matters.
public protocol Card: Sendable {
    var definitionID: CardDefID { get }
    var owner: PlayerID { get }
}

/// Rule 130: Cost as printed in the upper-left corner.
public struct Cost: Codable, Sendable, Equatable {
    /// Energy cost — numeral, paid by exhausting Runes (130.2).
    public var energy: Int
    /// Power cost — total number of Power symbols required (130.3), paid
    /// by recycling this many Runes.
    public var powerCost: Int
    /// Which Domain(s) a recycled Rune may come from to pay `powerCost`.
    /// Any combination of Runes drawn from this list, summing to
    /// `powerCost`, is legal — this is NOT one entry per required symbol.
    /// Confirmed against the source data: multi-domain cards (e.g. Tibbers:
    /// power 2, domains [Fury, Chaos]; Decisive Strike: power 1, domains
    /// [Body, Order]) don't map domain-list length to symbol count 1:1, so
    /// a positional reading would be a guess, not a fact read off the card.
    public var eligibleDomains: [Domain]

    public init(energy: Int = 0, powerCost: Int = 0, eligibleDomains: [Domain] = []) {
        self.energy = energy
        self.powerCost = powerCost
        self.eligibleDomains = eligibleDomains
    }
}

/// Rule 132.4: card type for Main Deck cards. "Card" in rules text (052)
/// means specifically a Main Deck card unless stated otherwise.
public enum MainDeckCardType: Codable, Sendable, Equatable {
    case unit(isChampion: Bool)   // 137–141; champions are units (138 header note)
    case gear                     // 142–145
    case spell                    // 146–152
}

/// A card that lives in a player's Main Deck / Hand / Trash / Banishment,
/// i.e. everything counted toward the "Card" definition in rule 052.
public struct MainDeckCard: Card, Codable, Sendable, Identifiable {
    public var id: ObjectID
    public var definitionID: CardDefID
    public var owner: PlayerID
    public var name: String                 // rule 131
    public var type: MainDeckCardType
    public var tags: [String]                // rule 139.1 — champion/region/faction/species tags
    public var domains: [Domain]             // rule 133 — may be empty (domainless)
    public var cost: Cost
    public var might: Int?                   // 139.2 — nil for Gear/Spell (144.3 notes Gear has no Might)
    public var keywords: [Keyword]           // printed keywords only; granted ones live on the board instance

    public init(
        id: ObjectID = ObjectID(),
        definitionID: CardDefID,
        owner: PlayerID,
        name: String,
        type: MainDeckCardType,
        tags: [String] = [],
        domains: [Domain] = [],
        cost: Cost = Cost(),
        might: Int? = nil,
        keywords: [Keyword] = []
    ) {
        self.id = id
        self.definitionID = definitionID
        self.owner = owner
        self.name = name
        self.type = type
        self.tags = tags
        self.domains = domains
        self.cost = cost
        self.might = might
        self.keywords = keywords
    }
}

/// Rune Deck card (rule 153–157). Not a Main Deck card, not a Permanent
/// (154.1.a), but still a "card" per rule 052.
public struct RuneCard: Card, Codable, Sendable, Identifiable, Equatable {
    public var id: ObjectID
    public var definitionID: CardDefID
    public var owner: PlayerID
    public var domain: Domain

    public init(id: ObjectID = ObjectID(), definitionID: CardDefID, owner: PlayerID, domain: Domain) {
        self.id = id
        self.definitionID = definitionID
        self.owner = owner
        self.domain = domain
    }
}

/// Rule 166–169. Not a Main Deck card, not a "card" per rule 052's shorthand
/// — card *effects* that say "card" do not include Legends.
public struct ChampionLegend: Codable, Sendable, Identifiable {
    public var id: ObjectID
    public var definitionID: CardDefID
    public var owner: PlayerID
    public var name: String
    public var domains: [Domain]              // 169 — determines Domain Identity
    public var championTag: String            // e.g. "Jinx" — matches Chosen Champion (103.2.a.2)
    public var isExhausted: Bool = false

    public init(
        id: ObjectID = ObjectID(),
        definitionID: CardDefID,
        owner: PlayerID,
        name: String,
        domains: [Domain],
        championTag: String
    ) {
        self.id = id
        self.definitionID = definitionID
        self.owner = owner
        self.name = name
        self.domains = domains
        self.championTag = championTag
    }
}

/// Rule 162–165. Not a Main Deck card, not a "card" per rule 052.
public struct Battlefield: Codable, Sendable, Identifiable {
    public var id: BattlefieldID
    public var definitionID: CardDefID
    public var owner: PlayerID
    public var name: String
    public var domains: [Domain]

    public init(
        id: BattlefieldID = BattlefieldID(),
        definitionID: CardDefID,
        owner: PlayerID,
        name: String,
        domains: [Domain] = []
    ) {
        self.id = id
        self.definitionID = definitionID
        self.owner = owner
        self.name = name
        self.domains = domains
    }
}
