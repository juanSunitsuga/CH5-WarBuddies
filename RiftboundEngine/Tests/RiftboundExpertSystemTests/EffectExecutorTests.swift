import Testing
@testable import RiftboundExpertSystem

/// `EffectExecutor` — the counterpart to `GameActionApplier` for the
/// effects vocabulary (`EffectInstruction`) rather than the action
/// vocabulary (`GameAction`).
struct EffectExecutorTests {

    @Test("dealDamage against .source increments the source unit's damage")
    func dealDamageAgainstSource() {
        let (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        var mutableState = state
        let unit = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        mutableState.units[unit.id] = unit

        let outcomes = EffectExecutor.run(
            [.dealDamage(amount: 3, targets: .source)],
            source: unit.id,
            resolvedTargets: [],
            to: &mutableState,
            proposedBy: playerA
        )

        #expect(mutableState.units[unit.id]?.damage == 3)
        #expect(outcomes.first?.executed == true)
    }

    @Test("dealDamage against a chosen unit consumes one resolvedTarget")
    func dealDamageAgainstChosenUnit() {
        let (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        var mutableState = state
        let attacker = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        let target = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID))
        mutableState.units[attacker.id] = attacker
        mutableState.units[target.id] = target

        EffectExecutor.run(
            [.dealDamage(amount: 5, targets: .chosenUnit())],
            source: attacker.id,
            resolvedTargets: [target.id],
            to: &mutableState,
            proposedBy: playerA
        )

        #expect(mutableState.units[target.id]?.damage == 5)
        #expect(mutableState.units[attacker.id]?.damage == 0)
    }

    @Test("chosenUnit filtered to .enemy rejects a friendly-owned resolvedTarget")
    func chosenUnitEnemyFilterRejectsFriendly() {
        let (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        var mutableState = state
        let source = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        let friendlyOther = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        mutableState.units[source.id] = source
        mutableState.units[friendlyOther.id] = friendlyOther

        let outcomes = EffectExecutor.run(
            [.dealDamage(amount: 4, targets: .chosenUnit(.enemy))],
            source: source.id,
            resolvedTargets: [friendlyOther.id],
            to: &mutableState,
            proposedBy: playerA
        )

        #expect(mutableState.units[friendlyOther.id]?.damage == 0)
        #expect(outcomes.first?.executed == false)
    }

    @Test("allUnits(.enemy) reaches every enemy unit and none of the proposer's own")
    func allUnitsEnemyFilter() {
        let (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        var mutableState = state
        let ownUnit = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        let enemyUnit1 = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID))
        let enemyUnit2 = TestFixtures.makeUnit(owner: playerB, location: .base(playerB))
        mutableState.units[ownUnit.id] = ownUnit
        mutableState.units[enemyUnit1.id] = enemyUnit1
        mutableState.units[enemyUnit2.id] = enemyUnit2

        EffectExecutor.run(
            [.dealDamage(amount: 2, targets: .allUnits(.enemy))],
            source: ownUnit.id,
            resolvedTargets: [],
            to: &mutableState,
            proposedBy: playerA
        )

        #expect(mutableState.units[ownUnit.id]?.damage == 0)
        #expect(mutableState.units[enemyUnit1.id]?.damage == 2)
        #expect(mutableState.units[enemyUnit2.id]?.damage == 2)
    }

    @Test("upToUnits(maximum:) picks at most the requested count, in order")
    func upToUnitsRespectsMaximum() {
        let (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        var mutableState = state
        let source = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        let u1 = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        let u2 = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        let u3 = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        mutableState.units[source.id] = source
        mutableState.units[u1.id] = u1
        mutableState.units[u2.id] = u2
        mutableState.units[u3.id] = u3

        EffectExecutor.run(
            [.buff(targets: .upToUnits(maximum: 2))],
            source: source.id,
            resolvedTargets: [u1.id, u2.id, u3.id],
            to: &mutableState,
            proposedBy: playerA
        )

        #expect(mutableState.units[u1.id]?.hasBuff == true)
        #expect(mutableState.units[u2.id]?.hasBuff == true)
        #expect(mutableState.units[u3.id]?.hasBuff == false)
    }

    @Test("draw moves cards from the Main Deck into Hand")
    func drawMovesCardsFromDeckToHand() {
        let (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        var mutableState = state
        mutableState.zones[playerA]?.mainDeck = [
            TestFixtures.makeMainDeckCard(owner: playerA, name: "Card 1"),
            TestFixtures.makeMainDeckCard(owner: playerA, name: "Card 2"),
        ]
        let startingHandCount = mutableState.zones[playerA]?.hand.count ?? 0

        EffectExecutor.run(
            [.draw(count: 1)],
            source: nil,
            resolvedTargets: [],
            to: &mutableState,
            proposedBy: playerA
        )

        #expect(mutableState.zones[playerA]?.hand.count == startingHandCount + 1)
        #expect(mutableState.zones[playerA]?.mainDeck.count == 1)
    }

    @Test("killUnit removes the resolved unit from the board")
    func killUnitRemovesFromBoard() {
        let (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        var mutableState = state
        let source = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        let victim = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID))
        mutableState.units[source.id] = source
        mutableState.units[victim.id] = victim

        EffectExecutor.run(
            [.killUnit(targets: .chosenUnit(.enemy))],
            source: source.id,
            resolvedTargets: [victim.id],
            to: &mutableState,
            proposedBy: playerA
        )

        #expect(mutableState.units[victim.id] == nil)
        #expect(mutableState.units[source.id] != nil)
    }

    @Test("A case with no producer yet (counterSpell) reports itself as not executed, without mutating state")
    func unimplementedCaseReportsNotExecuted() {
        let (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        var mutableState = state
        let unit = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        mutableState.units[unit.id] = unit

        let outcomes = EffectExecutor.run(
            [.counterSpell(targets: .source)],
            source: unit.id,
            resolvedTargets: [],
            to: &mutableState,
            proposedBy: playerA
        )

        #expect(outcomes.first?.executed == false)
        #expect(mutableState.units[unit.id]?.isExhausted == unit.isExhausted)
    }
}
