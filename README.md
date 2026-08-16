# RiftChamps

A macOS app that watches a physical *Riftbound: League of Legends TCG* game
through a camera, follows the cards across the table, and checks every move
against a from-scratch implementation of the rulebook.

Point a camera at your playmat, play normally, and the app tells you what it
saw and whether it was legal.

## Architecture Overview

```text
┌──────────────────────────────────────────────────────────────────────┐
│                         RiftboundVisionApp                           │
│                    (macOS SwiftUI — the runnable app)                │
├──────────────────────────────────────────────────────────────────────┤
│  Camera capture → calibration overlay → live overlays → instructions │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ CapturedFrame (CVPixelBuffer + timestamp)
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                          RiftboundVision                             │
├──────────────────────────────────────────────────────────────────────┤
│  ① CoreMLCardDetector    YOLO11n, 38 classes → [Detection]           │
│  ② ObjectTracker         stable IDs across frames                    │
│     ZoneMapper           centroid → calibrated playmat zone          │
│     TemporalEventDetector  debounce → [VisionEvent]                  │
│     ExpertSystemAdapter  VisionEvent → ObservedTableEvent  ──────┐   │
└──────────────────────────────────────────────────────────────────│───┘
                                                                   │
                    ┌──────────────────────────────────────────────┘
                    │ ObservedTableEvent  (BoardObserving)
                    ▼
┌──────────────────────────────────────────────────────────────────────┐
│                       RiftboundTextProcessing                        │
├──────────────────────────────────────────────────────────────────────┤
│  ③ SwiftData cache → SQLite index → FoundationModels → Swift regex   │
│     ActionTranslatingEngine   → CandidateGameAction                  │
│     ExpertSystemTranslatorAdapter → GameAction   ────────────────┐   │
└──────────────────────────────────────────────────────────────────│───┘
                                                                   │
                    ┌──────────────────────────────────────────────┘
                    │ GameAction  (ActionTranslating)
                    ▼
┌──────────────────────────────────────────────────────────────────────┐
│                RiftboundEngine (RiftboundExpertSystem)               │
├──────────────────────────────────────────────────────────────────────┤
│  ④ LegalityValidator   is this legal in this GameState?              │
│     GameActionApplier  mutate through GameStateStore (actor)         │
│     TurnSequencer      the fixed ABCD prefix, and End of Turn        │
│     ChainResolver      the Chain, and Focus around a Showdown        │
│     Combat / Scoring   damage, Conquer, Hold, victory                │
│     Cleanup            rule 518–526 sweep after every action         │
│                        → PlayerInstruction                           │
└──────────────────────────────────────────────────────────────────────┘
```

Four Swift packages, each independently buildable and tested:

| Package | What it is |
|---|---|
| **RiftboundEngine** (`RiftboundExpertSystem`) | Pure rules engine — legality, the Chain, Showdowns, Cleanup, turn structure. No UI, no camera, no ML. The source of truth for "is this move legal." |
| **RiftboundVision** | Camera capture, YOLO detection, object tracking, playmat calibration, card database. A library with no app bundle of its own. |
| **RiftboundTextProcessing** | Card text → game action. SwiftData cache over a SQLite card index, with on-device Foundation Models for cards the index doesn't know. |
| **RiftboundVisionApp** | The runnable macOS app — camera picker, calibration, live overlays, card details, score tracking, and the instruction bar. |

Dependencies point inward; the engine depends on nothing:

```text
RiftboundVisionApp ──▶ RiftboundVision ──────▶ RiftboundEngine
        │                                             ▲
        └──────▶ RiftboundTextProcessing ─────────────┘
```

## How Tracking Works

The system uses a **dual-layer approach** to follow cards in real time:

| Layer | Model | Question it answers | Details |
|-------|-------|---------------------|---------|
| **Detection** | YOLO11n (CoreML, 38 classes) | *What card is where, right now?* | Locates cards in the camera frame and names them. Runs on a 0.35 s poll rather than every frame. Two gates before a detection is trusted: a 0.75 confidence floor, and a card-shape aspect check (1.2–1.8) so a hand or a phone can't pass as a card. Carries no identity — every poll returns a completely fresh array. |
| **Tracking** | Centroid + identity matching | *Is this the same physical card as before?* | Assigns a stable `TrackedObjectID` that survives across polls, so a card can be identified once and then followed. Matching runs in two passes: nearest-centroid within 60 pt, then — for anything left over — by recognized card name at any distance. |

