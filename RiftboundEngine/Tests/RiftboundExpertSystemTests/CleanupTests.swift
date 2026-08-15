import Testing
@testable import RiftboundExpertSystem

/// Rule 518–526: the state-based-action sweep. Currently exercises only
/// the two steps with real logic — `markPendingCombats` (524) and
/// `beginCombatIfPending` (526) — everything else in `Cleanup.run` is
/// still a documented no-op, so a bare `Cleanup.run` call elsewhere in
/// these fixtures is safe to treat as a passthrough.
struct CleanupTests {

    /// The core worked scenario for 526: Player A moves a Unit onto a
    /// Battlefield Player B already controls a Unit at. `applyStandardMove`
    /// already sets `contestedBy` (181.3.a); Cleanup should pick that up,
    /// see two controllers present, and open a Combat Showdown with A as
    /// Attacker (549/625.1.a.1) and only the two combatants Relevant
    /// (550.2) — not the whole `turnOrder`, unlike 525's standalone case.
    @Test("Combat begins when a Move creates two controllers at one Battlefield")
    func combatBeginsOnContestedMoveIntoOccupiedBattlefield() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()

        let defendingUnit = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID))
        state.units[defendingUnit.id] = defendingUnit
        state.battlefieldControl[battlefieldID]?.controller = playerB

        let movingUnit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        state.units[movingUnit.id] = movingUnit

        GameActionApplier.apply(
            .standardMove(units: [movingUnit.id], destination: .battlefield(battlefieldID)),
            to: &state,
            proposedBy: playerA
        )

        let cleanedState = Cleanup.run(state)

        guard case .showdownOpen(let showdown) = cleanedState.turnState else {
            Issue.record("Expected a Showdown to open, got \(cleanedState.turnState)")
            return
        }
        #expect(showdown.origin == .combat(attacker: playerA, defender: playerB, battlefield: battlefieldID))
        #expect(showdown.focusPlayer == playerA)
        #expect(showdown.relevantPlayers == [playerA, playerB])
    }

    /// A Battlefield with only one controller's Units present never
    /// becomes Combat Pending — no clash, nothing for 526 to do.
    @Test("No Combat begins when only one controller has Units at the Battlefield")
    func noCombatWithOnlyOneController() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        state.units[unit.id] = unit

        let cleanedState = Cleanup.run(state)

        #expect(cleanedState.turnState.isShowdown == false)
    }

    /// Two controllers present, but `contestedBy` is missing or doesn't
    /// match either of them (e.g. Combat became Pending some way other
    /// than a fresh Move/Play this pass) — there's no reliable Attacker
    /// signal, so this is skipped rather than guessed at.
    @Test("No Combat begins when there's no reliable Attacker signal (contestedBy unset)")
    func noCombatWithoutContestedBySignal() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let unitA = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        let unitB = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID))
        state.units[unitA.id] = unitA
        state.units[unitB.id] = unitB
        // Deliberately not setting battlefieldControl[battlefieldID]?.contestedBy.

        let cleanedState = Cleanup.run(state)

        #expect(cleanedState.turnState.isShowdown == false)
    }
}
