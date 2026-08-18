import Testing
@testable import RiftboundExpertSystem

/// Rule 140.4: where a Standard Move may actually go.
///
/// The permitted set is small and worth stating plainly, because the engine
/// previously checked none of it — any Location was accepted as a
/// destination, so a unit could hop straight from one Battlefield to
/// another without Ganking, which skips a Showdown it should have had to
/// fight for.
///
///   - 140.4.a: Base → Battlefield
///   - 140.4.b: Battlefield → Base
///   - 140.4.c.1: Battlefield → Battlefield, **only** with Ganking (722)
struct MoveDestinationTests {

    private static func twoBattlefieldState() -> (GameState, PlayerID, PlayerID, BattlefieldID, BattlefieldID) {
        let playerA = TestFixtures.makePlayer()
        let playerB = TestFixtures.makePlayer()
        let first = TestFixtures.makeBattlefield(owner: playerA, name: "First")
        let second = TestFixtures.makeBattlefield(owner: playerB, name: "Second")

        var state = GameState(
            turnOrder: [playerA, playerB],
            battlefields: [first.id: first, second.id: second],
            zones: [
                playerA: TestFixtures.makeZones(owner: playerA),
                playerB: TestFixtures.makeZones(owner: playerB)
            ]
        )
        state.phase = .action
        return (state, playerA, playerB, first.id, second.id)
    }

    @Test("Base to Battlefield is legal")
    func baseToBattlefieldIsLegal() {
        var (state, playerA, _, battlefieldID, _) = Self.twoBattlefieldState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        state.units[unit.id] = unit

        #expect(LegalityValidator.validate(
            .standardMove(units: [unit.id], destination: .battlefield(battlefieldID)),
            in: state, proposedBy: playerA
        ).isSuccess)
    }

    @Test("Battlefield to Base is legal")
    func battlefieldToBaseIsLegal() {
        var (state, playerA, _, battlefieldID, _) = Self.twoBattlefieldState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID), isExhausted: false)
        state.units[unit.id] = unit

        #expect(LegalityValidator.validate(
            .standardMove(units: [unit.id], destination: .base(playerA)),
            in: state, proposedBy: playerA
        ).isSuccess)
    }

    /// 140.4.c.1: Battlefield to Battlefield is Ganking's whole privilege.
    /// Without it the move is illegal — the unit has to go home first,
    /// which costs it a turn and gives the opponent a window.
    @Test("Battlefield to Battlefield is illegal without Ganking")
    func battlefieldToBattlefieldNeedsGanking() {
        var (state, playerA, _, first, second) = Self.twoBattlefieldState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .battlefield(first), isExhausted: false)
        state.units[unit.id] = unit

        let result = LegalityValidator.validate(
            .standardMove(units: [unit.id], destination: .battlefield(second)),
            in: state, proposedBy: playerA
        )

        #expect(result.failureValue == .illegalMoveDestination(from: .battlefield(first), to: .battlefield(second)))
    }

    @Test("Battlefield to Battlefield is legal with Ganking")
    func gankingAllowsBattlefieldToBattlefield() {
        var (state, playerA, _, first, second) = Self.twoBattlefieldState()
        var unit = TestFixtures.makeUnit(owner: playerA, location: .battlefield(first), isExhausted: false)
        unit.printedKeywords = [.ganking]
        state.units[unit.id] = unit

        #expect(LegalityValidator.validate(
            .standardMove(units: [unit.id], destination: .battlefield(second)),
            in: state, proposedBy: playerA
        ).isSuccess)
    }

    /// Base → Base is absent from 140.4 entirely. It isn't a Move; in
    /// practice it means tracking mistook a card being nudged for a play.
    @Test("Base to Base is not a move")
    func baseToBaseIsIllegal() {
        var (state, playerA, _, _, _) = Self.twoBattlefieldState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        state.units[unit.id] = unit

        let result = LegalityValidator.validate(
            .standardMove(units: [unit.id], destination: .base(playerA)),
            in: state, proposedBy: playerA
        )

        #expect(result.failureValue == .illegalMoveDestination(from: .base(playerA), to: .base(playerA)))
    }

    /// Moving to the Battlefield a unit already occupies would pay the
    /// Exhaust cost (140.2) for no change of Location — the camera saw
    /// jitter, not a move.
    @Test("Moving to the battlefield the unit is already at is rejected")
    func movingNowhereIsRejected() {
        var (state, playerA, _, battlefieldID, _) = Self.twoBattlefieldState()
        var unit = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID), isExhausted: false)
        unit.printedKeywords = [.ganking]   // even Ganking doesn't make this a move
        state.units[unit.id] = unit

        let result = LegalityValidator.validate(
            .standardMove(units: [unit.id], destination: .battlefield(battlefieldID)),
            in: state, proposedBy: playerA
        )

        #expect(!result.isSuccess)
    }

    /// 140.3.a: "When a Move like this is declared by a player, the units'
    /// Destination must be the same." One Move, one Destination — which is
    /// what makes each Showdown about exactly one Battlefield. Enforced
    /// structurally: `GameAction.standardMove` carries a single
    /// `destination` for the whole group, so two battlefields at once is
    /// unrepresentable rather than merely rejected.
    ///
    /// 140.3.b: Origins need not match, and this checks that too — one unit
    /// coming from each Base still moves as one group.
    @Test("Units with different origins can move together to one destination")
    func multipleOriginsOneDestination() {
        var (state, playerA, _, battlefieldID, otherBattlefield) = Self.twoBattlefieldState()
        let fromBase = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        var fromBattlefield = TestFixtures.makeUnit(owner: playerA, location: .battlefield(otherBattlefield), isExhausted: false)
        fromBattlefield.printedKeywords = [.ganking]
        state.units[fromBase.id] = fromBase
        state.units[fromBattlefield.id] = fromBattlefield

        #expect(LegalityValidator.validate(
            .standardMove(units: [fromBase.id, fromBattlefield.id], destination: .battlefield(battlefieldID)),
            in: state, proposedBy: playerA
        ).isSuccess)
    }

    /// A group Move is all-or-nothing: one unit with an illegal origin
    /// invalidates the declaration rather than moving the rest.
    @Test("A group move is rejected if any single unit's move is illegal")
    func groupMoveRejectedIfAnyMemberIsIllegal() {
        var (state, playerA, _, battlefieldID, otherBattlefield) = Self.twoBattlefieldState()
        let legal = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        let illegal = TestFixtures.makeUnit(owner: playerA, location: .battlefield(otherBattlefield), isExhausted: false)
        state.units[legal.id] = legal
        state.units[illegal.id] = illegal

        let result = LegalityValidator.validate(
            .standardMove(units: [legal.id, illegal.id], destination: .battlefield(battlefieldID)),
            in: state, proposedBy: playerA
        )

        #expect(!result.isSuccess)
    }
}
