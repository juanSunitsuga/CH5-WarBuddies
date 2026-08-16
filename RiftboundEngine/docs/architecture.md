# Riftbound Expert System — Architecture

## 0. Framing

The rulebook already supplies a formal grammar to build against:

| Construct | Rules | What it gives you |
|---|---|---|
| **Zones** | 106–107 | Base, Battlefield, Facedown, Legend, Trash, Champion, Main Deck, Rune Deck, Banishment, Hand |
| **States** | 507–510 | Neutral/Showdown × Open/Closed — four combinations that gate legality |
| **The Chain** | 532–544 | Stack-based resolution for spells and abilities |
| **Showdowns** | 545–553 | Windows of opportunity, nested in combat or standalone |
| **Layers** | 634–639 | Deterministic ordering for effects that alter traits/abilities/numbers |
| **Cleanup** | 518–526 | The state-based-action sweep after every discrete event |

So this isn't "validate this move" — it's **a state machine mirroring those
constructs exactly**, with a validator on top. Model Chain, Showdown, and
Cleanup faithfully and most legality questions answer themselves, because
illegal states can't be constructed in the first place.

## 1. Layered System Overview

Four packages. Dependencies point inward; this package depends on nothing.

```text
┌──────────────────────────────────────────────┐
│  Physical table                              │  RiftboundVision
│  YOLO detection → tracking → zone resolution │  CoreMLCardDetector,
│                                              │  ObjectTracker, ZoneMapper
└────────────────────┬─────────────────────────┘
                     │ VisionEvent (debounced, zone-resolved)
                     ▼
┌──────────────────────────────────────────────┐
│  Event ingestion            BoardObserving   │  RiftboundVision
│  VisionEvent → ObservedTableEvent            │  ExpertSystemAdapter
└────────────────────┬─────────────────────────┘
                     │ ObservedTableEvent
                     ▼
┌──────────────────────────────────────────────┐
│  Action translation      ActionTranslating   │  RiftboundTextProcessing
│  card text → candidate GameAction            │  ExpertSystemTranslatorAdapter
│  resolved against real GameState.zones       │  over ActionTranslatingEngine
└────────────────────┬─────────────────────────┘
                     │ GameAction
                     ▼
┌──────────────────────────────────────────────┐
│  Legality validator                          │  this package
│  GameState + GameAction → legal / illegal    │  LegalityValidator
└────────────────────┬─────────────────────────┘
                     │ accepted GameAction
                     ▼
┌──────────────────────────────────────────────┐
│  State machine                               │  this package
│  owns GameState, applies action, runs Cleanup│  GameStateStore, GameEngine,
│                                              │  GameActionApplier, Cleanup
└────────────────────┬─────────────────────────┘
                     │ triggers "ability text needs resolving"
                     ▼
┌──────────────────────────────────────────────┐
│  Ability resolution                          │  EffectInstruction
│  ⚠ defined, not executed — see §7            │  (nothing runs it yet)
└────────────────────┬─────────────────────────┘
                     │ resulting state diff
                     ▼
┌──────────────────────────────────────────────┐
│  Instruction / feedback                      │  PlayerInstruction
│  what to do next, and what was rejected      │  rendered live in the app
└──────────────────────────────────────────────┘
```

**The key decision: `GameState` is the single source of truth, and the
physical table is an untrusted client that proposes actions.** Detection never
mutates state directly. It proposes deltas; the validator accepts or rejects;
only accepted deltas mutate. That is what lets the engine catch a move a
player physically made but wasn't allowed to, instead of silently corrupting
its own model.

## 2. Core Data Model

Read the real shapes in `Sources/RiftboundExpertSystem/Model/` — this section
describes them rather than duplicating them, so it can't drift.

| Type | File | Notes |
|---|---|---|
| `GameState` | `Model/GameState.swift` | Plain `Sendable` struct. Requires non-empty `turnOrder`, `battlefields`, `zones`. |
| `PlayerZones` | `Model/Zones.swift` | Only `legend` is required; every other zone defaults to empty. `hand` is `[MainDeckCard]`. |
| `MainDeckCard` | `Model/Card.swift` | A *card* (rule 052). `.unit(isChampion:)` / `.gear` / `.spell`. |
| `ChampionLegend`, `Battlefield` | `Model/Card.swift` | Game Objects, deliberately **not** `MainDeckCard`. |
| `Unit`, `Gear` | `Model/BoardPermanent.swift` | Board instances. Units enter exhausted (139.4). |
| `Location` | `Model/Location.swift` | **Only** `.base` and `.battlefield` (rule 106). |
| `GameObject` | `Model/Location.swift` | `id`, `owner`, `controller` — Control ≠ ownership (179–183). |

