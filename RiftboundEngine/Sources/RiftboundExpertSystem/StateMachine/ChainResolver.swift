/// Rule 532–544: the Chain's state-transition functions — kept separate
/// from `Chain` itself (a plain data type, see its own doc comment) so
/// each transition is unit-testable against a constructed `Chain`/
/// `GameState` without needing the full live pipeline. Named and referenced
/// from `Chain.swift` and `GameStateStore.swift` before this file existed;
/// this is that piece, per docs/architecture.md item 4 ("Drive the Chain
/// for real, so Reactions resolve in rules order").
///
/// Both functions take `GameState` `inout`, matching `Cleanup.run`'s and
/// `GameActionApplier.apply`'s shape — callers run these only through
/// `GameStateStore.mutate` (CLAUDE.md point 2), same as everything else
/// that touches `GameState`.
public enum ChainResolver {
    /// Rule 534.1/534.2: opens a new Chain if none exists yet for the
    /// current `TurnState`, or adds `item` to the existing one — a
    /// Chain-adding action never spawns a second Chain. Transitions
    /// `state.turnState` Open → Closed (or keeps it Closed, with the new
    /// item on top).
    ///
    ///   - 550/551: while a Showdown is in progress, a new Chain nests
    ///     inside it (`.showdownOpen` → `.showdownClosed`) rather than
    ///     opening independently, and its Relevant Players default to the
    ///     Showdown's own `relevantPlayers` (550), not the whole
    ///     `turnOrder` — a Showdown Chain is scoped to who's Relevant to
    ///     *that* Showdown, same restriction 550.2 already puts on the
    ///     Showdown itself.
    ///   - 540.4.b/543.4: adding an item resets `passedPlayers` — a fresh
    ///     full pass-around among Relevant Players is required before the
    ///     new top item can resolve, regardless of who'd already passed
    ///     on the previous top item.
    ///   - `activePlayer` becomes whoever just added the item, matching
    ///     512.2.c (Priority while Closed belongs to the Chain's
    ///     `activePlayer`) — the player who just acted doesn't
    ///     automatically get to act again next; this only reflects "who
    ///     most recently added something," not a claim about who's next.
    public static func push(_ item: ChainItem, proposedBy player: PlayerID, to state: inout GameState) {
        switch state.turnState {
        case .neutralOpen:
            state.turnState = .neutralClosed(Chain(firstItem: item, activePlayer: player, relevantPlayers: Set(state.turnOrder)))

        case .neutralClosed(var chain):
            chain.items.append(item)
            chain.activePlayer = player
            chain.passedPlayers = []
            state.turnState = .neutralClosed(chain)

        case .showdownOpen(let showdown):
            state.turnState = .showdownClosed(showdown, Chain(firstItem: item, activePlayer: player, relevantPlayers: showdown.relevantPlayers))

        case .showdownClosed(let showdown, var chain):
            chain.items.append(item)
            chain.activePlayer = player
            chain.passedPlayers = []
            state.turnState = .showdownClosed(showdown, chain)
        }
    }

    /// Rule 540.4/553.4: records a Pass from `player`. If every Relevant
    /// Player has now passed since the last item was added or resolved,
    /// resolves the top item (543.1: the last one added) and, if that was
    /// the Chain's only item, closes it entirely — reverting
    /// `state.turnState` back to Open (Neutral or Showdown, matching
    /// whichever this Chain was nested inside). Returns the resolved
    /// item, if the pass-around just completed one, so the caller can
    /// apply its effect — see `GameActionApplier`'s handling of `.pass`
    /// for what "resolve" currently means in practice (563.2.b: nothing
    /// executes Ability effects yet, architecture.md item 7).
    ///
    /// 543.4: passes never carry over to the next top item — resolving
    /// clears `passedPlayers`, same as `push` does, so whatever's now on
    /// top needs its own fresh full pass-around.
    ///
    /// No-op (`nil`) when there's no Chain to pass on at all — `.pass` is
    /// still a legal Discretionary Action in `.neutralOpen`/`.showdownOpen`
    /// (589.1: any player with Priority may decline to act), it just has
    /// nothing here to resolve.
    @discardableResult
    public static func pass(by player: PlayerID, in state: inout GameState) -> ChainItem? {
        switch state.turnState {
        case .neutralOpen, .showdownOpen:
            return nil

        case .neutralClosed(var chain):
            chain.passedPlayers.insert(player)
            guard chain.relevantPlayers.isSubset(of: chain.passedPlayers) else {
                state.turnState = .neutralClosed(chain)
                return nil
            }
            let resolved = chain.items.popLast()
            chain.passedPlayers = []
            state.turnState = chain.items.isEmpty ? .neutralOpen : .neutralClosed(chain)
            return resolved

        case .showdownClosed(let showdown, var chain):
            chain.passedPlayers.insert(player)
            guard chain.relevantPlayers.isSubset(of: chain.passedPlayers) else {
                state.turnState = .showdownClosed(showdown, chain)
                return nil
            }
            let resolved = chain.items.popLast()
            chain.passedPlayers = []
            state.turnState = chain.items.isEmpty ? .showdownOpen(showdown) : .showdownClosed(showdown, chain)
            return resolved
        }
    }
}
