/// A Unit on the board (rule 137–141). This is the *board instance*, distinct
/// from the `MainDeckCard` that defines its printed stats — `cardDefinitionID`
/// links back to the definition (and to whatever the NLP layer parsed for
/// its ability text).
public struct Unit: GameObject, Codable, Sendable, Identifiable {
    public var id: ObjectID
    public var owner: PlayerID
    public var controller: PlayerID          // rule 179–183: control ≠ ownership
    public var cardDefinitionID: CardDefID
    public var name: String
    public var isChampion: Bool
    public var baseMight: Int                // printed Might; current Might is computed via Layers (637.1.a.1)
    public var location: Location
    public var isExhausted: Bool             // units enter exhausted (139.4), unless Accelerate (717)
    public var damage: Int                   // rule 139.3 — cleared at turn end and combat end (139.3.b)
    public var hasBuff: Bool                 // rule 701–705 — max one buff at a time
    public var printedKeywords: [Keyword]
    public var grantedKeywords: [Keyword]    // temporary, from other effects; cleared at Expiration Step (109, 517.2)
    public var combatRole: CombatRole?       // set during Showdown (625.1.a-b), cleared at Cleanup (521)

    public init(
        id: ObjectID = ObjectID(),
        owner: PlayerID,
        controller: PlayerID? = nil,
        cardDefinitionID: CardDefID,
        name: String,
        isChampion: Bool,
        baseMight: Int,
        location: Location,
        isExhausted: Bool = true,
        damage: Int = 0,
        hasBuff: Bool = false,
        printedKeywords: [Keyword] = [],
        grantedKeywords: [Keyword] = [],
        combatRole: CombatRole? = nil
    ) {
        self.id = id
        self.owner = owner
        self.controller = controller ?? owner
        self.cardDefinitionID = cardDefinitionID
        self.name = name
        self.isChampion = isChampion
        self.baseMight = baseMight
        self.location = location
        self.isExhausted = isExhausted
        self.damage = damage
        self.hasBuff = hasBuff
        self.printedKeywords = printedKeywords
        self.grantedKeywords = grantedKeywords
        self.combatRole = combatRole
    }

    /// Rule 139.2.b: Might is never treated as negative.
    /// NOTE: this does not yet apply Layer-based modifications (buffs,
    /// Assault/Shield while attacking/defending, granted +Might effects).
    /// That belongs in a `MightCalculator` that walks the Layers system
    /// (rules 634–639) once it exists — this is a placeholder for the
    /// printed/base value only.
    public var printedMightClamped: Int { max(baseMight, 0) }
}

/// Rule 625.1.b: Attacker/Defender designation, tracked only during Combat.
public enum CombatRole: Codable, Sendable, Equatable {
    case attacker
    case defender
}

/// Gear on the board (rule 142–145). Always at a Base (144.2); if ever
/// found at a Battlefield it must be Recalled during the next Cleanup
/// (144.3, 619) — the state machine is responsible for enforcing that,
/// not this struct.
public struct Gear: GameObject, Codable, Sendable, Identifiable {
    public var id: ObjectID
    public var owner: PlayerID
    public var controller: PlayerID
    public var cardDefinitionID: CardDefID
    public var name: String
    public var isExhausted: Bool             // Gear enters ready (144.1), unlike Units
    public var printedKeywords: [Keyword]
    public var grantedKeywords: [Keyword]

    public init(
        id: ObjectID = ObjectID(),
        owner: PlayerID,
        controller: PlayerID? = nil,
        cardDefinitionID: CardDefID,
        name: String,
        isExhausted: Bool = false,
        printedKeywords: [Keyword] = [],
        grantedKeywords: [Keyword] = []
    ) {
        self.id = id
        self.owner = owner
        self.controller = controller ?? owner
        self.cardDefinitionID = cardDefinitionID
        self.name = name
        self.isExhausted = isExhausted
        self.printedKeywords = printedKeywords
        self.grantedKeywords = grantedKeywords
    }
}