**The subtlety to keep:** `Card` (rule 052) is a narrower category than
`GameObject`. Runes, Legends, and Battlefields are Game Objects but not
"cards." Card text that says "card" means the narrower thing. Conflating them
breaks triggers like Legion (724), which counts *Main Deck cards played*, not
any object entering play.

## 3. State Machine

The four states are one enum, not booleans scattered around:

```swift
enum TurnState {
    case neutralOpen
    case neutralClosed(Chain)
    case showdownOpen(Showdown)
    case showdownClosed(Showdown, Chain)
}
```

Pattern-matching on it answers "what can be played right now" (508–510)
almost for free, and `playerWithPriority(turnPlayer:)` derives priority from
it rather than from a separate field that could disagree.

### The Chain (532–544)

A literal stack, resolved top-down (543.1), requiring a full pass-around among
Relevant Players before popping (539–542). Implemented in
`StateMachine/Chain.swift` and unit-tested.

> **Not yet driven live.** `GameActionApplier.applyPlay` resolves immediately
> rather than pushing onto the Chain. With a single seat and legality
> restricted to Neutral Open there is no observable difference today, but
> Reaction (725) and Legion (724) timing depend on it being real, so this is a
> known simplification rather than a design choice.

### Showdowns (545–553)

Its own structure, not just "combat" — it also fires when moving into an
uncontested empty battlefield (516.5.b). Holds `focusPlayer`,
`relevantPlayers`, and an optional owned `Chain` for its Initial Chain (551).

### Cleanup (518–526)

The state-based action sweep. Run after **every** Chain item resolution, Move
completion, Showdown completion, and Combat completion.

Battlefield control changes, lethal-damage kills, and Pending Combat detection
happen *only* inside Cleanup. It is one pure function called religiously —
inlining ad hoc versions of it in several places is the most common way these
engines silently drift from spec.

`GameEngine.process` runs `GameActionApplier.apply` and `Cleanup.run` inside a
single `store.mutate`, so no observer can see the state between them.

## 4. Ability Resolution — where the NLP plugs in

The NLP layer outputs structured effects, never free text:

```swift
enum EffectInstruction {
    case dealDamage(amount: Int, targets: TargetSpec)
    case draw(count: Int)
    case buff(targets: TargetSpec)
    case moveUnit(unit: TargetSpec, destination: LocationSpec)
    // ... one case per Game Action in 590–607
}
```

**Rules 586–607 enumerate a closed set of 21 Game Actions.** Mapping arbitrary
card text onto *only* those primitives is the constraint. Text that doesn't
map is a parse failure to surface, not a new primitive to invent.

> **Status: defined, not executed.** `EffectInstruction` exists with the full
> vocabulary, but nothing runs it against `GameState`, and `TargetSpec` /
> `LocationSpec` / `EffectCondition` are still placeholders — deliberately, so
> their shape is settled against real card text rather than guessed. Both
> `parseAbility` implementations return `[]`, so mechanic tags extracted by the
> NLP layer are currently dropped.

When it is built, resolution must follow the defined steps: re-validate
targets at *resolution* time (559.3.c), apply Layers in Trait → Ability →
Arithmetic order (634–639), and run replacement effects (571–575) as a filter
*before* the effect executor rather than a special case inside it.

## 5. Legality Validator

Given `GameState` + a proposed `GameAction`, return legal or illegal-with-a-
reason. Its most valuable job is **reverse inference**: given an observed
physical delta, decide which legal action (if any) explains it, and flag the
ones that don't. That is the anti-mistake mechanism, more than pre-approving
moves.

Implemented checks:

| Action | Rules | Checks |
|---|---|---|
| `.play` | 555–563 | Neutral Open + priority; card actually in hand; Units need a real Location (559.2); Gear can't target a Battlefield (144.2); destination not held by 2 other controllers; Energy payable from the Rune Pool (560–561) |
| `.standardMove` | 140 | Neutral Open + priority; unit exists and is ready; destination not held by 2 other controllers (140.4.a.1 / 623.2) |
| Limited Actions | 589.2 | Authorized in `GameState.pendingLimitedActions` — generic across all of them |

