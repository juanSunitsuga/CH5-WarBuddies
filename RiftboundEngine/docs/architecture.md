# Riftbound Expert System — Architecture Design

## 0. Framing

The rulebook already gives you a formal grammar to build against:

- **Zones** (106–107): Base, Battlefield Zone, Facedown Zone, Legend Zone, Trash, Champion Zone, Main Deck, Rune Deck, Banishment, Hand
- **States** (507–510): Neutral/Showdown × Open/Closed — 4 combinations that gate what actions are legal
- **The Chain** (532–544): a stack-based resolution structure for spells/abilities
- **Showdowns** (545–553): windows of opportunity nested inside combat or standalone
- **Layers** (634–639): deterministic ordering for effects that alter traits/abilities/numbers
- **Cleanup** (518–526): the state-based-action sweep that runs after every discrete event

This means your expert system isn't really "validate this specific move" — it's **a state machine that mirrors these constructs exactly**, with a validator sitting on top of it. If you model Chain/Showdown/Cleanup faithfully, most "is this legal?" questions answer themselves because illegal states simply can't be constructed.

## 1. Layered System Overview

This is the original design sketch, written before any of it existed. It's
now real — three sibling Swift packages implement it, wired together
through this package's two ingestion protocols
(`BoardObserving`/`ActionTranslating`). See the root `README.md` for the
current per-stage status (what's implemented/tested/live in the app).

```
┌─────────────────────────────────────────────┐
│  Physical Table                              │  RiftboundVision:
│  YOLO detection → Object Tracking →          │  CoreMLCardDetector,
│  calibrated zone resolution                  │  ObjectTracker, ZoneMapper
└───────────────────┬───────────────────────────┘
                     │ VisionEvent (debounced, zone-resolved)
                     ▼
┌─────────────────────────────────────────────┐
│  Event Ingestion (BoardObserving)            │  RiftboundVision:
│  - VisionEvent → ObservedTableEvent          │  ExpertSystemAdapter
└───────────────────┬───────────────────────────┘
                     │ ObservedTableEvent
                     ▼
┌─────────────────────────────────────────────┐
│  NLP Translation (ActionTranslating)         │  RiftboundTextProcessing:
│  - card text → candidate GameAction          │  ExpertSystemTranslatorAdapter
│  - resolved against real GameState.zones     │  wrapping ActionTranslatingEngine
└───────────────────┬───────────────────────────┘
                     │ candidate GameAction
                     ▼
┌─────────────────────────────────────────────┐
│  Legality Validator (core of "expert system")│  this package:
│  - checks action against current GameState   │  LegalityValidator
│  - references rules 587–615 (Game Actions)   │
└───────────────────┬───────────────────────────┘
                     │ accepted GameAction
                     ▼
┌─────────────────────────────────────────────┐
│  State Machine (Turn/Phase/Chain/Showdown)   │  this package:
│  - owns GameState (single source of truth)   │  GameStateStore, GameEngine,
│  - applies action, runs Cleanup sweep         │  GameActionApplier, Cleanup
└───────────────────┬───────────────────────────┘
                     │ triggers "ability text needs resolving"
                     ▼
┌─────────────────────────────────────────────┐
│  Ability Resolution Pipeline                 │  this package:
│  - NLP parses card text → structured Effect  │  EffectInstruction (defined,
│  - Effect executed against GameState          │  not yet executed — see §7)
└───────────────────┬───────────────────────────┘
                     │ resulting state diff
                     ▼
┌─────────────────────────────────────────────┐
│  Instruction / Feedback Layer                │  this package:
│  - tells player what to physically do next    │  PlayerInstruction
│  - flags illegal moves already made physically│  (defined; app doesn't
└─────────────────────────────────────────────┘  render it live yet — see §7)
```

The key architectural decision: **GameState is the single source of truth, and the physical table is treated as an untrusted client that proposes actions.** OCR doesn't drive the state directly — it proposes deltas, the validator accepts/rejects them, and only accepted deltas mutate GameState. This is what lets you catch a player physically making an illegal move (e.g. moving a unit to an already-2-controlled battlefield) and flag it instead of silently corrupting your model.

## 2. Core Data Model

Below is the *original* pre-implementation sketch, kept for the rationale
in its comments — the real types have since drifted from it in a few
places (no `Identifiable` conformance; `PlayerZones` field names are
`legend`/`championZoneCard`, not `legendZone`/`championZone`). Treat this
as illustrative, not authoritative — for the real shapes, read
`Sources/RiftboundExpertSystem/Model/*.swift` directly (`GameObject` in
`Location.swift`, `Unit` in `BoardPermanent.swift`, `PlayerZones` in
`Zones.swift`).

```swift
// Game Objects (rule 119–123) — everything that can produce effects or be a target
protocol GameObject {
    var id: ObjectID { get }
    var owner: PlayerID { get }
    var controller: PlayerID { get set }   // rule 179–183, Control ≠ Ownership
}

struct Unit: GameObject {
    var id: ObjectID
    var owner: PlayerID
    var controller: PlayerID
    var cardDefinitionID: CardDefID   // links to NLP-parsed ability text
    var location: Location            // Base or a specific Battlefield
    var isExhausted: Bool
    var damage: Int
    var buff: Bool                    // rule 701–705, max 1 buff
    var temporaryKeywords: [Keyword]  // granted this turn, cleared at Expiration Step
}

enum Location: Hashable {
    case base(PlayerID)
    case battlefield(BattlefieldID)
    // NOT hand/deck/trash — those are card-level zones, not "locations" per rule 106
}

// Zones as explicit containers, not just implicit groupings
struct PlayerZones {
    var hand: [MainDeckCard]
    var mainDeck: [MainDeckCard]      // ordered, secret (127.3)
    var runeDeck: [RuneCard]          // ordered, secret
    var trash: [Card]                 // unordered, public
    var banishment: [Card]            // unordered, public
    var legend: ChampionLegend
    var championZoneCard: MainDeckCard?   // empty once played to board
    var runePool: RunePool            // ephemeral, empties at Draw Phase end + turn end
}
```

**Important subtlety from the rules to bake in early:** `Card` (154.1, 176) is *not* the same category as `GameObject`. Runes, Legends, Battlefields are Game Objects but not "cards" per rule 052 — lots of card text says "card" and means something narrower than what's on the board. If you conflate these in your type system you'll misfire triggers like Legion (724) which counts "Main Deck cards played," not any game object entering play.

## 3. State Machine

Model the four states explicitly (507–510) rather than as booleans scattered around:

```swift
enum TurnState {
    case neutralOpen
    case neutralClosed(chain: Chain)
    case showdownOpen(showdown: Showdown)
    case showdownClosed(showdown: Showdown, chain: Chain)
}
```

This single enum answers "what can be played right now" (508–510) almost for free — pattern-match on it, and each case has a known legal-action set (only Reaction in Closed states, only Action/Reaction in Showdown states, anything on your turn in Neutral Open).

### The Chain (532–544)

This is a literal stack:

```swift
final class Chain {
    private(set) var items: [ChainItem] = []   // last = next to resolve
    private(set) var activePlayer: PlayerID
    private(set) var passedPlayers: Set<PlayerID> = []

    func add(_ item: ChainItem) { items.append(item); passedPlayers.removeAll() }
    func pass(_ player: PlayerID) -> ChainResolution { ... }  // rule 540.4
}
```

Resolve top-down (543.1), re-derive Relevant Players and require a full pass-around before popping (539–542). This is the single most important piece to get exactly right — Reactions (725), Legion timing, and combat trigger ordering all depend on Chain semantics being correct, not approximated.

### Showdowns (545–553)

A Showdown is a distinct nested structure, not just "combat" — it also fires on moving into an empty contested battlefield (516.5.b). Model it as its own object holding `focusPlayer`, `relevantPlayers`, and an optional owned `Chain` for its Initial Chain (551).

### Cleanup (518–526)

This is your **state-based action sweep** — run it after every: Chain item resolves, Move completes, Showdown completes, Combat completes. It's not optional bookkeeping; rules like Battlefield control changes, lethal-damage kills, and Pending Combat detection all *only* happen inside Cleanup. Implement it as a single pure function `func cleanup(_ state: GameState) -> GameState` you call religiously after every mutation — this is the piece most engines get subtly wrong by inlining ad hoc versions of it in five different places.

## 4. Ability Resolution Pipeline (where your NLP plugs in)

Your NLP layer should output a structured `Effect`, not free text:

```swift
enum EffectInstruction {
    case dealDamage(amount: Int, targets: TargetSpec)
    case draw(count: Int)
    case discard(count: Int)
    case buff(targets: TargetSpec)
    case moveUnit(unit: TargetSpec, destination: LocationSpec)
    case channelRune(count: Int, exhausted: Bool)
    // ... one case per Game Action in section 590–607 (Draw, Exhaust, Ready,
    //     Recycle, Play, Move, Hide, Discard, Stun, Reveal, Counter, Buff,
    //     Banish, Kill, Add, Channel, Burn Out)
}
```

This is a strong design constraint worth committing to: **section 590–607 of the rulebook enumerates a closed set of Game Actions.** Your NLP's job is to map arbitrary card text onto *only* those primitives. If your NLP tries to output something outside that vocabulary, that's a signal the parse failed, not a new game action — the engine should reject/flag it for human review rather than execute unknown behavior.

Execution then follows the exact resolution steps already defined:
- Targeting/mistargeting rules (559.3.c) — re-validate legality at *resolution* time, not just at declaration time (a target can become illegal mid-chain)
- Layers (634–639) for anything that alters traits/abilities/numbers, applied in Trait → Ability → Arithmetic order, with dependency-based ordering within a layer
- Replacement effects (571–575) intercept before the effect they modify executes — implement as a filter function that runs *before* your normal effect executor, not as a special case inside it

## 5. Legality Validator

This is the layer that talks to OCR/tracking. Its job: given `GameState` + a proposed `GameAction`, return `.legal` or `.illegal(reason)`. Since Discretionary Actions (589.1) are the ones players choose to take physically, this is what you're validating in real time:

- Standard Move (140): is destination a Base/Battlefield the unit can legally reach, is it already occupied by 2 other players' units (140.4.a.1), is the unit exhausted already
- Playing a card (554–563): can they pay the cost (Rune Pool sufficiency), is the state Open, is it their priority window
- Combat legality (623): no 3-player combats, Pending/in-progress battlefields are invalid destinations for outside players

Because OCR gives you physical ground truth (card moved from base to battlefield X), your validator's most valuable job is actually **reverse-inference**: given an observed delta, find which legal GameAction (if any) explains it, and reject/flag deltas that don't correspond to any legal action — that's your primary anti-cheat/mistake-catching mechanism, more than pre-approving moves.

## 6. Swift/macOS Implementation Notes

Given your Swift 6 strict-concurrency experience from PlantPal:

- **`GameState` is a plain, `Sendable` value type; `GameStateStore` is the actor that owns and serializes mutation of it** (implemented — see `Model/GameState.swift`/`StateMachine/GameStateStore.swift`). All mutations (Chain pushes/pops, Cleanup, effect application) go through the store serially — this matters more here than it would elsewhere since detection events, NLP resolution, and user-facing instructions are all separate async producers. `GameState` isn't `Codable` yet (no replay/undo serialization built), which was originally sketched here as a nice-to-have — still a reasonable future addition, not yet needed for anything currently built.
- **Effects and Chain items as an enum, not a class hierarchy** — matches the closed-set nature of section 590–607 and makes exhaustive `switch` your friend for correctness (compiler yells if you add a new Game Action and forget to handle it somewhere). Implemented: `GameAction`, `EffectInstruction`.
- Keep the **detection/NLP integration behind protocols** (`BoardObserving`, `ActionTranslating` — implemented in `Ingestion/`) so you can swap in fixtures/mocks for testing rule logic without needing the camera pipeline running. Both are implemented for real now by sibling-package adapters (`RiftboundVision.ExpertSystemAdapter`, `RiftboundTextProcessing.ExpertSystemTranslatorAdapter`), not just fixtures — see `GameEngineTests`/`LegalityValidatorTests` for the fixture-based side of this, and the sibling packages' own test suites for the adapters. The rulebook's worked examples (559.3.c.5, 594.5, 638, etc.) are already used verbatim as test cases across this package's test suite.

## 7. Build Order — actual status

The original suggested order, annotated with what's actually true today
(cross-check against the root `README.md`'s pipeline status table, which
is the single source of truth for current state — this list shouldn't
drift from it again):

1. ✅ Core types (GameObject/Zones/Location) + static deck/board setup (rules 100–184)
2. ✅ Turn phase state machine — `Phase`/`StartOfTurnStep`/`EndOfTurnStep` (515–517)
3. ✅ Chain + priority passing (532–544) — `Chain.swift`
4. ✅ Showdown + Combat steps (545–553, 620–628) — `Showdown.swift`
5. ✅ Cleanup as a first-class function (518–526) — `Cleanup.swift`, called from `GameEngine.process`
6. 🟡 Legality Validator — implemented for `standardMove` and `draw` only; every other `GameAction` case (critically `.play`) falls through a `.notImplemented` default in both `LegalityValidator` and `GameActionApplier`. **This is the actual next item**, not a fresh integration step.
7. 🟡 Effect execution pipeline + Layers — `EffectInstruction` is fully defined (rule 590–607 vocabulary), but nothing executes it against `GameState` yet, and `TargetSpec`/`LocationSpec`/`EffectCondition` are still placeholders (by design — see the type's own doc comment: don't guess the shape before real card text is in hand to pressure-test against). No cards manually encoded yet either.
8. ✅ Wire in NLP output → candidate `GameAction` mapping — `RiftboundTextProcessing.ExpertSystemTranslatorAdapter` implements `ActionTranslating` for real, resolving against actual `GameState.zones[player].hand` (not a fabricated `ObjectID`). Note this produces `GameAction`, not `EffectInstruction` — item 7 (ability *text* → effect) is a separate, still-unstarted piece from item 8 (a card *entering play* → the action of playing it).
9. ✅ Wire in detection/tracking → `ObservedTableEvent` — `RiftboundVision.ExpertSystemAdapter` implements `BoardObserving` for real, reconnected as a live second consumer in `RiftboundVisionApp.CameraPipelineController` (independent of the app's own stateless live-detection overlay).
10. ❌ Feedback/instruction UI layer — `PlayerInstruction` is fully defined, but nothing in `RiftboundVisionApp` constructs a live `GameEngine`/`GameState` yet to produce or render one. The app currently only shows the raw detection count and a debug count of `ObservedTableEvent`s, not real game state or player-facing instructions.

**What's actually blocking end-to-end play**, in priority order: (a) item 6
— fill in `LegalityValidator`/`GameActionApplier` for `.play` at minimum;
(b) real game setup (deck loading, player identification) so
`RiftboundVisionApp` can construct a real `GameState` instead of
placeholder `PlayerID`s; (c) wiring a live `GameEngine` in the app,
consuming the already-reconnected `ObservedTableEvent` stream and
rendering `PlayerInstruction`.
