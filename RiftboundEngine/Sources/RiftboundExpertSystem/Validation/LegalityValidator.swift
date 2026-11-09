/// Given a `GameState` snapshot and a proposed `GameAction`, decides
/// whether it's currently legal. This is what the vision/event-inference
/// layer calls with candidate actions derived from observed table deltas —
/// see docs/architecture.md section 5 for the "untrusted proposer" framing.
///
/// **The rules themselves are not in this file.** They live in
/// `Resources/RuleBase.json`, are modeled by `RuleBase`, and are applied by
/// `RuleEngine` against the facts `RuleFacts` reads off the board. This type
/// is now the boundary: it names the failures the rest of the engine
/// switches on, and forwards the question to the expert system.
///
/// That split is what makes the usual claim about this architecture true of
/// this app. Every branch below used to be hand-written Swift, so changing a
/// timing window or a cost check meant editing and recompiling the
/// validator; the knowledge base was the code. A rule's phase, keyword
/// requirement, cost comparison, precedence and rule number are now data,
/// and editing them needs no Swift change.
///
/// `Failure` stays a Swift enum with typed payloads on purpose. It is the
/// vocabulary the engine, the app's instruction log and the thesis's
/// measurement tables all agree on — a rejection has to be a value callers
/// can switch over exhaustively, not a string from a file.
public enum LegalityValidator {
    public enum Failure: Error, Equatable {
        case notPlayersPriority
        case unitAlreadyExhausted(ObjectID)
        case unitNotFound(ObjectID)
        case destinationOccupiedByTwoOtherControllers(BattlefieldID)
        case moveOriginsMismatch  // 140.3.b requires same Destination, not same Origin — but all named units must actually exist and be movable
        /// Rule 555/558: the proposed card isn't in the proposing player's
        /// Hand — either it's already been played, or the observed event
        /// misidentified which card moved.
        case cardNotInHand(ObjectID)
        /// Rule 559.2: a Unit must be given a real board Location to enter
        /// (`.none` is only valid for Spells/abilities, which have no board
        /// form).
        case invalidPlayDestination(PlayDestination)
        /// Rule 560–561: the player's Rune Pool doesn't have enough Energy
        /// to pay the card's cost.
        case insufficientEnergy(required: Int, available: Int)
        /// Rule 560–561/130.3: the player's Rune Pool doesn't have enough
        /// Power matching the card's `eligibleDomains` — either too few
        /// Runes of any eligible Domain were Recycled, or the wrong
        /// Domain(s) were (e.g. Recycling 2 Fury when the card needs 2
        /// Chaos; Recycling 1 Fury + 1 Chaos when it needs 2 of a single
        /// Domain). `available` counts only pool entries that actually
        /// match — non-matching entries in the pool don't count toward it
        /// even though they're real, spendable Power for some other card.
        case insufficientPower(required: Int, available: Int)
        /// Rule 130.2: how many Runes were physically Exhausted at the
        /// moment this Play was observed doesn't match the card's Energy
        /// cost — Energy is paid by Exhausting Runes, so playing a card
        /// costing `required` should correspond to exactly that many
        /// Runes going from Ready to Exhausted. Only checked when the
        /// proposer actually supplied `GameAction.play`'s
        /// `observedExhaustedRuneCount` — see that field's doc comment.
        case exhaustedRuneCountMismatch(required: Int, observed: Int)
        /// Rule 509.1.a: the turn is Closed (`.neutralClosed`/`.showdownClosed`
        /// — a Chain currently exists) and this card carries no
        /// `Keyword.reaction` (725) — only Reaction-tagged cards/abilities
        /// may respond to an existing window. (Whether `player` is even
        /// allowed to act right now at all is a separate check —
        /// `Failure.notPlayersPriority`, from `TurnState.playerWithPriority`.)
        case reactionRequired
        /// Rule 508.1.a: a Showdown is in progress with no Chain yet
        /// (`.showdownOpen`) and this card carries neither `Keyword.action`
        /// (718) nor `Keyword.reaction` (725) — only Action- or
        /// Reaction-tagged cards/abilities may open the Showdown's Chain.
        case actionOrReactionRequired
        /// Rule 589.2: this Limited Action was proposed without any rule or
        /// effect having called for it — nothing in
        /// `GameState.pendingLimitedActions` matches. The classic case:
        /// OCR observed a player draw a card whose "when I enter play, draw
        /// a card" trigger hasn't actually resolved yet.
        case limitedActionNotAuthorized(GameAction)
        /// Rule 516.1/140.1.a: this action belongs to the Action Phase, and
        /// the turn hasn't reached it (or has left it). Everything before
        /// the Action Phase — Awaken, Beginning, Channel, Draw — is fixed
        /// and automatic (515), so a player physically playing a card
        /// during it is acting out of turn structure, not merely early.
        case notActionPhase(Phase)
        /// Rule 140.4: a Standard Move's Destination is restricted to Base
        /// → Battlefield and Battlefield → Base. Battlefield → Battlefield
        /// requires Ganking (140.4.c/722), and Base → Base isn't a Move at
        /// all.
        case illegalMoveDestination(from: Location, to: Location)
        /// Rule 594.3: a Recycle used as a cost has to be completable — the
        /// player has no Rune of this Domain in their Rune Area to send
        /// back to the Rune Deck, so the Power it would produce can't be
        /// paid for.
        case noRuneOfDomainAvailable(Domain)
        /// Rule 633: the game is over. Nothing further is legal.
        case gameAlreadyWon(PlayerID)
        case notImplemented
    }

    /// Hands the question to the expert system: `RuleFacts` reads the board,
    /// `RuleEngine` matches `RuleBase.bundled` against it, the first broken
    /// rule is the verdict.
    public static func validate(_ action: GameAction, in state: GameState, proposedBy player: PlayerID) -> Result<Void, Failure> {
        RuleEngine.evaluate(action, in: state, proposedBy: player)
    }

    /// Same question against a rule base supplied by the caller, so a test
    /// can prove a rule changed by editing the knowledge base rather than
    /// the code.
    public static func validate(
        _ action: GameAction,
        in state: GameState,
        proposedBy player: PlayerID,
        using ruleBase: RuleBase
    ) -> Result<Void, Failure> {
        RuleEngine.evaluate(action, in: state, proposedBy: player, ruleBase: ruleBase)
    }
}
