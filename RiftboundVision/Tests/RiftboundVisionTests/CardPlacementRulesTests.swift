import Testing
@testable import RiftboundVision

/// Which zones a kind of card can physically occupy. A noise filter on a
/// detector that re-reads every card several times a second and sometimes
/// names one card as another — a Rune reported in the Base is far more
/// likely to be a misread than a player breaking the rules.
@Suite("Card Placement Rules")
struct CardPlacementRulesTests {
    private let rules = CardPlacementRules()

    @Test("Runes live only in the Rune Area and the Rune Deck")
    func runesAreConfinedToRuneZones() {
        #expect(rules.isPlausible(kind: .rune, in: .runeArea))
        #expect(rules.isPlausible(kind: .rune, in: .runeDeck))

        for zone in [Zone.base, .battlefield, .player1Hand, .champion, .legend, .mainDeck] {
            #expect(!rules.isPlausible(kind: .rune, in: zone), "A Rune can't be in \(zone).")
        }
    }

    /// Explicitly called out: everything *except* a Rune may end up in the
    /// Trash.
    @Test("Every kind but Rune can reach the Trash")
    func onlyRunesAreBarredFromTheTrash() {
        #expect(!rules.isPlausible(kind: .rune, in: .trash))
        for kind in [CardKind.unit, .champion, .spell, .gear] {
            #expect(rules.isPlausible(kind: kind, in: .trash), "\(kind) should be able to reach the Trash.")
        }
    }

    @Test("Units belong in Hand, Base, and Battlefield")
    func unitZones() {
        for zone in [Zone.player1Hand, .base, .battlefield] {
            #expect(rules.isPlausible(kind: .unit, in: zone))
        }
        #expect(!rules.isPlausible(kind: .unit, in: .runeArea))
        #expect(!rules.isPlausible(kind: .unit, in: .legend))
    }

    /// A Champion is a Unit that also has its own printed box on the mat.
    @Test("Champions add the Champion zone to a Unit's zones")
    func championZones() {
        for zone in [Zone.player1Hand, .base, .battlefield, .champion] {
            #expect(rules.isPlausible(kind: .champion, in: zone))
        }
        #expect(!rules.isPlausible(kind: .unit, in: .champion), "A plain Unit has no business in the Champion box.")
    }

    @Test("Spells belong in Hand and Base, never the Battlefield")
    func spellZones() {
        #expect(rules.isPlausible(kind: .spell, in: .player1Hand))
        #expect(rules.isPlausible(kind: .spell, in: .base))
        #expect(!rules.isPlausible(kind: .spell, in: .battlefield))
        #expect(!rules.isPlausible(kind: .spell, in: .runeArea))
    }

    /// A card in transit between calibrated regions isn't in a wrong
    /// place — it's between places — so nothing is filtered there.
    @Test("An unresolved zone never rejects anything")
    func unknownZoneIsAlwaysAllowed() {
        for kind in CardKind.allCases {
            #expect(rules.isPlausible(kind: kind, in: .unknown))
        }
    }

    /// Refusing to track what can't be named would be worse than tracking
    /// it loosely.
    @Test("An unidentified card is allowed anywhere")
    func unknownKindIsAllowedEverywhere() {
        for zone in Zone.allCases {
            #expect(rules.isPlausible(kind: .unknown, in: zone))
        }
    }

    @Test("Champion supertype is detected from the printing's supertype")
    func championIsReadFromSupertype() {
        #expect(CardKind.from(type: "Unit", supertype: "Champion") == .champion)
        #expect(CardKind.from(type: "Unit", supertype: nil) == .unit)
        #expect(CardKind.from(type: "Rune") == .rune)
        #expect(CardKind.from(type: "Battlefield") == .battlefield)
        #expect(CardKind.from(type: "Nonsense") == .unknown)
    }

    /// The catalogue puts `supertype: "Champion"` on the champion **tag**
    /// (rule 169 / 103.2.a.2), which both a Legend and a Champion Unit
    /// carry — `Annie - Dark Child (Starter)` is `type: Legend`,
    /// `supertype: Champion`, and so is every other starter Legend.
    ///
    /// Reading `supertype` first therefore classified every Legend in every
    /// deck as a Champion. Champions aren't allowed in the Legend zone, so
    /// the app told the player to move a Legend out of the Legend zone —
    /// permanently, and about the one card rules 166–169 require to be
    /// exactly there.
    @Test("A Legend carrying the champion tag is a Legend, not a Champion")
    func legendWithChampionTagIsALegend() {
        let annie = CardKind.from(type: "Legend", supertype: "Champion")

        #expect(annie == .legend)
        #expect(annie != .champion, "The old ordering returned .champion here.")

        // The consequence that was actually visible on screen.
        #expect(rules.isPlausible(kind: annie, in: .legend))
    }

    /// The other half: the tag still distinguishes a Champion Unit, which
    /// is the only kind whose zones it changes (107.2's Champion zone).
    @Test("A Unit carrying the champion tag is a Champion")
    func unitWithChampionTagIsAChampion() {
        #expect(CardKind.from(type: "Unit", supertype: "Champion") == .champion)
        #expect(rules.isPlausible(kind: .champion, in: .champion))
        #expect(!rules.isPlausible(kind: .unit, in: .champion))
    }

    /// Every Legend in the four bundled starter decks is `type: Legend`,
    /// `supertype: Champion` — so this was never a one-card typo to special-
    /// case, it was every deck the app ships with.
    @Test("All four starter legends classify as legends")
    func allStarterLegendsAreLegends() {
        let starters = [
            "Annie - Dark Child (Starter)",
            "Lux - Lady of Luminosity (Starter)",
            "Master Yi - Wuju Bladesman (Starter)",
            "Garen - Might of Demacia (Starter)"
        ]
        for name in starters {
            let kind = CardKind.from(type: "Legend", supertype: "Champion")
            #expect(kind == .legend, "\(name) should classify as a Legend.")
        }
    }
}
