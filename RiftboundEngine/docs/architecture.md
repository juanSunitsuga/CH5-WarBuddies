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
│  ⚠ parsed + shown, not executed — see §7     │  CardAbilityParser  
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
| `Rune` | `Model/Rune.swift` | A Channeled Rune sitting in a Rune Area (606.1). Carries its whole `RuneCard`, because Recycling puts *that card* back on the Rune Deck (154.2.b). |
| `Location` | `Model/Location.swift` | **Only** `.base` and `.battlefield` (rule 106). |
| `GameObject` | `Model/Location.swift` | `id`, `owner`, `controller` — Control ≠ ownership (179–183). |

**The subtlety to keep:** `Card` (rule 052) is a narrower category than
`GameObject`. Runes, Legends, and Battlefields are Game Objects but not
"cards." Card text that says "card" means the narrower thing. Conflating them
breaks triggers like Legion (724), which counts *Main Deck cards played*, not
any object entering play.

`Rune` is where that distinction earns its keep. A Rune is a Game Object on
the board with a stance, and `RuneCard` is the card it came from — they are
separate because the two halves genuinely separate: Recycling moves the card
back to the deck while the object leaves play. A Rune is also explicitly *not*
a Permanent (154.1.a), so it lives beside `Unit`/`Gear` rather than among them.

### The rune economy (153–160, 594, 606)

Three distinct physical acts, and the reason they must stay distinct:

| Act | Rule | Effect |
|---|---|---|
| **Channel** | 606.1 | Rune Deck → Rune Area, on the board, Ready. Produces **nothing**. |
| **Exhaust** | 157.2.a `[T]: Add [1]` | Turn it sideways → **+1 Energy**. |
| **Recycle** | 157.2.b / 594.1.b | Rune Area → bottom of Rune Deck → **+1 Power** of its Domain. |

Channel used to do `runePool.energy += count`, collapsing the first two. That
paid players for runes they had only placed, let costs be met without turning
anything, and left the Rune Area with nothing in it for the camera to count.

Both abilities carry a `:`, so 577.2 makes them **Activated Abilities** whose
costs happen to be Exhausting and Recycling — Discretionary, needing only
Priority. They were previously gated on 589.2 authorization that nothing ever
granted, which made the entire economy unreachable from the camera. Channel
stays Limited; 606.3.a says so outright.

Pools empty at the end of each Draw Phase **and** each turn (160/515.4.d/
517.2.c), for *every* player both times.

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

### The turn (514–517) — `StateMachine/TurnSequencer.swift`

A Riftbound turn is one rigid prefix and then nothing:

```
Awaken → Beginning → Channel → Draw  │  Action Phase  │  End of Turn
├──────── fixed, automatic ─────────┤  └ free-form ┘   └ automatic ┘
```

515 gives the four Start of Turn steps no windows of opportunity, so
`TurnSequencer` runs them straight through without asking anyone. 516.2 then
says the Action Phase "has no defined structure" — a player moves units, plays
cards and triggers Showdowns in any order and any number of times until they
end the turn (516.6). **There is no Action → Showdown → End sequence.** A
Showdown is something a Move *causes* (516.5.b), not a step the turn advances
into.

So `.action` is terminal in the sequencer: `advance` refuses to move past it,
and only `GameAction.endTurn` leaves. `endTurn` walks 517's steps as it
performs them rather than setting the phase once at the end — `Cleanup` reads
`phase` to decide whether a Showdown may open, so leaving it at `.action`
through the Cleanup Step let a turn end by starting a fight.

The validator gates `.play` and `.standardMove` on `.action` (516.1/140.1.a),
which is what makes "you're still in the channel phase" a real, reportable
verdict instead of a silently accepted move.

### The Chain (532–544)

A literal stack, resolved top-down (543.1), requiring a full pass-around among
Relevant Players before popping (539–542). Implemented in
`StateMachine/Chain.swift` and unit-tested.

> **Partly driven live.** `GameActionApplier.applyPlay` pushes a **Spell**
> onto the Chain, so Reactions get a real window against it (509.1.a) before
> anything happens. **Units and Gear still resolve immediately** — they have no
> `ChainItem` shape — and the two rune abilities resolve immediately too, by a
> deliberate divergence from 577.3 documented at `validateRuneAbility` (putting
> "add 1 energy" on the Chain would require a full pass-around before the
> Energy existed to spend with). With one seat the difference is unobservable
> today, but Reaction (725) and Legion (724) timing depend on it being real, so
> these are known simplifications rather than design choices.

