import Testing
@testable import RiftboundExpertSystem

/// Rules 153–160, 594, 606: where Energy and Power actually come from.
///
/// A Rune's life cycle has three distinct physical acts, and the engine
/// used to collapse them into one:
///
///   1. **Channel** (606.1) — Rune Deck → Rune Area, on the board, Ready.
///      Produces nothing.
///   2. **Exhaust** (157.2.a, `[T]: Add [1]`) — turn it sideways. *This* is
///      what produces 1 Energy.
///   3. **Recycle** (157.2.b/594.1.b) — Rune Area → bottom of Rune Deck.
///      Produces 1 Power of that Rune's Domain, and the Rune leaves the
///      board.
///
/// Collapsing 1 and 2 into "channel adds energy" is the bug these tests
/// pin: it granted Energy for Runes that had only been placed, and left
/// the Rune Area empty for the camera to look at.
struct RuneEconomyTests {

    // MARK: - Channel (606)

    /// 606.1: Channeling puts Runes **on the board**. 157.2.a: Energy comes
    /// from Exhausting them, so a freshly Channeled Ready Rune is worth 0.
    @Test("Channeling moves runes from deck to board and adds no energy")
    func channelPutsRunesOnBoardWithoutEnergy() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        TestFixtures.stockRuneDeck([.fury, .calm, .mind], for: playerA, in: &state)
        state.authorize(.channel(count: 2, exhausted: false), for: playerA)

        GameActionApplier.apply(.channel(count: 2, exhausted: false), to: &state, proposedBy: playerA)

