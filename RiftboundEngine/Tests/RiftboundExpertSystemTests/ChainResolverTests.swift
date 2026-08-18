import Testing
@testable import RiftboundExpertSystem

/// Rule 532–544: the Chain's state-transition functions. `Chain` itself is
/// tested indirectly through these — see that type's own doc comment on
/// why the logic lives here instead.
struct ChainResolverTests {

    private static func spellItem(owner: PlayerID) -> ChainItem {
        .spell(MainDeckCard(definitionID: CardDefID(rawValue: "spell"), owner: owner, name: "Test Spell", type: .spell), targets: [])
    }

    // MARK: - push (534)

    @Test("push opens a Chain from Neutral Open, with the whole turnOrder Relevant")
    func pushOpensChainFromNeutralOpen() {
        var (state, playerA, playerB, _) = TestFixtures.makeTwoPlayerState()

        ChainResolver.push(Self.spellItem(owner: playerA), proposedBy: playerA, to: &state)

        guard case .neutralClosed(let chain) = state.turnState else {
            Issue.record("Expected Neutral Closed, got \(state.turnState)")
            return
        }
        #expect(chain.items.count == 1)
        #expect(chain.activePlayer == playerA)
        #expect(chain.relevantPlayers == [playerA, playerB])
        #expect(chain.passedPlayers.isEmpty)
    }

    @Test("push adds to an existing Chain rather than opening a second one (534.1)")
    func pushAddsToExistingChain() {
        var (state, playerA, playerB, _) = TestFixtures.makeTwoPlayerState()
        ChainResolver.push(Self.spellItem(owner: playerA), proposedBy: playerA, to: &state)

        // playerB responds — passedPlayers would be non-empty here in a
        // fuller scenario; simulate that to confirm push resets it (543.4).
        ChainResolver.push(Self.spellItem(owner: playerB), proposedBy: playerB, to: &state)

        guard case .neutralClosed(let chain) = state.turnState else {
            Issue.record("Expected still Neutral Closed, got \(state.turnState)")
            return
        }
        #expect(chain.items.count == 2)
        #expect(chain.activePlayer == playerB)
        #expect(chain.passedPlayers.isEmpty)
    }

    /// 550: a Chain opened inside a Showdown is scoped to *that Showdown's*
    /// Relevant Players, not the whole `turnOrder` — distinguishable only
    /// with a 3rd player who isn't Relevant to this particular Showdown.
    @Test("push inside a Showdown scopes the new Chain to the Showdown's own Relevant Players")
    func pushInsideShowdownScopesToShowdownRelevantPlayers() {
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
        state.turnState = .showdownOpen(Showdown(
            origin: .combat(attacker: playerA, defender: playerB, battlefield: battlefield.id),
            focusPlayer: playerA,
            relevantPlayers: [playerA, playerB]  // playerC is not Relevant to this Combat
        ))

        ChainResolver.push(Self.spellItem(owner: playerA), proposedBy: playerA, to: &state)

        guard case .showdownClosed(_, let chain) = state.turnState else {
            Issue.record("Expected Showdown Closed, got \(state.turnState)")
            return
        }
        #expect(chain.relevantPlayers == [playerA, playerB])
    }

    // MARK: - pass (540.4/543)

    @Test("pass from an Open state (no Chain) is a no-op")
    func passWithNoChainIsNoOp() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()

        let resolved = ChainResolver.pass(by: playerA, in: &state)

        #expect(resolved.isRecordedOnly)
        #expect(state.turnState.isClosed == false)
    }

    @Test("pass from only some Relevant Players doesn't resolve yet")
    func partialPassDoesNotResolve() {
        var (state, playerA, playerB, _) = TestFixtures.makeTwoPlayerState()
        ChainResolver.push(Self.spellItem(owner: playerA), proposedBy: playerA, to: &state)

        let resolved = ChainResolver.pass(by: playerB, in: &state)

        #expect(resolved.isRecordedOnly)
        guard case .neutralClosed(let chain) = state.turnState else {
            Issue.record("Expected still Neutral Closed, got \(state.turnState)")
            return
        }
        #expect(chain.items.count == 1)
        #expect(chain.passedPlayers == [playerB])
    }

    @Test("pass from every Relevant Player resolves the top item and closes an empty Chain")
    func fullPassResolvesAndClosesChain() {
        var (state, playerA, playerB, _) = TestFixtures.makeTwoPlayerState()
        ChainResolver.push(Self.spellItem(owner: playerA), proposedBy: playerA, to: &state)

        #expect(ChainResolver.pass(by: playerB, in: &state).isRecordedOnly)
        let resolved = ChainResolver.pass(by: playerA, in: &state)

        #expect(resolved.resolvedItem != nil)
        guard case .neutralOpen = state.turnState else {
            Issue.record("Expected the Chain to have closed back to Neutral Open, got \(state.turnState)")
            return
        }
    }

    /// Same full-pass resolution, but a second item is still underneath —
    /// the Chain stays Closed (543.4: fresh pass-around for the new top),
    /// with `passedPlayers` reset rather than carrying over.
    @Test("Resolving one item of a multi-item Chain leaves it open with passes reset")
    func resolvingOneOfTwoItemsLeavesChainOpenWithResetPasses() {
        var (state, playerA, playerB, _) = TestFixtures.makeTwoPlayerState()
        ChainResolver.push(Self.spellItem(owner: playerA), proposedBy: playerA, to: &state)
        ChainResolver.push(Self.spellItem(owner: playerB), proposedBy: playerB, to: &state)

        // Both pass on the top (playerB's) item.
        #expect(ChainResolver.pass(by: playerA, in: &state).isRecordedOnly)
        let resolved = ChainResolver.pass(by: playerB, in: &state)

        #expect(resolved.resolvedItem != nil)
        guard case .neutralClosed(let chain) = state.turnState else {
            Issue.record("Expected still Neutral Closed with one item left, got \(state.turnState)")
            return
        }
        #expect(chain.items.count == 1)
        #expect(chain.passedPlayers.isEmpty)
    }

    /// Mirrors `fullPassResolvesAndClosesChain`, but nested in a Showdown —
    /// closing reverts to Showdown Open, not all the way to Neutral Open.
    @Test("Resolving the last item of a Showdown's Chain reverts to Showdown Open")
    func resolvingLastItemInShowdownRevertsToShowdownOpen() {
        var (state, playerA, playerB, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let showdown = Showdown(
            origin: .standalone(battlefield: battlefieldID),
            focusPlayer: playerA,
            relevantPlayers: [playerA, playerB]
        )
        state.turnState = .showdownOpen(showdown)
        ChainResolver.push(Self.spellItem(owner: playerA), proposedBy: playerA, to: &state)

        #expect(ChainResolver.pass(by: playerB, in: &state).isRecordedOnly)
        _ = ChainResolver.pass(by: playerA, in: &state)

        guard case .showdownOpen = state.turnState else {
            Issue.record("Expected the Chain to have closed back to Showdown Open, got \(state.turnState)")
            return
        }
    }
}