### Showdowns and Focus (545–553)

Its own structure, not just "combat" — it also fires when moving into an
uncontested empty battlefield (516.5.b). Holds `focusPlayer`,
`relevantPlayers`, and an optional owned `Chain` for its Initial Chain (551).

**Focus moves**, and that movement is the engine of the whole Showdown:

- 549 — the player who applied Contested status gets it first (the attacker).
- 553.5 — it passes to the next *Relevant* player when its holder passes,
  skipping seats that aren't Relevant to this Showdown (550.1 makes a Combat
  Showdown two-player even at a table of four).
- 552 — it passes again when a nested Chain's last item resolves, and the run
  of passes resets, because 553.4.a counts passes *in sequence*.
- 553.4.a — when every Relevant player has passed in sequence, the Showdown
  ends and Combat resolves.

`ChainResolver.pass` returns a `PassOutcome` rather than `ChainItem?` because a
Pass is not one thing: it can record, resolve a Chain item, or end a Showdown,
and the caller applies something different for each. The old `ChainItem?`
could only express the middle one — which is why a Pass during a Showdown
silently did nothing, Focus never moved, and the turn stopped dead.

### Combat (620–628) — `StateMachine/Combat.swift`

Runs when a Combat Showdown closes: 626 damage → 627 resolution → 628 Cleanup.
627.3 is what it exists to reach — *no Defending Units remain but Attacking
Units do* — because that hands Control over (627.3.a), which is rule 630.1's
definition of a Conquer.

Damage assignment (626.1.d) is nominally the assigning player's choice, but
626.1.d.1 (Tank first) and 626.1.d.2 (lethal in full before moving on) narrow
it enough that a stable canonical order is faithful. Not modelled, and each
would change the numbers: Assault (719), Shield (726), Deflect (721), and
"assign me last" restrictions. Might is printed Might, since the Layers
calculator (637) doesn't exist.

### Scoring (629–633) — `StateMachine/Scoring.swift`

Hold (630.2) at the Beginning Phase, Conquer (630.1) on gaining Control,
capped once per battlefield per turn (631). The final point is asymmetric and
easy to get wrong: a Hold takes it outright (632.1.b.1), but a Conquer takes it
only if the player has scored *every* battlefield this turn — otherwise they
draw a card instead (632.1.b.2). You cannot steal the last point with one late
attack.

### Cleanup (518–526)

The state-based action sweep. Run after **every** Chain item resolution, Move
completion, Showdown completion, and Combat completion.

Pending Combat detection, Showdown opening, and Control-follows-presence
(181.4.d) happen inside Cleanup. It is one pure function called religiously —
inlining ad hoc versions of it is the most common way these engines silently
drift from spec.

181.4.d isn't a numbered Cleanup step, but 181.5 calls Control "a constant
state with no reliance on timing", which makes it exactly the kind of fact a
Cleanup reconciles. It matters more than it looks: 525 only opens a Showdown
at a Contested battlefield with **no** Controller, so a battlefield whose
controller had left stayed unconquerable by anyone while looking entirely
normal on the table.

Both 525 and 526 are gated on the Action Phase (516.5) — Cleanup also runs from
End of Turn (517.3), and without the gate a turn could end by opening a
Showdown and handing it to the next player.

`GameEngine.process` runs `GameActionApplier.apply` and `Cleanup.run` inside a
single `store.mutate`, so no observer can see the state between them. `apply`
returns `[PlayerInstruction]`, because an action can *cause* something the
player must be told that isn't the action itself — a Conquer, a Hold, a win —
and none of that is derivable from the `GameAction` alone.

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

> **Status: parsed and shown, not executed.** `CardAbilityParser` reads
> printed text into this vocabulary and `ExpertSystemTranslatorAdapter.parseAbility`
> returns it, so a card's abilities reach the player — the app lists what
> everything in play does, and names each by the Game Action it resolves to.
> What still doesn't happen is *execution*: nothing runs an
> `EffectInstruction` against `GameState`.
>
> The untargeted cases (`.draw`, `.channelRune`, `.discard`) carry real
> arguments and are the ones the engine could already apply. Targeted ones
> come back with `TargetSpec.placeholder`, because `TargetSpec` /
> `LocationSpec` / `EffectCondition` are still placeholders on purpose —
> their shape gets settled against real card text rather than guessed. Until
> then a targeted ability can be *named* but not aimed, and the
> `ParsedAbility.summary` is what carries its meaning.
>
> Text that mentions a game verb but matches no known shape is reported as
> unparsed rather than guessed at. A card whose ability shows as unread is a
> parser gap someone can go fix; one silently invented is a wrong game state
> nobody can trace.

