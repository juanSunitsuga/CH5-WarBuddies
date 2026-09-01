import Foundation

/// Every accepted action, in order, with everything needed to re-derive
/// `GameState` from the start of the game.
///
/// The engine currently *accumulates* state: `GameActionApplier` mutates it
/// in place and what came before is gone. That costs three things this log
/// is meant to buy back.
///
/// - **Resume.** Stopping the pipeline throws the session away. A log is a
///   durable record the next session can fold back into a board.
/// - **Correction.** When the camera misreads a card there is no way to say
///   "that was a Fury rune" and have the consequences follow. With a log,
///   correcting is amending one entry and replaying — see `correcting(_:)`.
/// - **One source of truth.** `GameState` becomes *derived* rather than
///   independently maintained, so "what does the engine think" has one
///   answer that can always be recomputed rather than only observed.
///
/// **This is not a memory concern.** Worth saying plainly, because the
/// question that prompted it came from a leak: entries are recorded per
/// *accepted action*, not per camera poll. A long session produces hundreds,
/// not the tens of thousands a per-frame path would. Growth here tracks how
/// much has been played rather than how long the app has been open, which is
/// exactly the distinction that separates a record from a leak.
public struct GameEventLog: Sendable {

    /// One accepted action, and everything that mutated `GameState` because
    /// of it.
    ///
    /// `abilityInstructions` is stored rather than re-derived on replay, and
    /// that is deliberate: they come from the NLP layer's card corpus, so
    /// re-parsing at replay time would let a change to the card database
    /// silently rewrite the history of a game that has already been played.
    /// A log that can be re-interpreted isn't a record of what happened.
    public struct Entry: Sendable, Identifiable {
        /// Monotonic, and stable across corrections — an amended entry keeps
        /// its number so a caller holding one still means the same moment.
        public let id: Int
        public let action: GameAction
        public let proposer: PlayerID
        public let abilityInstructions: [EffectInstruction]
        /// What the camera saw, if this came from the table. Kept for
        /// correction and audit; replay never reads it, since re-translating
        /// an observation is the re-interpretation this design avoids.
        public let observation: ObservedTableEvent?

        public init(
            id: Int,
            action: GameAction,
            proposer: PlayerID,
            abilityInstructions: [EffectInstruction] = [],
            observation: ObservedTableEvent? = nil
        ) {
            self.id = id
            self.action = action
            self.proposer = proposer
            self.abilityInstructions = abilityInstructions
            self.observation = observation
        }
    }

    /// The board before anything was played — deck, opening hand, seats.
    /// Replay folds the entries onto this, so it has to be the *whole*
    /// starting position rather than an empty state.
    public let initialState: GameState
    public private(set) var entries: [Entry] = []

    private var nextID = 1

    public init(initialState: GameState) {
        self.initialState = initialState
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    // MARK: - Recording

    @discardableResult
    public mutating func record(
        action: GameAction,
        proposer: PlayerID,
        abilityInstructions: [EffectInstruction] = [],
        observation: ObservedTableEvent? = nil
    ) -> Entry {
        let entry = Entry(
            id: nextID,
            action: action,
            proposer: proposer,
            abilityInstructions: abilityInstructions,
            observation: observation
        )
        nextID += 1
        entries.append(entry)
        return entry
    }

    // MARK: - Replay

    /// The board as of `id`, or as of everything when `id` is `nil`.
    ///
    /// Mirrors `GameEngine.process`'s accepted path exactly — apply, then
    /// Cleanup, then clear the ability summaries the way a live turn
    /// consumes them. That correspondence is the whole contract: if the two
    /// ever diverge, a replayed game stops being the game that was played,
    /// and `GameEventLogTests` exists to catch it.
    ///
    /// 518–526: Cleanup runs after *each* entry rather than once at the end.
    /// Batching it would let a board sit in a state the rules never allow —
    /// a dead unit still present while the next action resolves — which is
    /// precisely the drift CLAUDE.md point 3 warns about.
    public func state(through id: Int? = nil) -> GameState {
        var state = initialState
        for entry in entries {
            if let id, entry.id > id { break }
            _ = GameActionApplier.apply(
                entry.action,
                to: &state,
                proposedBy: entry.proposer,
                abilityInstructions: entry.abilityInstructions
            )
            state = Cleanup.run(state)
            // Consumed each turn by the live path; a replay that let them
            // accumulate would end holding every ability summary of the game.
            state.abilityOutcomeSummaries = []
        }
        return state
    }

    // MARK: - Correction

    /// A log with one entry's action replaced — "that wasn't a Play, it was
    /// a Move" — leaving everything after it in place to be re-derived.
    ///
    /// Returns a new log rather than mutating, so a caller can compute the
    /// corrected board and show it *before* committing to it. A correction
    /// that silently rewrote history the moment it was proposed would be
    /// hard to offer safely in a UI.
    ///
    /// Unknown ids return the log unchanged rather than trapping: the id
    /// most likely came from a stale view of the log, which is a UI race
    /// rather than a programming error.
    public func correcting(
        _ id: Int,
        action: GameAction,
        abilityInstructions: [EffectInstruction]? = nil
    ) -> GameEventLog {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return self }

        var corrected = self
        let old = entries[index]
        corrected.entries[index] = Entry(
            id: old.id,
            action: action,
            proposer: old.proposer,
            // Keeping the old instructions would attach one card's ability to
            // another card's play, so the default is none rather than stale.
            abilityInstructions: abilityInstructions ?? [],
            observation: old.observation
        )
        return corrected
    }

    /// A log with one entry removed — the camera saw something that never
    /// happened.
    ///
    /// Ids are *not* renumbered. Gaps are the honest record: entry 7 having
    /// been struck out is a fact about the game, and shuffling 8 down into
    /// its place would silently invalidate every id anyone still holds.
    public func removing(_ id: Int) -> GameEventLog {
        var corrected = self
        corrected.entries.removeAll { $0.id == id }
        return corrected
    }
}
