import Testing
import Foundation
@testable import RiftboundExpertSystem

/// The claim these tests exist to keep honest: the rules are data, and the
/// Swift side is an inference engine that holds none of them.
///
/// That is easy to assert and easy to quietly lose — one Swift `if` added
/// back into the validator for a rule that "didn't fit the file" and the
/// separation is gone while every other test still passes. So the central
/// test here states rule 140.4 differently *in data only* and requires the
/// verdict to change with it. If anyone re-implements that rule in code,
/// this fails rather than the design silently rotting.
@Suite("Rule Base")
struct RuleBaseTests {

    // MARK: - The shipped file

    @Test("The bundled rule base loads")
    func bundledRuleBaseLoads() {
        let ruleBase = RuleBase.bundled
        #expect(!ruleBase.rules.isEmpty)
        #expect(!ruleBase.moveDestinations.isEmpty)
    }

    /// A misspelled `kind` would not fail to decode — it would quietly
    /// become `.notImplemented`, so a real rejection would report "not
    /// modeled" and the rule would look like a gap in the engine. Nothing
    /// else catches that, because the rule still fires.
    @Test("Every failure kind in the file is one the engine can build")
    func everyFailureKindIsKnown() {
        let known: Set<String> = [
            "gameAlreadyWon", "notActionPhase", "notPlayersPriority", "cardNotInHand",
            "reactionRequired", "actionOrReactionRequired", "invalidPlayDestination",
            "destinationOccupiedByTwoOtherControllers", "insufficientEnergy",
            "insufficientPower", "exhaustedRuneCountMismatch", "unitNotFound",
            "unitAlreadyExhausted", "illegalMoveDestination", "moveOriginsMismatch",
            "noRuneOfDomainAvailable", "limitedActionNotAuthorized", "notImplemented"
        ]
        for rule in RuleBase.bundled.rules {
            #expect(known.contains(rule.failure.kind), "Rule \(rule.id) reports '\(rule.failure.kind)'")
        }
    }

    /// Order in the file is rule precedence, and 633 has to come first: a
    /// finished game ends every other question, so any rule read before it
    /// could report a cost or a phase problem for a game that is already
    /// over.
    @Test("Rule 633 is read before anything else")
    func gameOverIsReadFirst() {
        #expect(RuleBase.bundled.rules.first?.failure.kind == "gameAlreadyWon")
    }

    // MARK: - Rules really are data

    /// 140.4.c.1 says Battlefield → Battlefield needs Ganking. Stating the
    /// table without that requirement — in JSON, against the same compiled
    /// engine — has to make the same move legal. That is the whole
    /// separation, in one test.
    @Test("Dropping Ganking from the rule text legalizes a move the shipped rules reject")
    func statingTheRuleDifferentlyChangesTheVerdict() throws {
        var (state, playerA, _, first, second) = Self.twoBattlefieldState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .battlefield(first), isExhausted: false)
        state.units[unit.id] = unit
        let move = GameAction.standardMove(units: [unit.id], destination: .battlefield(second))