Detection alone can't tell you a card *moved*; it only ever says what is
visible now. Tracking is what turns two frames into "this card left the hand
and arrived on the battlefield," which is the only thing the rules engine can
act on.

## Card Tracking Pipeline

### Centroid Tracking

Each card is reduced to a single point — the centre of its bounding box. That
point, not the box, is what everything downstream reasons about:

```text
   Detection box                    Centroid                 Zone lookup
┌───────────────────┐                                   ┌──────────────────┐
│                   │                                   │   Hand   Base    │
│    Card art       │  ────────►      ●        ────────►│      ●           │
│                   │           (midX, midY)            │  Battlefield     │
└───────────────────┘                                   └──────────────────┘
                                                    which calibrated polygon
                                                    contains the dot?
```

Zone membership is decided by which calibrated polygon contains the centroid.
A card whose dot falls outside every zone resolves to `.unknown` and its
events are dropped — however cleanly the box is drawn around it. The app draws
these dots live, tinted per zone with red for `.unknown`, so that case is
visible rather than silent.

### Two-Pass Identity Matching

Distance matching alone can only follow a card that *slides* across the table.
Actually playing a card means picking it up, carrying it hidden inside your
hand, and setting it down somewhere else — several hundred points in a single
poll, far past any sane distance threshold.

```text
Pass 1 — nearest centroid (≤ 60 pt)        Pass 2 — recognized name (any distance)

  frame N      frame N+1                     frame N        frame N+2
    ●  #3   →    ●  #3                        ● #3      ✋      ● #3
   Hand         Hand                         Hand    (occluded) Battlefield
                                             "Tibbers"          "Tibbers"
  follows a card sliding                     survives a pickup
```

The recognizer already knows *which card* each detection is, so a card
reappearing with the same name as a track that just went missing is that same
physical card. Among several copies of one card the nearest candidate wins, so
two identical Runes side by side can't swap identities.

Without pass 2, every real play produced `.objectAppeared` with no origin —
and an origin-less appearance can't be translated into a Play at all.

### Temporal Confirmation

Raw per-poll zone assignments flicker. `TemporalEventDetector` requires a card
to hold a new zone for **2 consecutive polls** before it emits a
`.objectMoved`, and buckets rotation into 90° steps before calling a card
exhausted (rules 592–593).

### Occlusion Tolerance

A track isn't dropped the moment it stops being detected:

| Situation | Grace period | Why |
|---|---|---|
| Card in a settled zone (Battlefield, Rune Area, Rune Deck) | **300 polls** | A card there genuinely doesn't move. A hand resting over it must not read as "left play." |
| Card anywhere else (Hand, in transit, decks) | **15 polls** (~5 s) | These are exactly the zones where presence really can change between polls. |

### Playmat Calibration

The playmat template is defined in normalized coordinates and mapped onto the
camera frame through a user-positioned rectangle. The geometry is derived from
the border artwork's real pixel dimensions rather than eyeballed — all four
assets are 164 tall and their widths tile exactly:

```text
row 1   394 + 5 + 121 + 5 + 121 = 646     Battlefield · Legend · Champion
row 2   520 + 5 + 121           = 646     Base · Deck
row 3   121 + 5 + 394 + 5 + 121 = 646     Rune Deck · Runes · Trash
```

That all three rows total 646 is what fixes the gutter at exactly 5 pt — it
isn't a tuning knob, it's the only value that makes the artwork tile. Every
zone's aspect ratio therefore equals its artwork's exactly, so nothing
stretches when drawn.

The calibration quad is constrained to an **axis-aligned rectangle**: dragging
a corner resizes it with the opposite corner pinned, and a centre handle moves
it without reshaping. Free-corner dragging allowed any quadrilateral, and one
nudge sheared every zone inside it out of alignment with what the camera saw.

