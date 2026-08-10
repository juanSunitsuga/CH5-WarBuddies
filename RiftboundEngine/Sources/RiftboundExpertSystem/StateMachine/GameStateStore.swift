/// Owns the single live `GameState` and serializes all mutation through
/// actor isolation (CLAUDE.md point 2). This is deliberately the *only*
/// place `GameState` is mutated in the whole engine — every other type
/// (Cleanup, ChainResolver, effect executors, the Legality Validator)
/// should be pure functions taking and returning `GameState` values, called
/// from here.
///
/// Expected callers, once built out:
///   - `LegalityValidator` (reads a snapshot via `currentState`, doesn't mutate)
///   - `GameAction` application (mutates via `apply`)
///   - OCR/tracking event ingestion (proposes `GameAction`s, doesn't mutate directly)
///   - NLP-driven effect resolution (proposes `EffectInstruction`s → chain items)
public actor GameStateStore {
    private var state: GameState

    public init(initialState: GameState) {
        self.state = initialState
    }

    /// Read-only snapshot for validators/UI. Safe to call frequently; the
    /// returned value is independent of subsequent mutation (value type).
    public var currentState: GameState { state }

    /// The single mutation entry point. Callers pass a pure transform;
    /// the store guarantees it runs atomically with respect to any other
    /// transform. Cleanup (rule 518–526) should be invoked as part of the
    /// transform itself wherever the rules require it — see CLAUDE.md
    /// point 3 — not bolted on afterward here, since some transforms
    /// (e.g. mid-Chain-resolution steps) need Cleanup at a specific point
    /// within their own logic, not just at the end.
    @discardableResult
    public func mutate(_ transform: (inout GameState) throws -> Void) rethrows -> GameState {
        try transform(&state)
        return state
    }
}
