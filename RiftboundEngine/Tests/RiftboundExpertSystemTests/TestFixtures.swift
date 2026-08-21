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

    static func makeRuneCard(owner: PlayerID, domain: Domain = .fury) -> RuneCard {
        RuneCard(definitionID: CardDefID(rawValue: "rune-\(domain.rawValue)"), owner: owner, domain: domain)
    }

    /// Puts already-Channeled Runes in `owner`'s Rune Area (606.1), as if
    /// their Channel Phase had run. Returns their IDs so a test can Exhaust
    /// specific ones.
    @discardableResult
    static func channelRunes(
        _ domains: [Domain],
        for owner: PlayerID,
        exhausted: Bool = false,
        into state: inout GameState
    ) -> [ObjectID] {
        domains.map { domain in
            let rune = Rune(owner: owner, card: makeRuneCard(owner: owner, domain: domain), isExhausted: exhausted)
            state.runes[rune.id] = rune
            return rune.id
        }
    }

    /// Stocks `owner`'s Rune Deck so a Channel Step has something to draw
    /// from — 515.3.b.1 channels "as many as possible," so an empty deck
    /// silently channels nothing.
    static func stockRuneDeck(_ domains: [Domain], for owner: PlayerID, in state: inout GameState) {
        state.zones[owner]?.runeDeck = domains.map { makeRuneCard(owner: owner, domain: $0) }
    }

    /// Two-player game state, one Battlefield each player nominally owns,
    /// no units placed yet. Caller adds units/mutates as needed.
    ///
    /// Starts in the **Action Phase** (516), because that's the only phase
    /// a player takes Discretionary Actions in and almost every test here
    /// is about one. A `GameState` fresh from its initializer sits at
    /// `.startOfTurn(.awaken)` — realistic, but it would make every play/
    /// move test fail on `.notActionPhase` before reaching what it's
    /// actually checking. Tests about the turn structure itself pass
    /// `phase:` explicitly instead.
    static func makeTwoPlayerState(
        phase: Phase = .action
    ) -> (state: GameState, playerA: PlayerID, playerB: PlayerID, battlefield: BattlefieldID) {
        let playerA = makePlayer()
        let playerB = makePlayer()
        let battlefield = makeBattlefield(owner: playerA)

        var state = GameState(
            turnOrder: [playerA, playerB],
            battlefields: [battlefield.id: battlefield],
            zones: [
                playerA: makeZones(owner: playerA),
                playerB: makeZones(owner: playerB)
            ]
        )
        state.phase = phase
        return (state, playerA, playerB, battlefield.id)
    }
}

/// `ActionTranslating` stub that always proposes a single fixed
/// `GameAction`, regardless of the observed event — sufficient for driving
/// `GameEngine.process` in tests without a real NLP layer (CLAUDE.md's
/// testing guidance: this is the seam `process` was written to expose).
struct FixedActionTranslator: ActionTranslating {
    let action: GameAction?
    /// Returned by `parseAbility` regardless of `cardDefinitionID` — good
    /// enough for a single-card test, which is all this fixture is used
    /// for. Defaults empty so existing call sites that don't care about
    /// ability resolution keep seeing exactly the old no-op behavior.
    var abilityInstructions: [EffectInstruction] = []

    func inferAction(from event: ObservedTableEvent, in state: GameState, proposedBy player: PlayerID) async -> GameAction? {
        action
    }

    func parseAbility(cardDefinitionID: CardDefID) async -> [EffectInstruction] {
        abilityInstructions
    }
}

/// `BoardObserving` stub — unused by `process(_:)` directly (only `run()`
/// consumes it), but `GameEngine.init` requires one.
struct NeverObserving: BoardObserving {
    func events() -> AsyncStream<ObservedTableEvent> {
        AsyncStream { $0.finish() }
    }
}

/// Assertion helpers for `LegalityValidator.validate`'s result.
///
/// Defined once here rather than `private` in each test file: three
/// identical copies had accumulated, which is the same duplication trap
/// CLAUDE.md flags for view helpers — a fourth test file wanting these
/// should not have to paste them again.
extension Result where Success == Void, Failure == LegalityValidator.Failure {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var failureValue: LegalityValidator.Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