When it is built, resolution must follow the defined steps: re-validate
targets at *resolution* time (559.3.c), apply Layers in Trait → Ability →
Arithmetic order (634–639), and run replacement effects (571–575) as a filter
*before* the effect executor rather than a special case inside it.

## 4b. Play flow at the table (`RiftboundVision`)

The Expert System validates *actions*. What the player at the table needs is
a level below that: which physical steps they still owe. Those are different
questions, and the second one lives in `RiftboundVision` because it's about
what the camera can see, not about legality.

Four types, none of which know anything about the Chain or `GameState`:

| Type | Answers |
|---|---|
| `ManualGameState` / `GamePhase` | Which phase, whose turn — the facts vision can't infer |
| `PhaseAutoDetector` | Has the player finished this phase's step yet? |
| `RunePayment` | Can the runes on the table cover this card? |
| `PendingPlay` | What does this played card still owe? |

The app layer that renders all of this has its own notes —
`RiftboundVisionApp/design.md` — covering the palette, the shared control
styles, and the UI traps that have already cost time. Read it before
changing anything the player looks at.

**The turn shown to the player is five phases, not eight.** 517's Ending,
Expiration and Cleanup are real, but a player does nothing in them, so
`GamePhase` stops at `.action` and ending the Action Phase hands over
directly. `TurnSequencer` still models all three properly — this enum is the
player-facing sequence, not the rules one.

**Verdicts are withheld until the Action Phase.** 516.2 makes it the only
phase whose contents the player chooses, so it's the only one where "was that
allowed?" is a question. During the fixed prefix the bar says what to *do*
instead; narrating each card touched while following a script buries the
instruction being followed.

**A play is a sequence, not a moment.** The card lands, then it's turned
sideways (139.4), then runes are turned for Energy (157.2.a), then runes go
back to the Rune Deck for Power (157.2.b). `PendingPlay` holds the Action
Phase open until all of it is done, and refuses a second card meanwhile — a
half-paid play is a board the engine and the table disagree about, and every
action stacked on top inherits that disagreement.

Progress is measured against **baselines taken as the card landed**. "Two
runes are exhausted" means nothing; "two more than when this card hit the
table" is the payment. Power is the mirror image: recycling takes the rune
off the board, so it reads as the Rune Area shrinking. That's inferred from
the area rather than the deck growing because a deck is a *stack* — the
detector sees one object on top however many cards are underneath.

Three ways a play could settle itself for free, each guarded: a card the
camera has lost sight of counts as not-yet-turned (otherwise a hand passing
over the table pays a cost); runes reappearing can't count as negative
payment; and a card that enters ready (717) owes nothing for its own stance.

## 5. Legality Validator

Given `GameState` + a proposed `GameAction`, return legal or illegal-with-a-
reason. Its most valuable job is **reverse inference**: given an observed
physical delta, decide which legal action (if any) explains it, and flag the
ones that don't. That is the anti-mistake mechanism, more than pre-approving
moves.

Implemented checks:

| Action | Rules | Checks |
|---|---|---|
| `.play` | 555–563 | Action Phase (516.1); priority; card actually in hand; keyword gate per `TurnState` — none in Neutral Open, Reaction when Closed (509.1.a), Action-or-Reaction in a Showdown (508.1.a); Units need a real Location (559.2); Gear can't target a Battlefield (144.2); destination not held by 2 other controllers; Energy from the pool and Power matched against `Cost.eligibleDomains` (560–561); observed exhausted-rune count matches cost when supplied (130.2) |
| `.standardMove` | 140 | Action Phase and Neutral Open — which is also how 140.1.b/c's "not Closed, not during a Showdown" is enforced; priority; unit exists and is ready; destination legal per 140.4 (Base↔Battlefield; Battlefield→Battlefield needs Ganking); destination not held by 2 other controllers (140.4.a.1 / 623.2) |
| `.endTurn` | 516.6 | Action Phase; proposer is the Turn Player |
| Rune abilities | 157.2, 577 | `.recycleRune`, and `.exhaust` of one's *own* Runes: priority only — Activated Abilities, so **not** authorization-gated. `.recycleRune` also needs a matching Rune present (594.3) |
| Limited Actions | 589.2 | Authorized in `GameState.pendingLimitedActions` — generic across all of them |
| Anything | 633 | Rejected outright once someone has won |