`Failure` cases are user-facing by design (`cardNotInHand`,
`insufficientEnergy(required:available:)`, `invalidPlayDestination`), so the
app renders a real reason instead of a validator case name.

**Known gaps:** Power cost isn't checked (`RunePool.power` and `Cost.power`
aren't typed alike yet); Showdown/Focus-based play timing isn't modelled, so
legality is restricted to Neutral Open.

## 6. Swift / macOS Implementation Notes

- **`GameState` is a plain `Sendable` value type; `GameStateStore` is the
  actor** that owns it and serializes mutation. This matters more here than
  usual because detection events, NLP resolution, and user-facing instructions
  are separate async producers. `GameState` is not `Codable` — no replay or
  undo is built, and nothing currently needs it.
- **Actions and effects are enums, not class hierarchies**, matching the
  closed-set nature of 586–607. Exhaustive `switch` then makes the compiler
  catch a new action that some site forgot to handle.
- **Integration stays behind protocols.** `BoardObserving` and
  `ActionTranslating` (in `Ingestion/`) let rule logic be tested with fixtures
  and no camera. Both have real sibling-package implementations as well as
  fixtures — see `GameEngineTests` and `LegalityValidatorTests` for the fixture
  side.
- Rulebook worked examples (559.3.c.5, 594.5, 638) are used verbatim as test
  cases, quoted in the tests' doc comments.

## 7. Status

| # | Item | Rules | Status |
|---|---|---|---|
| 1 | Core types, zones, board setup | 100–184 | ✅ |
| 2 | Turn phase state machine | 515–517 | ✅ `TurnSequencer` runs Awaken→Draw and End of Turn |
| 3 | Chain + priority passing | 532–544 | ✅ built, ⚠ not driven live |
| 4 | Showdown + Focus | 545–553 | ✅ Focus passes, Showdowns end |
| 4b | Combat damage + resolution | 620–628 | 🟡 damage/lethal/recall/conquer; no Assault, Shield, Deflect, Tank ordering |
| 5 | Cleanup as a first-class function | 518–526 | ✅ |
| 6 | Legality validator | 586–615 | 🟡 `.play`, `.standardMove`, `.draw`, `.endTurn`, rune abilities |
| 6b | Scoring — Hold, Conquer, victory | 629–633 | ✅ |
| 6c | Rune economy — channel, exhaust, recycle | 153–160, 594, 606 | ✅ Runes are board objects |
| 7 | Effect execution + Layers | 634–639 | ❌ defined, not executed |
| 8 | NLP → candidate `GameAction` | — | ✅ live |
| 9 | Detection → `ObservedTableEvent` | — | ✅ live |
| 10 | Instruction / feedback UI | — | ✅ live (turn bar + event log) |

Items 8–10 run end to end in `RiftboundVisionApp`: `GameEngine` is constructed
per session, driven from the adapter's event stream, and its
`PlayerInstruction`s render in the app.

### What blocks fuller play, in order

1. **Propose `.exhaust` when a rune turns.** The engine now models the real
   rune economy — Channel puts a Rune on the board (606.1), Exhausting it is
   what adds Energy (157.2.a), Recycling returns the card to the Rune Deck for
   Power (157.2.b/594.1.b) — and both abilities are Discretionary, so no
   authorization blocks them. But the vision layer only *counts* exhausted
   runes (`observedExhaustedRuneCount`); it never emits an action for one
   turning. Until it does, no Energy can enter a pool from play, which is why
   `GameSessionBuilder` still seeds a stand-in pool. **The fix is that event,
   not a bigger seeded number.**
2. **Item 7** — route the NLP layer's mechanic tags into `parseAbility` and
   execute `EffectInstruction`, so cards actually *do* what they say. Score
   abilities (632.2) and Cleanup's 520/522/523 all wait on this too.
3. **A second seat.** `GameEngine` is built for one local player, so an
   opponent's Hold, Conquer and Focus are unreachable in the app even though
   the engine handles them. Scoring is therefore still effectively manual.
4. **Real game setup** — deck selection and player identification, replacing
   the app's stand-in hand (every Unit and Spell) and placeholder Rune Deck
   (two of each Domain).
5. **Drive the Chain** for real, so Reactions resolve in rules order —
   `applyPlay` still resolves a Unit/Gear immediately rather than pushing it.
6. **Layers (634–639)** — combat and Cleanup both use printed Might, so a
   buffed or debuffed Unit fights at its printed value, and Assault (719),
   Shield (726), Deflect (721) and Tank ordering don't apply.