        // As shipped: illegal, because the unit has no Ganking.
        #expect(
            LegalityValidator.validate(move, in: state, proposedBy: playerA).failureValue
                == .illegalMoveDestination(from: .battlefield(first), to: .battlefield(second))
        )

        // Same engine, same board, the requirement removed from the text.
        let houseRules = try Self.moveRuleBase(destinations: """
        [
          { "id": "140.4.a", "from": "base", "to": "battlefield" },
          { "id": "140.4.b", "from": "battlefield", "to": "base" },
          { "id": "house-rule", "from": "battlefield", "to": "battlefield", "distinct": true }
        ]
        """)
        #expect(LegalityValidator.validate(move, in: state, proposedBy: playerA, using: houseRules).isSuccess)
    }

    /// The other direction: a destination is illegal because it is *absent*
    /// from the table, not because Swift says so. An empty table rejects
    /// every move, including the two the shipped file allows.
    @Test("An empty destination table rejects every move")
    func emptyTableRejectsEveryMove() throws {
        var (state, playerA, _, first, _) = Self.twoBattlefieldState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .base(playerA), isExhausted: false)
        state.units[unit.id] = unit

        let noDestinations = try Self.moveRuleBase(destinations: "[]")
        #expect(
            LegalityValidator.validate(
                .standardMove(units: [unit.id], destination: .battlefield(first)),
                in: state, proposedBy: playerA, using: noDestinations
            ).failureValue == .illegalMoveDestination(from: .base(playerA), to: .battlefield(first))
        )
    }

    // MARK: - The condition language

    /// A fact the file names but the board does not supply makes its rule
    /// fail, not crash. Rule order is what keeps a rule from reading an
    /// absent fact in the shipped file; this is the behaviour when an edit
    /// gets that wrong.
    @Test("A fact the file names but the board doesn't have fails its rule rather than trapping")
    func absentFactFailsClosed() throws {
        let (state, playerA, _, _, _) = Self.twoBattlefieldState()
        let ruleBase = try Self.decode("""
        {
          "version": "test",
          "rules": [
            {
              "id": "made-up",
              "appliesTo": ["pass"],
              "require": { "atLeast": ["noSuchFact", 1] },
              "failure": { "kind": "notImplemented" }
            }
          ],
          "moveDestinations": []
        }
        """)
        #expect(
            LegalityValidator.validate(.pass, in: state, proposedBy: playerA, using: ruleBase).failureValue
                == .notImplemented
        )
    }

    /// `when` narrows a rule; an unmet guard skips it rather than failing
    /// it. Without that, every guarded rule would reject every action it
    /// does not apply to.
    @Test("A rule whose guard is unmet is skipped, not failed")
    func unmetGuardSkipsTheRule() throws {
        let (state, playerA, _, _, _) = Self.twoBattlefieldState()
        let ruleBase = try Self.decode("""
        {
          "version": "test",
          "rules": [
            {
              "id": "guarded",
              "appliesTo": ["pass"],
              "when": { "equals": ["turnState", "showdownOpen"] },
              "require": { "always": false },
              "failure": { "kind": "notImplemented" }
            }
          ],
          "moveDestinations": []
        }
        """)
        // The board is in neutralOpen, so the guard doesn't hold.
        #expect(LegalityValidator.validate(.pass, in: state, proposedBy: playerA, using: ruleBase).isSuccess)
    }

    @Test("A condition with two operators is rejected rather than silently read as one")
    func ambiguousConditionFailsToDecode() {
        #expect(throws: (any Error).self) {
            try Self.decode("""
            {
              "version": "test",
              "rules": [
                {
                  "id": "ambiguous",
                  "appliesTo": ["pass"],
                  "require": { "isTrue": "hasPriority", "always": false },
                  "failure": { "kind": "notImplemented" }
                }
              ],
              "moveDestinations": []
            }
            """)
        }
    }

    // MARK: - Helpers

    private static func decode(_ json: String) throws -> RuleBase {
        try JSONDecoder().decode(RuleBase.self, from: Data(json.utf8))
    }

    /// Just the rules a Standard Move needs, so a test about 140.4's table
    /// doesn't have to restate the play and cost rules it never reaches.
    private static func moveRuleBase(destinations: String) throws -> RuleBase {
        try decode("""
        {
          "version": "test",
          "rules": [
            {
              "id": "140.1.a",
              "appliesTo": ["standardMove"],
              "require": { "equals": ["phase", "action"] },
              "failure": { "kind": "notActionPhase" }
            },
            {
              "id": "512.1.a",
              "appliesTo": ["standardMove"],
              "require": { "isTrue": "hasPriority" },
              "failure": { "kind": "notPlayersPriority" }
            },
            {
              "id": "140.4",
              "appliesTo": ["standardMove"],
              "require": { "not": { "equals": ["moveViolation", "illegalDestination"] } },
              "failure": { "kind": "illegalMoveDestination" }
            }
          ],
          "moveDestinations": \(destinations)
        }
        """)
    }

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
}