> This gives up perspective correction for an angled camera.
> `PlaymatCalibration.map` still interpolates all four corners, so restoring it
> is a UI change rather than a model one.

## Card Identification Pipeline

Once a card is detected, its printed text and metadata are resolved through a
four-step chain, most authoritative first:

```text
   ┌────────────────────┐  hit
   │ 1. SwiftData cache │──────► type, cost, tags        (<0.05 ms)
   └─────────┬──────────┘
             │ miss
   ┌─────────▼──────────┐  hit
   │ 2. SQLite index    │──────► type, cost, tags        75 cards, bundled
   └─────────┬──────────┘
             │ miss
   ┌─────────▼──────────┐  ok
   │ 3. Foundation      │──────► tagged ─────┐           on-device, macOS 26+
   │    Models tagging  │                    │
   └─────────┬──────────┘                    │ cached back into SwiftData
             │ error / older OS              ▼
   ┌─────────▼──────────┐            (step 1 next time)
   │ 4. Swift regex     │──────► tags only
   └────────────────────┘
```

The database is the primary source because it holds hand-verified type, cost,
and mechanic tags. The Foundation Model only runs for cards the index doesn't
know, and its result is written back so the same card resolves instantly
afterwards.

### The ID Join

Two ID spaces exist and they do **not** overlap:

| Source | Key | Example |
|---|---|---|
| Vision pipeline / `GameState` | `riftbound_id` | `ogn-007-298` |
| Bundled SQLite index | catalogue hex `card_id` | `69bc5bc6d308c64675ca86bc` |

Both come from the same catalogue, so `CardPrinting.id` bridges them — it
matches all 75 rows. The app passes it explicitly as `databaseID`; without it
every lookup misses and known cards fall through to the model.

## The Rules Engine

`GameState` is a plain `Sendable` value type. `GameStateStore` is the actor
that owns it and serializes every mutation — the correctness mechanism for a
system where camera events and rules resolution are separate async producers.

```text
ObservedTableEvent
        │
        ▼  translator.inferAction(from:in:proposedBy:)
   GameAction?  ──nil──► .unrecognizedEvent (with a reason)
        │
        ▼  LegalityValidator.validate
   Result<Void, Failure>  ──failure──► .actionRejected(reason)
        │
        ▼  store.mutate { GameActionApplier.apply; Cleanup.run }
   PlayerInstruction .actionAccepted
```

The physical table is treated as an **untrusted client**. Detection doesn't
drive state directly — it *proposes* deltas, the validator accepts or rejects
them, and only accepted deltas mutate `GameState`. That's what lets the engine
catch a move a player physically made but wasn't allowed to.

### The turn

The only fixed part of a Riftbound turn is its opening:

```text
Awaken → Beginning → Channel → Draw  │  Action Phase  │  End of Turn
├──────── fixed, automatic ─────────┤  └ free-form ┘   └ automatic ┘
```

`TurnSequencer` runs the four Start of Turn steps straight through — 515 gives
nobody a window to act between them — and then stops. The Action Phase "has no
defined structure" (516.2): move units, play cards, trigger Showdowns, in any
order, until you end the turn. **There is no Action → Showdown → End
sequence.** A Showdown is something a Move *causes* (516.5.b).

A Move goes to exactly one Battlefield (140.3.a), which is why each Showdown is
about exactly one Battlefield. Inside a Showdown, Focus starts with the
attacker (549) and passes around the Relevant players; when everyone has passed
in sequence the Showdown ends (553.4.a) and combat resolves. If your units are
the only ones left standing, you Conquer it (627.3) and score (630.1).

### The rune economy

Three separate physical acts, deliberately not collapsed:

| Act | Rule | Effect |
|---|---|---|
| **Channel** | 606.1 | Rune Deck → Rune Area, on the board, ready. Produces nothing. |
| **Exhaust** | 157.2.a | Turn it sideways → +1 Energy. |
| **Recycle** | 157.2.b | Back to the Rune Deck → +1 Power of its Domain. |

Energy comes from *turning* a rune, not from placing one. Both abilities are
the rune's own (577.2), so a player uses them at will with priority.

