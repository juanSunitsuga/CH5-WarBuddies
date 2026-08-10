import Testing
@testable import RiftboundExpertSystem

struct LegalityValidatorTests {

    @Test("Standard Move is legal for a readied unit moving to an empty battlefield")
    func legalMoveToEmptyBattlefield() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        state.units[unit.id] = unit

        let result = LegalityValidator.validate(
            .standardMove(units: [unit.id], destination: .battlefield(battlefieldID)),
            in: state,
            proposedBy: playerA
        )

        #expect(result.isSuccess)
    }

    @Test("Standard Move is illegal when the unit is already exhausted (rule 592.1.b)")
    func illegalMoveWhenExhausted() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: true)
        state.units[unit.id] = unit

        let result = LegalityValidator.validate(
            .standardMove(units: [unit.id], destination: .battlefield(battlefieldID)),
            in: state,
            proposedBy: playerA
        )

        #expect(result.failureValue == .unitAlreadyExhausted(unit.id))
    }

    /// Worked scenario from rule 140.4.a.1 / 610.2 / 623.2: a unit cannot
    /// move to (nor, per 623.2, be played to) a Battlefield that already
    /// has units controlled by 2 *other* players. This models a 3-player
    /// game (Skirmish/War mode, rules 646–647) where Battlefield X already
    /// has units from Player B and Player C, and Player A attempts to move
    /// a third unit in.
    @Test("Standard Move is illegal into a battlefield already occupied by two other controllers")
    func illegalMoveIntoThreeWayBattlefield() {
        let playerA = TestFixtures.makePlayer()
        let playerB = TestFixtures.makePlayer()
        let playerC = TestFixtures.makePlayer()
        let battlefield = TestFixtures.makeBattlefield(owner: playerA)

        var state = GameState(
            turnOrder: [playerA, playerB, playerC],
            battlefields: [battlefield.id: battlefield],
            zones: [
                playerA: TestFixtures.makeZones(owner: playerA),
                playerB: TestFixtures.makeZones(owner: playerB),
                playerC: TestFixtures.makeZones(owner: playerC)
            ]
        )

        let unitB = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefield.id))
        let unitC = TestFixtures.makeUnit(owner: playerC, location: .battlefield(battlefield.id))
        let movingUnit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        state.units[unitB.id] = unitB
        state.units[unitC.id] = unitC
        state.units[movingUnit.id] = movingUnit

        let result = LegalityValidator.validate(
            .standardMove(units: [movingUnit.id], destination: .battlefield(battlefield.id)),
            in: state,
            proposedBy: playerA
        )

        #expect(result.failureValue == .destinationOccupiedByTwoOtherControllers(battlefield.id))
    }
}

private extension Result where Success == Void, Failure == LegalityValidator.Failure {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var failureValue: LegalityValidator.Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
