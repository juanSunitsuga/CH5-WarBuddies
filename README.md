# CH5-WarBuddies

A computer-vision + rules-engine system for playing physical *Riftbound:
League of Legends TCG* with a camera watching the table — cards are
identified from a live camera feed, printed rules text is translated into
game actions, and legality is checked against a from-scratch
implementation of the ruleset.

Four Swift packages, each independently buildable and tested:

```
RiftboundVisionApp  ──depends on──▶  RiftboundVision  ──depends on──▶  RiftboundEngine
        │                                                                      ▲
        └──depends on── RiftboundTextProcessing ──depends on───────────────────┘
```

| Package | What it is |
|---|---|
| **RiftboundEngine** (`RiftboundExpertSystem` module) | Pure rules engine — legality, the Chain, Cleanup, Turn Structure. No UI, no camera, no ML. Source of truth for "is this move legal." |
| **RiftboundVision** | Camera capture, YOLO card detection, object tracking, playmat-zone calibration, card database. A library, no app bundle of its own. |
| **RiftboundTextProcessing** | Card-text → game-action inference: a MiniLM embedder + CoreML classifier + regex fallback, backed by a real SQLite card index. |
| **RiftboundVisionApp** | The runnable macOS app — camera picker, live detection overlay, playmat calibration, manual round/turn/phase control. |

## The pipeline

```
Camera → ① YOLO Detection → ② Tracking + Zones → ③ NLP Translation → ④ Expert System → Player Instruction
```

1. **YOLO Object Detection** (`CoreMLCardDetector`, RiftboundVision) — a
   trained YOLO11n model finds every card/Rune in frame, gated by a
   confidence floor and a card-shape aspect-ratio check so background
   clutter can't get misidentified as a card. Runs on a 0.35s poll, not
   every camera frame.
2. **Object Tracking + Area of Region** (`ObjectTracker` /
   `TemporalEventDetector` / `ExpertSystemAdapter`, RiftboundVision) —
   resolves each detection to a calibrated playmat zone (Hand/Base/
   Battlefield/etc.), gives it a stable identity across frames, and
   debounces raw detection noise into confirmed `ObservedTableEvent`s.
   Runs as a second, independent consumer of the same detections the live
   overlay shows — the overlay wants "what's visible now," this wants
   "what changed, debounced and identity-stable."
3. **NLP Action Translation** (`ActionTranslatingEngine` +
   `ExpertSystemTranslatorAdapter`, RiftboundTextProcessing) — the
   identified card's real printed text (no OCR needed — the text is
   already known once the card is identified) goes through a CoreML
   classifier (Unit/Spell/Rune) and a regex tag extractor, then resolves
   to an actual `GameAction` against the real hand state.
4. **Expert System** (`GameEngine`, RiftboundEngine) — validates the
   candidate action against the rules (`LegalityValidator`), applies it to
   `GameState`, runs Cleanup, and returns a `PlayerInstruction`
   (accepted / rejected / choice required / scored / game won).

## Current status

| Stage | Implemented | Tested | Wired into the app |
|---|---|---|---|
| ① YOLO Detection | ✅ | — | ✅ live |
| ② Tracking + Zones | ✅ | ✅ | ✅ (reconnected as a second detection consumer) |
| Seam: VisionEvent → ObservedTableEvent | ✅ | ✅ | ✅ |
| ③ NLP Translation | ✅ | ✅ (18/20*) | seam built, not yet driving a live `GameEngine` |
| ④ Expert System | ✅ | ✅ | not yet fed by a live `GameEngine` in the app |

\* 2 known failures are a CoreML classifier accuracy issue (its
tokenizer isn't a real WordPiece tokenizer), not a code defect.

**Known gaps, flagged rather than papered over:**
- `TableRegion` (RiftboundEngine) can only represent Hand/Base/
  Battlefield — Main Deck, Rune Deck, Trash, and Rune Area have no
  representation yet, so Draw and Channel Rune signatures can't be
  forwarded from the vision layer at all.
- `GameAction.play` has no `LegalityValidator`/`GameActionApplier` logic
  yet (`standardMove` and `draw` are the only implemented cases) — a
  correctly-resolved `.play` action currently comes back
  `.actionRejected(reason: .notImplemented)`.
- `expertSystemAdapter`'s zone calibration is a one-time snapshot taken
  when the camera starts; re-dragging the playmat overlay afterward
  updates the visual layer live but not this adapter's zone resolution.
- No player-identification or deck-setup UI exists yet — the app mints
  placeholder `PlayerID`/`BattlefieldID`s once per session rather than
  reading a real match configuration.
- The app doesn't yet construct a live `GameEngine`/`GameState` — Stage
  ③/④ are real, tested, and wired to each other, but nothing in
  `RiftboundVisionApp` drives them from the reconnected Stage ②
  `ObservedTableEvent` stream yet.

## Building

Each package builds and tests independently:

```bash
cd RiftboundEngine && swift test          # rules engine
cd RiftboundVision && swift test          # CV pipeline
cd RiftboundTextProcessing && swift test  # NLP pipeline
```

`RiftboundVisionApp` is an Xcode project (`RiftboundVisionApp.xcodeproj`)
depending on the other three as local Swift packages — open it in Xcode
and run the `RiftboundVisionApp` scheme.