### Implemented Game Actions

Rules 586–607 define a closed set of 21 Game Actions:

| Action | Validator | Applier | Rules |
|---|---|---|---|
| `.play` | ✅ | ✅ | 555–563 — phase, priority, keyword window, hand membership, destination, Energy + Domain-matched Power |
| `.standardMove` | ✅ | ✅ | 140 — exhaust cost, 140.4 destinations, 2-controller limit |
| `.pass` | ✅ | ✅ | 540.4/553.4 — resolves the Chain, passes Focus, ends Showdowns |
| `.endTurn` | ✅ | ✅ | 516.6/517 — runs End of Turn and hands over |
| `.draw` | ✅ | ✅ | 591 — Limited Action, requires authorization |
| `.channel` | ✅ | ✅ | 606 — Limited; the Channel Phase authorizes it |
| `.exhaust`, `.ready`, `.recycleRune` | ✅ | ✅ | 157.2/592/593 — discretionary for your own Runes |
| Limited Actions (9 more) | 🟡 generic | ❌ | 589.2 authorization check only |
| `.activateAbility`, `.hide`, `.invite` | ❌ | ❌ | fall through `.notImplemented` |

Scoring (629–633) — Hold, Conquer, the once-per-battlefield cap, the final
point, and victory — runs off the back of these rather than being an action of
its own.

## Debugging

The app screen is deliberately quiet: the camera with its overlay, a score and
card-detail sidebar, and one instruction bar along the bottom. Tap a card's box
on the camera to inspect that printing.

The bottom bar is the primary diagnostic, and it is prioritised so the most
actionable thing wins: calibration needed → misplaced cards → the most recent
accepted or rejected verdict → the current phase. A rejection always carries a
reason in the player's words ("you're still in the channel phase", "units can't
move straight between battlefields"), never a validator case name.

`LegalityValidator.Failure` is switched exhaustively where it's rendered, so a
new rejection reason fails the build until someone writes words for it. That's
deliberate: with a `default:` branch, a new *rejection* would have quietly
rendered as "Action accepted."

Watch the `#N` badge on each centroid dot. A card that gets a new number every
time it's touched is being re-created rather than followed, and no play can
ever be recognized from it.

Pipeline stages can be toggled individually from the gear menu; disabling a
stage cascades to everything downstream of it.

## Project Structure

```text
Challenge 5/
├── RiftboundEngine/
│   ├── Sources/RiftboundExpertSystem/
│   │   ├── Model/          GameState, Card, BoardPermanent, Rune, Zones, Location
│   │   ├── StateMachine/   GameStateStore (actor), TurnState, Phase, TurnSequencer,
│   │   │                   Chain, ChainResolver, Showdown, Combat, Scoring, Cleanup
│   │   ├── Actions/        GameAction, GameActionApplier
│   │   ├── Validation/     LegalityValidator
│   │   ├── Ingestion/      BoardObserving, ActionTranslating, ObservedTableEvent
│   │   ├── Output/         PlayerInstruction
│   │   └── GameEngine.swift
│   └── docs/
│       ├── architecture.md
│       └── rules/          core-rules.md, how-to-play.md
├── RiftboundVision/
│   └── Sources/RiftboundVision/
│       ├── Detection/      CoreMLCardDetector, ObjectDetector
│       ├── Tracking/       ObjectTracker, TrackedObject
│       ├── Geometry/       BoardZone, ZoneMapper
│       ├── Events/         VisionEvent, TemporalEventDetector
│       ├── Calibration/    PlaymatCalibration, PlaymatOverlayView, template
│       ├── Adapter/        ExpertSystemAdapter
│       ├── CardDatabase/   CardDatabase, CardPrinting
│       └── Debug/          LiveDetectionOverlayView, TrackedObjectOverlayView
├── RiftboundTextProcessing/
│   └── Sources/RiftboundTextProcessing/
│       ├── Engine/         ActionTranslatingEngine
│       ├── Services/       SwiftDataCardService, CardDatabaseService,
│       │                   FoundationModelTaggingService, SwiftRegexParsingService
│       ├── Models/         RiftboundCard (@Model)
│       ├── Adapter/        ExpertSystemTranslatorAdapter
│       └── Resources/      RiftboundCardDatabase.db
└── RiftboundVisionApp/
    └── RiftboundVisionApp/
        ├── CameraPipelineController.swift
        ├── GameSessionBuilder.swift
        ├── BoardStatePersistence.swift
        ├── ContentView, DetectedCardsPanel, CardDetailView, TurnControlBar,
        │   GameStateBar, ScoreTracker, InstructionLogEntry, PipelineSettingsView
        └── Assets.xcassets/
```

