@testable import RiftboundExpertSystem

/// Minimal factory helpers for constructing `GameState` in tests without
/// repeating full deck/zone boilerplate every time. Expand as more of the
/// engine gets real logic — keep this file dependency-light and synchronous.
enum TestFixtures {
    static func makePlayer() -> PlayerID { PlayerID() }

    static func makeLegend(owner: PlayerID, name: String = "Test Legend", tag: String = "TestChamp") -> ChampionLegend {
        ChampionLegend(
            definitionID: CardDefID(rawValue: "legend-\(name)"),
            owner: owner,
            name: name,
            domains: [.fury],
            championTag: tag
        )
    }

    static func makeZones(owner: PlayerID) -> PlayerZones {
        PlayerZones(legend: makeLegend(owner: owner))
    }

    static func makeBattlefield(owner: PlayerID, name: String = "Test Battlefield") -> Battlefield {
        Battlefield(definitionID: CardDefID(rawValue: "bf-\(name)"), owner: owner, name: name)
    }

    static func makeUnit(
        owner: PlayerID,
        controller: PlayerID? = nil,
        location: Location,
        isExhausted: Bool = false,
        might: Int = 3
    ) -> Unit {
        Unit(
            owner: owner,
            controller: controller,
            cardDefinitionID: CardDefID(rawValue: "unit-test"),
            name: "Test Unit",
            isChampion: false,
            baseMight: might,
            location: location,
            isExhausted: isExhausted
        )
    }

    static func makeMainDeckCard(owner: PlayerID, name: String = "Test Spell") -> MainDeckCard {
        MainDeckCard(definitionID: CardDefID(rawValue: "card-\(name)"), owner: owner, name: name, type: .spell)
    }

    /// Two-player game state, one Battlefield each player nominally owns,
    /// no units placed yet. Caller adds units/mutates as needed.
    static func makeTwoPlayerState() -> (state: GameState, playerA: PlayerID, playerB: PlayerID, battlefield: BattlefieldID) {
        let playerA = makePlayer()
        let playerB = makePlayer()
        let battlefield = makeBattlefield(owner: playerA)

        let state = GameState(
            turnOrder: [playerA, playerB],
            battlefields: [battlefield.id: battlefield],
            zones: [
                playerA: makeZones(owner: playerA),
                playerB: makeZones(owner: playerB)
            ]
        )
        return (state, playerA, playerB, battlefield.id)
    }
}

/// `ActionTranslating` stub that always proposes a single fixed
/// `GameAction`, regardless of the observed event — sufficient for driving
/// `GameEngine.process` in tests without a real NLP layer (CLAUDE.md's
/// testing guidance: this is the seam `process` was written to expose).
struct FixedActionTranslator: ActionTranslating {
    let action: GameAction?

    func inferAction(from event: ObservedTableEvent, in state: GameState, proposedBy player: PlayerID) async -> GameAction? {
        action
    }

    func parseAbility(rawText: String, cardDefinitionID: CardDefID) async -> [EffectInstruction] {
        []
    }
}

/// `BoardObserving` stub — unused by `process(_:)` directly (only `run()`
/// consumes it), but `GameEngine.init` requires one.
struct NeverObserving: BoardObserving {
    func events() -> AsyncStream<ObservedTableEvent> {
        AsyncStream { $0.finish() }
    }
}
