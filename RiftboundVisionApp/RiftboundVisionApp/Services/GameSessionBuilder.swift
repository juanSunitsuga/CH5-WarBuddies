import Foundation
import RiftboundVision
import RiftboundExpertSystem

/// Builds the real `RiftboundExpertSystem.GameState` the live `GameEngine`
/// runs against, out of the bundled `CardDatabase`.
///
/// This is the "real game setup" step architecture.md lists as blocker (b):
/// the Expert System can't validate a Play unless the card is already in
/// the player's Hand zone in `GameState`, and nothing in this app knows a
/// real decklist. Since this is playing Open Hand (cards laid face-up), the
/// pragmatic stand-in is to seed the Hand with *every* card in the bundled
/// decks — the camera can then "play" any of them and the engine will
/// resolve it. That's deliberately permissive, not a real deck: it means
/// the engine never rejects a Play for "that card isn't in your hand" when
/// the real reason is that this app has no deck-selection UI yet.
///
/// `CardDefID`s here are `CardPrinting.riftboundID`, matching what
/// `ExpertSystemAdapter`'s injected label resolver produces — the two must
/// agree or nothing the camera sees will resolve against this state.
enum GameSessionBuilder {

    struct Session {
        let store: GameStateStore
        let localPlayerID: PlayerID
        let battlefieldSlotIDs: [Int: BattlefieldID]
    }

    static func makeSession(
        database: CardDatabase,
        localPlayerID: PlayerID,
        battlefieldSlotIDs: [Int: BattlefieldID]
    ) -> Session {
        let printings = database.allPrintings

        // Rule 052/121: a Legend is a Game Object but not a Main Deck card,
        // and `PlayerZones` requires one — fall back to a placeholder if
        // the bundled data has no Legend, rather than failing to start.
        let legendPrinting = printings.first { $0.classification.type.lowercased() == "legend" }
        let legend = ChampionLegend(
            definitionID: CardDefID(rawValue: legendPrinting?.riftboundID ?? "legend-placeholder"),
            owner: localPlayerID,
            name: legendPrinting?.name ?? "Unknown Legend",
            domains: [],
            championTag: legendPrinting?.name ?? "Unknown"
        )

        let hand = printings.compactMap { printing -> MainDeckCard? in
            guard let type = mainDeckCardType(for: printing) else { return nil }
            return MainDeckCard(
                definitionID: CardDefID(rawValue: printing.riftboundID),
                owner: localPlayerID,
                name: printing.name,
                type: type,
                cost: Cost(
                    energy: printing.attributes.energy ?? 0,
                    powerCost: printing.attributes.power ?? 0,
                    eligibleDomains: printing.classification.domain.compactMap(domain(named:))
                ),
                might: printing.attributes.might
            )
        }

        var battlefields: [BattlefieldID: Battlefield] = [:]
        let battlefieldPrintings = printings.filter { $0.classification.type.lowercased() == "battlefield" }
        for (index, (_, battlefieldID)) in battlefieldSlotIDs.sorted(by: { $0.key < $1.key }).enumerated() {
            let printing = index < battlefieldPrintings.count ? battlefieldPrintings[index] : nil
            battlefields[battlefieldID] = Battlefield(
                id: battlefieldID,
                definitionID: CardDefID(rawValue: printing?.riftboundID ?? "battlefield-slot-\(index)"),
                owner: localPlayerID,
                name: printing?.name ?? "Battlefield \(index)"
            )
        }

        // Rule 103.3: 12 Runes in the Rune Deck. Two of each Domain is a
        // placeholder for the player's real Rune Deck, which nothing in
        // this app captures yet — the camera can see the Rune Area but has
        // no way to be told what was put in the deck before play started.
        let runeDeck = Domain.allCases.flatMap { domain in
            (0..<2).map { index in
                RuneCard(
                    definitionID: CardDefID(rawValue: "rune-\(domain.rawValue)-\(index)"),
                    owner: localPlayerID,
                    domain: domain
                )
            }
        }

        var state = GameState(
            turnOrder: [localPlayerID],
            battlefields: battlefields,
            zones: [localPlayerID: PlayerZones(hand: hand, runeDeck: runeDeck, legend: legend)]
        )

        // Rule 515–516: run Awaken → Beginning → Channel → Draw so the
        // session actually starts where a player can act. Without this the
        // state sits at `.startOfTurn(.awaken)` and every observed Play is
        // rejected as `.notActionPhase` — correctly, but for a reason the
        // player can do nothing about, since nothing here would ever
        // advance the phase.
        state = TurnSequencer.startTurn(state)

        // Rule 157.2.a: Energy comes from Exhausting Runes, and the vision
        // layer does not yet propose `.exhaust` when it sees a rune turn
        // sideways — it only counts them (`observedExhaustedRuneCount`).
        // Until that event exists, a real pool would leave every Play
        // rejected for cost. Seeding one keeps cost from being the thing
        // that blocks play; it is explicitly NOT a rules-accurate start,
        // and the fix is the rune-exhaust event, not a bigger number.
        state.zones[localPlayerID]?.runePool.energy = 99

        return Session(
            store: GameStateStore(initialState: state),
            localPlayerID: localPlayerID,
            battlefieldSlotIDs: battlefieldSlotIDs
        )
    }

    /// Maps the bundled JSON's `classification.domain` strings (e.g.
    /// `"Fury"`) onto `RiftboundExpertSystem.Domain` (`.fury`) —
    /// case-insensitive since the JSON is Title Case and `Domain`'s raw
    /// values are lowercase. `nil` for anything that doesn't match one of
    /// the six Domains (133) rather than a guessed default — a printing
    /// with an unrecognized Domain string is a data problem worth
    /// surfacing, not silently dropping into "domainless."
    /// Not private: `CameraPipelineController` resolves domains for the
    /// validator through this same helper, so both sides of the pipeline
    /// read a printing's domain identically.
    static func domain(named raw: String) -> Domain? {
        Domain(caseInsensitive: raw)
    }

    /// Only Main Deck card types map onto `MainDeckCard` — Runes, Legends,
    /// and Battlefields are Game Objects but explicitly *not* "cards"
    /// (CLAUDE.md point 1), so they're excluded rather than coerced.
    private static func mainDeckCardType(for printing: CardPrinting) -> MainDeckCardType? {
        switch printing.classification.type.lowercased() {
        case "unit":
            let isChampion = printing.classification.supertype?.lowercased().contains("champion") ?? false
            return .unit(isChampion: isChampion)
        case "gear":
            return .gear
        case "spell":
            return .spell
        default:
            return nil
        }
    }
}