`Failure` cases are user-facing by design (`cardNotInHand`,
`insufficientEnergy(required:available:)`, `notActionPhase(Phase)`,
`illegalMoveDestination(from:to:)`, `noRuneOfDomainAvailable(Domain)`), so the
app renders a real reason instead of a validator case name. The enum is
exhaustively switched in `InstructionLogEntry` on purpose: adding a case
without giving the player words for it fails the build rather than rendering a
rejection as "Action accepted."

**Known gaps:** `.hide`, `.invite`, `.activateAbility` and the remaining
Limited Actions get the generic 589.2 authorization check only, with no
per-action logic; team-mode co-priority (516.2.b.1 / 648.8.a) isn't modelled,
so "whose turn" is strict.

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
| 3 | Chain + priority passing | 532–544 | ✅ built; Spells push onto it, Units/Gear still resolve immediately |
| 4 | Showdown + Focus | 545–553 | ✅ Focus passes, Showdowns end |
| 4b | Combat damage + resolution | 620–628 | 🟡 damage/lethal/recall/conquer; no Assault, Shield, Deflect, Tank ordering |
| 5 | Cleanup as a first-class function | 518–526 | ✅ |
| 6 | Legality validator | 586–615 | 🟡 `.play`, `.standardMove`, `.draw`, `.endTurn`, rune abilities |
| 6b | Scoring — Hold, Conquer, victory | 629–633 | ✅ |
| 6c | Rune economy — channel, exhaust, recycle | 153–160, 594, 606 | ✅ Runes are board objects |
| 7 | Ability parsing | 586–607 | ✅ `CardAbilityParser`; untargeted cases produce real `EffectInstruction`s |
| 7b | Effect execution + Layers | 634–639 | ❌ nothing runs an `EffectInstruction` yet |
| 8 | NLP → candidate `GameAction` | — | ✅ live |
| 9 | Detection → `ObservedTableEvent` | — | ✅ live |
| 10 | Instruction / feedback UI | — | ✅ live (instruction bar + card details) |
| 11 | Play flow at the table | 515–516, 139.4, 157.2 | ✅ `PhaseAutoDetector`, `RunePayment`, `PendingPlay` — see §4b |
| 12 | Auto-detect of the fixed phases | 515 | ✅ Awaken, Beginning, Channel, Draw; Action never auto-completes (516.2) |
| 13 | Onboarding | — | ✅ first-launch sheet, reachable later from Help |
| 14 | Long-session stability | — | ✅ diagnostic buffers capped; no per-poll `@Model` writes |

Items 8–12 run end to end in `RiftboundVisionApp`: `GameEngine` is constructed
per session, driven from the adapter's event stream, and its
`PlayerInstruction`s render in the app alongside the play-flow prompts §4b
describes.

### What blocks fuller play, in order

1. **Propose `.exhaust` when a rune turns.** The engine now models the real
   rune economy — Channel puts a Rune on the board (606.1), Exhausting it is
   what adds Energy (157.2.a), Recycling returns the card to the Rune Deck for
   Power (157.2.b/594.1.b) — and both abilities are Discretionary, so no
   authorization blocks them. The vision layer now *sees* it too — since
   `best-3`, orientation is derived from box shape and
   `ExpertSystemAdapter` emits `.cardOrientationChanged(nowExhausted:)`. What
   is missing is the last hop: `ExpertSystemTranslatorAdapter` explicitly
   returns `nil` for that event, saying Exhaust/Ready is "handled elsewhere in
   the pipeline" — and nowhere else handles it. Until it maps to
   `GameAction.exhaust`, no Energy can enter a pool from play, which is why
   `GameSessionBuilder` still seeds a stand-in pool. **The fix is that one
   translation, not a bigger seeded number.**
2. **Item 7b — execute `EffectInstruction`.** Parsing is done: card text now
   reaches the player as named Game Actions. What's missing is anything that
   *runs* one against `GameState`, so a card still doesn't do what it says.
   Score abilities (632.2), Cleanup's 520/522/523, and every targeted effect
   (which needs a real `TargetSpec` first) all wait on this.
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
