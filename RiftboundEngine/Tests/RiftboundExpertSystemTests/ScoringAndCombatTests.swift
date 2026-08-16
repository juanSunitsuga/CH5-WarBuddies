import Testing
@testable import RiftboundExpertSystem

/// Rules 620–633: how a Showdown turns into damage, Control, and Points.
///
/// The two scoring methods (630) are the whole win condition:
///   - **Hold** — you Control a Battlefield during your Beginning Phase.
///   - **Conquer** — you gain Control of one you haven't Scored this turn,
///     which in practice means winning a Showdown as the attacker: by
///     627.3, no Defending Units remain and yours do.
struct ScoringAndCombatTests {

    private static func showdown(
        attacker: PlayerID,
        defender: PlayerID,
        battlefield: BattlefieldID
    ) -> Showdown {
        Showdown(
            origin: .combat(attacker: attacker, defender: defender, battlefield: battlefield),
            focusPlayer: attacker,
            relevantPlayers: [attacker, defender]
        )
    }

    // MARK: - Combat damage and resolution (626–627)

    /// 626.1.b/c + 627.1: each side deals damage equal to summed Might;
    /// units with lethal damage are removed. A 5-Might attacker against a
    /// 3-Might defender kills it and survives.
    @Test("The stronger side kills the weaker and survives")
    func strongerAttackerKillsDefender() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let attacker = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID), might: 5)
        let defender = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID), might: 3)
        state.units[attacker.id] = attacker
        state.units[defender.id] = defender
        state.battlefieldControl[battlefieldID]?.controller = playerB

        let outcome = Combat.resolve(Self.showdown(attacker: playerA, defender: playerB, battlefield: battlefieldID), in: state)

        #expect(outcome.state.units[defender.id] == nil)         // 627.1
        #expect(outcome.state.units[attacker.id] != nil)
        #expect(outcome.state.zones[playerB]?.trash.count == 1)  // 107.1.d: owner's trash
    }

    /// 627.3: "The Battlefield is Conquered if No Defending Units Remain
    /// but Attacking Units do remain" — Control changes (627.3.a), which is
    /// exactly rule 630.1's definition of a Conquer, so a Point follows.
    @Test("Winning a showdown as the attacker conquers the battlefield and scores")
    func winningAsAttackerConquersAndScores() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let attacker = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID), might: 5)
        let defender = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID), might: 3)
        state.units[attacker.id] = attacker
        state.units[defender.id] = defender
        state.battlefieldControl[battlefieldID]?.controller = playerB

        let outcome = Combat.resolve(Self.showdown(attacker: playerA, defender: playerB, battlefield: battlefieldID), in: state)

        #expect(outcome.state.battlefieldControl[battlefieldID]?.controller == playerA)
        #expect(outcome.state.scores[playerA] == 1)
        #expect(outcome.state.battlefieldControl[battlefieldID]?.isContested == false)  // 627.4
        #expect(outcome.events.contains { if case .scored = $0 { return true } else { return false } })
    }

    /// Evenly matched units destroy each other (626.1.a.1's "neither
    /// Attacking Units nor Defending Units remain"). 627.3 needs Attacking
    /// Units to remain, so there is no Conquer — and with nobody left
    /// standing there, 181.4.d strips the defender's Control too.
    ///
    /// Note this is what an even trade *is* here: 1 Might against 1 Might
    /// is mutual destruction, not a standoff. 627.2's both-sides-survive
    /// branch can't be reached by damage alone — see the arithmetic in
    /// `Combat.resolve` — so it isn't tested here rather than being tested
    /// with a scenario that doesn't actually produce it.
    @Test("Evenly matched units destroy each other and nobody conquers")
    func evenTradeLeavesNobodyInControl() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let attacker = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID), might: 1)
        let defender = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID), might: 1)
        state.units[attacker.id] = attacker
        state.units[defender.id] = defender
        state.battlefieldControl[battlefieldID]?.controller = playerB

        let outcome = Combat.resolve(Self.showdown(attacker: playerA, defender: playerB, battlefield: battlefieldID), in: state)

        #expect(outcome.state.units[attacker.id] == nil)
        #expect(outcome.state.units[defender.id] == nil)
        #expect(outcome.state.battlefieldControl[battlefieldID]?.controller == nil)  // 181.4.d
        #expect(outcome.state.scores[playerA] == 0)                                   // 627.3 unmet
    }

    /// 626.1.d.2: "Units must have lethal damage assigned to them in full
    /// before damage is assigned to a different Unit" — 5 damage against
    /// two 3-Might units kills exactly one, never wounds both.
    @Test("Damage is assigned lethally to one unit before spilling to the next")
    func damageIsAssignedLethalFirst() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let attacker = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID), might: 5)
        let firstDefender = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID), might: 3)
        let secondDefender = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID), might: 3)
        state.units[attacker.id] = attacker
        state.units[firstDefender.id] = firstDefender
        state.units[secondDefender.id] = secondDefender

        let outcome = Combat.resolve(Self.showdown(attacker: playerA, defender: playerB, battlefield: battlefieldID), in: state)

        let survivingDefenders = outcome.state.units.values.filter { $0.controller == playerB }
        #expect(survivingDefenders.count == 1)
    }

    /// 516.5.b: moving into an *empty* Battlefield opens a standalone
    /// Showdown, not a Combat — no damage, but 181.4.a still hands Control
    /// to the player whose Units are now there, and gaining Control is a
    /// Conquer (630.1). This is the ordinary "walk onto an unclaimed
    /// battlefield and take it" play.
    @Test("Taking an empty battlefield unopposed conquers it")
    func standaloneShowdownConquersEmptyBattlefield() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        state.units[unit.id] = unit

        let standalone = Showdown(
            origin: .standalone(battlefield: battlefieldID),
            focusPlayer: playerA,
            relevantPlayers: [playerA]
        )
        let outcome = Combat.resolve(standalone, in: state)

        #expect(outcome.state.units[unit.id] != nil)   // no damage step
        #expect(outcome.state.battlefieldControl[battlefieldID]?.controller == playerA)
        #expect(outcome.state.scores[playerA] == 1)
    }

    // MARK: - Hold (630.2)

    /// 515.2.b.1/630.2: "A player has Control of a Battlefield during their
    /// Beginning Phase." Holding is passive — you scored by still being
    /// there when your turn came around.
    @Test("Controlling a battlefield at your Beginning Phase scores a point")
    func holdScoresAtBeginningPhase() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState(phase: .startOfTurn(.beginning))
        state.battlefieldControl[battlefieldID]?.controller = playerA

        state = TurnSequencer.advance(state)

        #expect(state.scores[playerA] == 1)
        #expect(state.battlefieldControl[battlefieldID]?.scoredThisTurnBy.contains(playerA) == true)
    }

    @Test("A battlefield the opponent controls scores nothing at your Beginning Phase")
    func noHoldWithoutControl() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState(phase: .startOfTurn(.beginning))
        state.battlefieldControl[battlefieldID]?.controller = playerB

        state = TurnSequencer.advance(state)

        #expect(state.scores[playerA] == 0)
    }

    // MARK: - The once-per-turn cap (631)

    /// 631: "A player may only Score, from either method, once per
    /// Battlefield per turn." Holding it at the Beginning Phase and then
    /// re-conquering it later the same turn is one Point, not two.
    @Test("Holding then re-conquering the same battlefield in one turn scores once")
    func holdAndConquerSameTurnScoresOnce() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState(phase: .startOfTurn(.beginning))
        state.battlefieldControl[battlefieldID]?.controller = playerA

        state = TurnSequencer.advance(state)         // Hold: +1
        #expect(state.scores[playerA] == 1)

        // The same battlefield changes hands and comes back this turn.
        state.battlefieldControl[battlefieldID]?.controller = playerB
        _ = Scoring.scoreConquer(battlefieldID, by: playerA, in: &state)

        #expect(state.scores[playerA] == 1)          // 631: still one
    }

    // MARK: - The final point (632.1.b) and victory (633)

    /// 632.1.b.1: "If the player has Scored through Hold, that player
    /// scores the Final Point." A Hold ends the game outright.
    @Test("A Hold takes the final point and wins")
    func holdTakesFinalPointAndWins() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState(phase: .startOfTurn(.beginning))
        state.battlefieldControl[battlefieldID]?.controller = playerA
        state.scores[playerA] = state.victoryScore - 1

        let outcome = TurnSequencer.advanceReporting(state)

        #expect(outcome.state.scores[playerA] == outcome.state.victoryScore)
        #expect(outcome.state.winner == playerA)       // 633
        #expect(outcome.events.contains { if case .gameWon = $0 { return true } else { return false } })
    }

    /// 632.1.b.2: a Conquer takes the Final Point only if the player has
    /// Scored *every* Battlefield this turn. Otherwise "that player draws a
    /// card" — no Point, no win. The asymmetry with Hold is deliberate and
    /// easy to miss: you cannot steal the last point with one late attack.
    @Test("A lone Conquer does not take the final point — it draws a card instead")
    func conquerWithoutEveryBattlefieldDrawsInstead() {
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
        state.scores[playerA] = state.victoryScore - 1

        // Conquering only one of the two battlefields this turn.
        _ = Scoring.scoreConquer(first.id, by: playerA, in: &state)

        #expect(state.scores[playerA] == state.victoryScore - 1)   // no point
        #expect(state.winner == nil)                                // no win
        #expect(state.pendingLimitedActions[playerA]?.contains(.draw(count: 1)) == true)
    }

    /// The other half of 632.1.b.2: having Scored every Battlefield this
    /// turn, the Conquer does take the Final Point.
    @Test("A Conquer completing every battlefield this turn does take the final point")
    func conquerCompletingTheBoardTakesFinalPoint() {
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
        state.scores[playerA] = state.victoryScore - 2

        _ = Scoring.scoreConquer(first.id, by: playerA, in: &state)
        _ = Scoring.scoreConquer(second.id, by: playerA, in: &state)

        #expect(state.scores[playerA] == state.victoryScore)
        #expect(state.winner == playerA)
    }

    /// 633: "they Win the Game immediately." Nothing after that is legal —
    /// a stray observed move must not be applied to a finished game.
    @Test("Nothing is legal once the game has been won")
    func nothingIsLegalAfterAWin() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        state.winner = playerA
        let unit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        state.units[unit.id] = unit

        let result = LegalityValidator.validate(
            .standardMove(units: [unit.id], destination: .battlefield(battlefieldID)),
            in: state, proposedBy: playerA
        )

        #expect(result.failureValue == .gameAlreadyWon(playerA))
    }

    // MARK: - Control follows presence (181.4)

    /// 181.4.d: a player with no Units at a Battlefield has no Control of
    /// it. Control outliving the Units that established it isn't just an
    /// untidy field — 525 only opens a Showdown at a Contested Battlefield
    /// with *no* Controller, so an abandoned-but-still-"controlled"
    /// Battlefield can never be Conquered by anyone. It looks completely
    /// normal on the table and is quietly unwinnable.
    @Test("A battlefield whose controller has no units there becomes uncontrolled")
    func abandonedBattlefieldLosesItsController() {
        var (state, _, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        state.battlefieldControl[battlefieldID]?.controller = playerB
        // playerB controls it on paper but has no units there — their unit
        // went home to their base.
        let departed = TestFixtures.makeUnit(owner: playerB, location: .base(playerB))
        state.units[departed.id] = departed

        state = Cleanup.run(state)

        #expect(state.battlefieldControl[battlefieldID]?.controller == nil)
    }

    /// 181.4.b: "A player maintains control of a Battlefield while it is
    /// being Contested by an opponent" — a pending Combat must not strip
    /// the defender's Control before it resolves, or the attacker would win
    /// the Battlefield by arriving rather than by fighting.
    @Test("A contested battlefield keeps its controller until the combat resolves")
    func contestedBattlefieldKeepsItsController() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        state.battlefieldControl[battlefieldID]?.controller = playerB
        let defender = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID))
        let attacker = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID))
        state.units[defender.id] = defender
        state.units[attacker.id] = attacker

        state = Cleanup.run(state)

        #expect(state.battlefieldControl[battlefieldID]?.controller == playerB)
    }

    // MARK: - End to end

    /// The most common play in a physical game, driven end to end: move a
    /// unit onto an empty battlefield, which opens a standalone Showdown
    /// (516.5.b) rather than a Combat, then pass it out to take the
    /// battlefield and score the Conquer.
    @Test("Moving onto an empty battlefield opens a showdown and conquers it")
    func movingOntoEmptyBattlefieldConquersIt() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        state.units[unit.id] = unit

        GameActionApplier.apply(
            .standardMove(units: [unit.id], destination: .battlefield(battlefieldID)),
            to: &state, proposedBy: playerA
        )
        state = Cleanup.run(state)

        guard case .showdownOpen(let showdown) = state.turnState else {
            Issue.record("Expected a standalone Showdown to have opened, got \(state.turnState)")
            return
        }
        // 550.2: not part of a Combat, so *all* players are Relevant.
        #expect(showdown.relevantPlayers == Set([playerA, playerB]))
        #expect(showdown.focusPlayer == playerA)   // 549

        GameActionApplier.apply(.pass, to: &state, proposedBy: playerA)
        GameActionApplier.apply(.pass, to: &state, proposedBy: playerB)

        #expect(state.battlefieldControl[battlefieldID]?.controller == playerA)
        #expect(state.scores[playerA] == 1)
        #expect(state.units[unit.id]?.location == .battlefield(battlefieldID))
    }

    /// The full arc the user described, driven only through public
    /// actions: move a unit onto a defended battlefield (which opens a
    /// Combat Showdown via Cleanup 526), both players pass out of the
    /// Showdown (553.4.a), combat resolves, and the attacker conquers.
    @Test("Move into a defended battlefield, pass the showdown, conquer")
    func moveThenPassResolvesCombatAndConquers() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()

        let defender = TestFixtures.makeUnit(owner: playerB, location: .battlefield(battlefieldID), might: 2)
        state.units[defender.id] = defender
        state.battlefieldControl[battlefieldID]?.controller = playerB

        let attacker = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false, might: 6)
        state.units[attacker.id] = attacker

        GameActionApplier.apply(
            .standardMove(units: [attacker.id], destination: .battlefield(battlefieldID)),
            to: &state, proposedBy: playerA
        )
        state = Cleanup.run(state)

        guard case .showdownOpen = state.turnState else {
            Issue.record("Expected a Combat Showdown to have opened, got \(state.turnState)")
            return
        }

        GameActionApplier.apply(.pass, to: &state, proposedBy: playerA)
        GameActionApplier.apply(.pass, to: &state, proposedBy: playerB)

        #expect(state.units[defender.id] == nil)
        #expect(state.battlefieldControl[battlefieldID]?.controller == playerA)
        #expect(state.scores[playerA] == 1)
        guard case .neutralOpen = state.turnState else {
            Issue.record("Expected to be back in Neutral Open after combat, got \(state.turnState)")
            return
        }
    }
}
