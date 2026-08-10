/// Rule 156–161: the conceptual pool of unspent Energy/Power available to
/// pay costs. Empties at the end of each player's Draw Phase AND at the end
/// of each player's turn (rule 160, 517.2.c) — the state machine must clear
/// this at both points, not just once.
public struct RunePool: Codable, Sendable, Equatable {
    public var energy: Int = 0
    public var power: [PowerType] = []

    public init(energy: Int = 0, power: [PowerType] = []) {
        self.energy = energy
        self.power = power
    }

    public static let empty = RunePool()
}

/// Rule 106–107: all the Non-Board (and quasi-board) Zones belonging to a
/// single player. Main Deck and Rune Deck are ordered (secret information,
/// 107.3.c/107.4.c); Trash and Banishment are unordered (public, 107.1.e/
/// 107.5.e) but modeled as arrays for simplicity — order has no gameplay
/// meaning there and should never be relied upon.
public struct PlayerZones: Sendable {
    public var hand: [MainDeckCard] = []
    public var mainDeck: [MainDeckCard] = []       // ordered; top = index 0 by convention
    public var runeDeck: [RuneCard] = []            // ordered; top = index 0 by convention
    public var trash: [any Card] = []                // rule 107.1.e: unordered
    public var banishment: [any Card] = []           // rule 107.5.e: unordered
    public var legend: ChampionLegend
    /// nil once the Chosen Champion has been played to the board (107.2.b:
    /// it cannot return to this zone by normal means).
    public var championZoneCard: MainDeckCard?
    public var runePool: RunePool = .empty

    public init(
        hand: [MainDeckCard] = [],
        mainDeck: [MainDeckCard] = [],
        runeDeck: [RuneCard] = [],
        trash: [any Card] = [],
        banishment: [any Card] = [],
        legend: ChampionLegend,
        championZoneCard: MainDeckCard? = nil,
        runePool: RunePool = .empty
    ) {
        self.hand = hand
        self.mainDeck = mainDeck
        self.runeDeck = runeDeck
        self.trash = trash
        self.banishment = banishment
        self.legend = legend
        self.championZoneCard = championZoneCard
        self.runePool = runePool
    }
}