## Building

Each package builds and tests independently:

```bash
cd RiftboundEngine && swift test          # rules engine
cd RiftboundVision && swift test          # CV pipeline
cd RiftboundTextProcessing && swift test  # NLP pipeline
```

`RiftboundTextProcessing` uses SwiftData and Foundation Models macros, so it
needs the full Xcode toolchain rather than Command Line Tools:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

`RiftboundVisionApp` is an Xcode project depending on the other three as local
packages — open it and run the `RiftboundVisionApp` scheme.

## Requirements

| | |
|---|---|
| macOS | 26+ for Foundation Models tagging; older falls back to regex |
| Xcode | 26+ (SwiftData + Foundation Models macros) |
| Swift | 6, strict concurrency |
| Camera | Any AVFoundation device; Continuity Camera works well overhead |

## Updating the Card Database

The detector finds cards generically and the index identifies them, so **new
cards do not require retraining YOLO** — unless the model can't detect them at
all.

| Change | Retrain YOLO? |
|---|---|
| New cards added to the index | **No** — rebuild `RiftboundCardDatabase.db` |
| New card frame/border style | Usually no, unless detection starts missing them |
| New class labels, different input size | Yes |

When rebuilding the `.db`, key it on **`riftbound_id`**, not the catalogue's
hex `id` — that's what the rest of the pipeline uses. The two are 1:1 across
all 75 printings, and alternate arts stay distinct (`ogn-214-298` vs
`ogn-214a-298`).

## Known Gaps

Flagged rather than papered over:

- **Nothing proposes `.exhaust` when a rune turns.** The engine models the rune
  economy properly now, and both rune abilities are discretionary, so the path
  is open — but the vision layer only *counts* exhausted runes, it never emits
  an action for one turning sideways. Until it does, no Energy can enter a pool
  from play, which is why `GameSessionBuilder` still seeds one. **The fix is
  that event, not a bigger seeded number.**
- **`parseAbility` returns `[]`.** Mechanic tags are extracted and then
  dropped, so no card ability ever executes. `EffectInstruction` is fully
  defined but nothing runs it. Score abilities (632.2) wait on this too.
- **No second seat.** The engine handles an opponent's Hold, Conquer and Focus,
  but the app is built for one local player, so scoring is still effectively
  manual and a Showdown has nobody to pass to.
- **Units and Gear skip the Chain.** Spells push onto it, so Reactions get a
  real window; Units and Gear still resolve immediately. Reaction and Legion
  timing depend on that becoming real.
- **No deck or player setup UI.** The hand is seeded with every Unit and Spell
  in the bundled decks, and the Rune Deck is a placeholder two-of-each-Domain.
  Deliberately permissive, not a real deck.
- **No Layers (634–639).** Combat and Cleanup use printed Might, so a buffed or
  debuffed unit fights at its printed value, and Assault, Shield, Deflect and
  Tank damage-ordering don't apply. One consequence worth knowing: 627.2's
  "both sides survive" outcome is arithmetically unreachable without them, so
  an even trade is always mutual destruction.

## Roadmap

- [ ] Emit `.exhaust` when the camera sees a rune turn, and drop the seeded pool
- [ ] Route mechanic tags into `parseAbility` → `EffectInstruction` execution
- [ ] Second seat, so Hold, Conquer and Focus have an opponent to work against
- [ ] Deck selection and player identification, replacing the permissive hand
- [ ] Push Units and Gear through the Chain, so Reactions resolve in rules order
- [ ] Layers, and the combat keywords that depend on them