        #expect(state.runes.count == 2)
        #expect(state.runes.values.allSatisfy { !$0.isExhausted })
        #expect(state.zones[playerA]?.runeDeck.count == 1)
        #expect(state.zones[playerA]?.runePool.energy == 0)
        #expect(state.totalRunesChanneled[playerA] == 2)
    }

    /// 606.2: "Channel 1 rune exhausted." An effect may specify the stance,
    /// and an Exhausted arrival has already spent its `[T]` — so it still
    /// adds no Energy on its own.
    @Test("Channeling exhausted puts the rune down already turned")
    func channelExhaustedRespectsTheStance() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        TestFixtures.stockRuneDeck([.fury], for: playerA, in: &state)
        state.authorize(.channel(count: 1, exhausted: true), for: playerA)

        GameActionApplier.apply(.channel(count: 1, exhausted: true), to: &state, proposedBy: playerA)

        #expect(state.runes.values.first?.isExhausted == true)
        #expect(state.zones[playerA]?.runePool.energy == 0)
    }

    /// 515.3.b.1: "If there are fewer than 2 runes in the Rune Deck, they
    /// channel as many as possible" — a short deck is not a failure.
    @Test("Channeling more runes than the deck holds channels as many as possible")
    func channelClampsToDeckSize() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        TestFixtures.stockRuneDeck([.fury], for: playerA, in: &state)
        state.authorize(.channel(count: 2, exhausted: false), for: playerA)

        GameActionApplier.apply(.channel(count: 2, exhausted: false), to: &state, proposedBy: playerA)

        #expect(state.runes.count == 1)
        #expect(state.zones[playerA]?.runeDeck.isEmpty == true)
    }

    // MARK: - Exhaust (157.2.a)

    @Test("Exhausting a ready rune adds one energy to its controller's pool")
    func exhaustingARuneAddsEnergy() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        let runeIDs = TestFixtures.channelRunes([.fury, .calm], for: playerA, into: &state)
        state.authorize(.exhaust(objects: runeIDs), for: playerA)

        GameActionApplier.apply(.exhaust(objects: runeIDs), to: &state, proposedBy: playerA)

        #expect(state.zones[playerA]?.runePool.energy == 2)
        #expect(state.runes.values.allSatisfy { $0.isExhausted })
    }

    /// The ability's cost is turning the Rune. A Rune already sideways has
    /// nothing left to pay with, so exhausting it again produces nothing —
    /// this is what stops one Rune funding a whole turn.
    @Test("Exhausting an already-exhausted rune produces no further energy")
    func exhaustingAnExhaustedRuneProducesNothing() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        let runeIDs = TestFixtures.channelRunes([.fury], for: playerA, exhausted: true, into: &state)
        state.authorize(.exhaust(objects: runeIDs), for: playerA)

        GameActionApplier.apply(.exhaust(objects: runeIDs), to: &state, proposedBy: playerA)

        #expect(state.zones[playerA]?.runePool.energy == 0)
    }

    /// 593: Ready is the inverse of Exhaust for *stance*, deliberately not
    /// for Energy — Energy already added is spent or lost to 160's
    /// emptying, never clawed back because the Rune stood up again.
    @Test("Readying a rune does not take back the energy it produced")
    func readyingARuneDoesNotRefundEnergy() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        let runeIDs = TestFixtures.channelRunes([.fury], for: playerA, into: &state)
        state.authorize(.exhaust(objects: runeIDs), for: playerA)
        GameActionApplier.apply(.exhaust(objects: runeIDs), to: &state, proposedBy: playerA)

        state.authorize(.ready(objects: runeIDs), for: playerA)
        GameActionApplier.apply(.ready(objects: runeIDs), to: &state, proposedBy: playerA)

        #expect(state.runes[runeIDs[0]]?.isExhausted == false)
        #expect(state.zones[playerA]?.runePool.energy == 1)
    }

    // MARK: - Recycle (157.2.b / 594)

    /// 594.1.b + 157.2.b.1: the Rune leaves the board, goes to the **bottom**
    /// of the Rune Deck, and adds Power of its own Domain.
    @Test("Recycling a rune returns the card to the bottom of the rune deck and adds matching power")
    func recyclingReturnsTheCardAndAddsPower() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        TestFixtures.stockRuneDeck([.mind], for: playerA, in: &state)
        TestFixtures.channelRunes([.chaos], for: playerA, into: &state)
        state.authorize(.recycleRune(domain: .chaos), for: playerA)

        GameActionApplier.apply(.recycleRune(domain: .chaos), to: &state, proposedBy: playerA)

        #expect(state.runes.isEmpty)                                       // left the board
        #expect(state.zones[playerA]?.runeDeck.count == 2)
        #expect(state.zones[playerA]?.runeDeck.last?.domain == .chaos)     // 594.1: the bottom
        #expect(state.zones[playerA]?.runePool.power == [.domain(.chaos)]) // 157.2.b.1
        #expect(state.totalRunesRecycled[playerA] == 1)
    }

    /// 594.3: "When Recycling is listed as a Cost, the action must be able
    /// to be completed for the cost to be paid." No Rune of that Domain in
    /// the Rune Area means no Power — previously this succeeded and minted
    /// Power from nothing, which let a player pay any Domain cost at will.
    @Test("Recycling a domain the player has no rune of is rejected")
    func recyclingWithoutAMatchingRuneIsRejected() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        TestFixtures.channelRunes([.fury], for: playerA, into: &state)

        let result = LegalityValidator.validate(.recycleRune(domain: .chaos), in: state, proposedBy: playerA)

        #expect(result.failureValue == .noRuneOfDomainAvailable(.chaos))
    }

    // MARK: - Rune abilities are discretionary (157.2 / 577)

    /// 157.2's two abilities are Activated Abilities (577.2 — they have the
    /// `:`), so a player may use them at will with Priority. Gating them on
    /// a 589.2 authorization, as this engine used to, made the whole rune
    /// economy unreachable from the camera: every observed rune turn came
    /// back "nothing has called for that action yet," so no Energy could
    /// ever legally exist and no card could ever be paid for.
    @Test("Exhausting your own runes needs no authorization, only priority")
    func exhaustingOwnRunesIsDiscretionary() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        let runeIDs = TestFixtures.channelRunes([.fury], for: playerA, into: &state)

        // Deliberately no `authorize` call.
        #expect(LegalityValidator.validate(.exhaust(objects: runeIDs), in: state, proposedBy: playerA).isSuccess)
    }

    @Test("Recycling your own rune needs no authorization, only priority")
    func recyclingOwnRuneIsDiscretionary() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        TestFixtures.channelRunes([.fury], for: playerA, into: &state)

        #expect(LegalityValidator.validate(.recycleRune(domain: .fury), in: state, proposedBy: playerA).isSuccess)
    }

    /// The carve-out is exactly "your own Runes." Exhausting anything else
    /// stays a Limited Action (592) — an opponent's Unit does not exhaust
    /// because you decided it should.
    @Test("Exhausting a unit is still a Limited Action needing authorization")
    func exhaustingAUnitStillNeedsAuthorization() {
        var (state, playerA, _, battlefieldID) = TestFixtures.makeTwoPlayerState()
        let unit = TestFixtures.makeUnit(owner: playerA, location: .battlefield(battlefieldID), isExhausted: false)
        state.units[unit.id] = unit

        let result = LegalityValidator.validate(.exhaust(objects: [unit.id]), in: state, proposedBy: playerA)

        #expect(result.failureValue == .limitedActionNotAuthorized(.exhaust(objects: [unit.id])))
    }

    @Test("Exhausting an opponent's rune is not covered by the carve-out")
    func exhaustingOpponentsRuneIsNotDiscretionary() {
        var (state, playerA, playerB, _) = TestFixtures.makeTwoPlayerState()
        let opponentRunes = TestFixtures.channelRunes([.fury], for: playerB, into: &state)

        let result = LegalityValidator.validate(.exhaust(objects: opponentRunes), in: state, proposedBy: playerA)

        #expect(!result.isSuccess)
    }

    /// 606.3.a: "Players may only channel runes when Game Effects direct
    /// them to do so." Channel stays Limited — unlike the two abilities
    /// above, it has no `:` cost the player pays, and letting it be
    /// discretionary would let a player refill their board at will.
    @Test("Channeling is still a Limited Action needing authorization")
    func channelingStillNeedsAuthorization() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        TestFixtures.stockRuneDeck([.fury], for: playerA, in: &state)

        let result = LegalityValidator.validate(.channel(count: 1, exhausted: false), in: state, proposedBy: playerA)

        #expect(result.failureValue == .limitedActionNotAuthorized(.channel(count: 1, exhausted: false)))
    }

    /// 560–561: costs are paid during the process of playing a card, which
    /// includes a Reaction played into an existing Chain. Restricting rune
    /// payment to a Neutral Open state (589.1.a's letter) would make every
    /// Reaction with a cost unplayable.
    @Test("Runes can still be spent while a chain is resolving")
    func runesSpendableDuringAChain() {
        var (state, playerA, playerB, _) = TestFixtures.makeTwoPlayerState()
        let runeIDs = TestFixtures.channelRunes([.fury], for: playerA, into: &state)
        let spell = MainDeckCard(
            definitionID: CardDefID(rawValue: "spell"), owner: playerA,
            name: "On The Chain", type: .spell
        )
        state.turnState = .neutralClosed(Chain(
            firstItem: .spell(spell, targets: []),
            activePlayer: playerA,
            relevantPlayers: [playerA, playerB]
        ))

        #expect(LegalityValidator.validate(.exhaust(objects: runeIDs), in: state, proposedBy: playerA).isSuccess)
    }

    /// An Exhausted Rune is as Recyclable as a Ready one — the cost is
    /// returning the card, not turning it. Where both exist the spent one
    /// goes first, since it has already produced its Energy.
    @Test("Recycling prefers an already-exhausted rune over a ready one")
    func recyclingPrefersTheSpentRune() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        let ready = TestFixtures.channelRunes([.fury], for: playerA, into: &state)[0]
        TestFixtures.channelRunes([.fury], for: playerA, exhausted: true, into: &state)
        state.authorize(.recycleRune(domain: .fury), for: playerA)

        GameActionApplier.apply(.recycleRune(domain: .fury), to: &state, proposedBy: playerA)

        #expect(state.runes.count == 1)
        #expect(state.runes[ready] != nil)   // the Ready one survived
    }

    // MARK: - The full cycle

    /// End to end, the way a turn actually spends: channel two Ready Runes,
    /// exhaust one for Energy, recycle the other for Power, and confirm the
    /// Rune Area holds what the camera should see — one fewer Rune than was
    /// channeled, because Recycling took one back to the deck.
    @Test("Channel, exhaust for energy, recycle for power — and the rune area matches")
    func fullRuneCycleLeavesTheAreaConsistent() {
        var (state, playerA, _, _) = TestFixtures.makeTwoPlayerState()
        TestFixtures.stockRuneDeck([.fury, .chaos], for: playerA, in: &state)

        state.authorize(.channel(count: 2, exhausted: false), for: playerA)
        GameActionApplier.apply(.channel(count: 2, exhausted: false), to: &state, proposedBy: playerA)

        guard let fury = state.runes.values.first(where: { $0.domain == .fury }) else {
            Issue.record("Expected a Fury rune in the rune area after channeling")
            return
        }
        state.authorize(.exhaust(objects: [fury.id]), for: playerA)
        GameActionApplier.apply(.exhaust(objects: [fury.id]), to: &state, proposedBy: playerA)

        state.authorize(.recycleRune(domain: .chaos), for: playerA)
        GameActionApplier.apply(.recycleRune(domain: .chaos), to: &state, proposedBy: playerA)

        #expect(state.zones[playerA]?.runePool.energy == 1)
        #expect(state.zones[playerA]?.runePool.power == [.domain(.chaos)])

        // What should physically be in the Rune Area: channeled minus
        // recycled. This is the figure the vision layer reconciles against,
        // and it now has a real board collection to check itself against
        // rather than only a pair of counters.
        let expectedVisible = state.totalRunesChanneled[playerA, default: 0]
            - state.totalRunesRecycled[playerA, default: 0]
        #expect(state.runes.values.filter { $0.controller == playerA }.count == expectedVisible)
        #expect(expectedVisible == 1)
    }
}
