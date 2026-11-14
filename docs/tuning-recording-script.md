# Recording script for the six detection parameters

One take, one camera setup, one app setup. Afterwards the take is split
into clips, and each parameter is swept by replaying only the clip that
provokes it — no camera, no cards, no re-staging.

Play style throughout is **beginner-slow**: the player hesitates, holds a
card over a zone while deciding, rests a hand on the table while reading.
That is the behaviour the parameters have to survive, so it is the
behaviour that gets recorded.

---

## 0. Why the durations are what they are

Detection polls at **5 Hz at best** — `CameraPipelineController`'s
`minimumDetectionInterval` is 0.2 s, and the real rate is
`max(0.2, averageDetectionDuration × 1.3)`. Every parameter counted in
"frames" is counted in *polls*, not video frames.

| Parameter | Slider range | In seconds at 5 Hz |
|---|---|---|
| `occlusionToleranceFrames` | 1–120 polls | 0.2 s – **24 s** |
| `confirmationFrames` | 1–20 polls | 0.2 s – 4 s |
| `labelCommitThreshold` | 3.0–30.0 vote-weight | ≈ 3.3–33 polls at 0.9/poll → 0.7 s – **6.7 s** |

**Read your real rate first.** Open the Debugger Panel and note
*detections/sec* on your Mac. If it is 3 Hz, not 5, every duration in this
script scales by 5/3. Write the measured rate on the slate (§1) so the
clips stay interpretable later.

Three behaviours are **not** tunable by these six and must not be confused
with them:

- A card in the **Battlefield, Rune Area or Rune Deck** uses a fixed 300-poll
  occlusion tolerance (`Zone.isPositionallyStable`). `occlusionToleranceFrames`
  does nothing there. Segment 6 is staged in the **Base** for this reason.
- A card whose identity has **committed** uses a fixed 60 polls. So segment 6
  must cover the card *before* it commits — within about 1.5 s of placing it.
- Committed identity is **permanent for the life of the track** and dies with
  the track. Once frozen, no later poll renames that card.

---

## 1. Before you press record

- [ ] Mount the camera where the app will actually use it. **Do not move it
      again for the whole take.** Zone calibration is derived per frame size,
      not per camera pose — nudging the camera invalidates the zones for
      every segment after the nudge, and there is no way to recalibrate
      mid-file.
- [ ] Fix one resolution and one frame rate for the whole take. A resolution
      change mid-file re-derives the mat geometry from scratch.
- [ ] Lock exposure and white balance if your camera allows it. Auto-exposure
      hunting changes detector confidence for reasons that have nothing to do
      with `minimumConfidence`.
- [ ] Whole playmat in frame, with ~5 cm margin on every side.
- [ ] Have ready: 6 ordinary cards, **2 visually similar cards** (same
      champion or near-identical art), 1 square token or die, 1 coin,
      1 pen, a card sleeve.
- [ ] **Audio on.** You are going to narrate. The narration is the answer
      key — on replay it is the only record of what *should* have happened.

## 2. The take

Say every bracketed cue **out loud**. Hold still for the stated duration;
counting out loud ("one… two… three") is better than guessing.

### Segment 1 — Slate (0:20)
- [ ] Empty mat, nothing on it. Hold still 10 s.
- [ ] Say: *"Slate. [date]. [resolution]. [camera]. Measured poll rate
      [N] hertz. Defaults: confidence 0.75, aspect 1.20 to 1.80, radius 1.2,
      occlusion 15, commit 6.0, confirm 2."*
- [ ] Hold still another 10 s. This is the calibration reference frame.

### Segment 2 — Lighting ladder → `minimumConfidence` (0:35)
- [ ] Place 4 cards square-on in the Base, well lit. Say *"segment two,
      bright."* Hold 10 s, hands out of frame.
- [ ] Dim the room, or shade the mat from off-frame. Say *"dim."* Hold 10 s.
- [ ] Dim further, to the worst light you would tolerate. Say *"dark."*
      Hold 10 s.
- [ ] Restore the light. Hold 5 s.

### Segment 3 — False-positive bait → `minimumConfidence`, aspect (0:20)
- [ ] Clear the mat. Place the token, coin, pen and empty sleeve on it.
      **No cards.** Say *"segment three, no cards present."* Hold 20 s,
      hands out of frame.
- [ ] Anything the overlay boxes here is a false positive, and the only
      honest way to pick a confidence floor.

### Segment 4 — Aspect ladder → `cardAspectRatioRange` (0:45)
- [ ] One card, square-on, Base. Say *"square on."* Hold 8 s.
- [ ] Same card tilted ~30° away from the camera. Say *"tilted thirty."*
      Hold 8 s.
- [ ] Tilt to ~60°. Say *"tilted sixty."* Hold 8 s.
- [ ] Two cards overlapping by half. Say *"two overlapping."* Hold 8 s.
- [ ] Four cards in a tight row, edges touching. Say *"row of four."*
      Hold 8 s.
- [ ] The square token alone. Say *"square token."* Hold 5 s.

### Segment 5 — Slow nudge and fast swipe → `matchRadiusInCardLengths` (0:40)
- [ ] One card in the Base. Hold 5 s so a track exists.
- [ ] Nudge it ~1 cm. Pause 2 s. Repeat six times. Say *"nudging."*
- [ ] Slide it slowly ~15 cm across the Base over 5 s. Say *"slow slide."*
- [ ] Return it, pause 3 s, then **swipe it across the whole mat in under
      half a second.** Say *"fast swipe."* Hold 5 s.
- [ ] The swipe is the case a tight radius loses. The nudges are the case a
      wide radius should not need.

### Segment 6 — Neighbour capture → `matchRadiusInCardLengths` (0:35)
- [ ] Two *different* cards side by side in the Base, about one card-width
      apart. Say *"two neighbours."* Hold 8 s.
- [ ] Remove the **left** one, cleanly, hand out of frame fast.
      Say *"left removed."* Hold 8 s.
- [ ] Replace it. Hold 5 s. Now **swap the two cards slowly, crossing their
      paths**, over about 4 s. Say *"swapping."* Hold 8 s.
- [ ] A too-wide radius lets the survivor inherit the dead card's track, and
      lets the swap hand each card the other's identity.

### Segment 7 — Occlusion ladder, uncommitted → `occlusionToleranceFrames` (1:40)
Staged in the **Base**, and the hand must land **within 1 second** of the
card, before the identity commits. If you are slow, the fixed 60-poll
committed tolerance applies instead and this segment measures nothing.

For each duration: place card → cover immediately with a flat hand →
hold → lift hand away → 5 s gap.
- [ ] 2 s. Say *"cover two."*
- [ ] 5 s. Say *"cover five."*
- [ ] 10 s. Say *"cover ten."*
- [ ] 15 s. Say *"cover fifteen."*
- [ ] 25 s. Say *"cover twenty-five."* (Past the 120-poll maximum — this is
      the one that must fail at every setting.)

### Segment 8 — Occlusion of a settled card (0:40)
- [ ] Place one card in the Base. Say *"settling."* Hold **15 s untouched**
      so the identity commits.
- [ ] Cover it 20 s. Say *"cover settled, twenty."* Uncover. Hold 5 s.
- [ ] This one is governed by the fixed 60 polls, not by the slider. It is
      here so you can tell the two apart when a track survives.

### Segment 9 — Confusable pair → `labelCommitThreshold` (1:00)
- [ ] Place similar card **A** alone in the Base. Say *"card A."*
      Hold 20 s untouched.
- [ ] Remove it. Hold 5 s with the spot empty. Say *"removed."*
- [ ] Place similar card **B** in the *same spot*. Say *"card B, same spot."*
      Hold 20 s untouched.
- [ ] Name both cards aloud, exactly as printed. This is the segment that
      shows whether the threshold commits to the wrong one of a pair.

### Segment 10 — Bad first look → `labelCommitThreshold` (0:30)
- [ ] Bring a card in at a steep angle, half out of the light, and hold it
      there 3 s. Say *"bad look."*
- [ ] Then lay it square-on and well lit in the Base. Say *"good look."*
      Hold 20 s untouched.
- [ ] A threshold that is too low freezes the bad read and never recovers.

### Segment 11 — Hover ladder → `confirmationFrames` (1:10)
The beginner's hesitation. Carry the card into the Battlefield, **keep
holding it**, then take it back to the Base. Nothing is played, so any event
reported here is a phantom.

- [ ] Hover 1 s, withdraw. Say *"hover one."* Pause 4 s.
- [ ] Hover 2 s, withdraw. Say *"hover two."* Pause 4 s.
- [ ] Hover 3 s, withdraw. Say *"hover three."* Pause 4 s.
- [ ] Hover 5 s, withdraw. Say *"hover five."* Pause 4 s.
- [ ] Hover 8 s, withdraw. Say *"hover eight."* Pause 4 s.

### Segment 12 — Real plays, which must still be seen (0:50)
- [ ] Carry a card from Base to Battlefield, **release it**, hand out of
      frame. Say *"played one."* Leave it 15 s.
- [ ] Same to a second Battlefield. Say *"played two."* Leave it 15 s.
- [ ] Same to a third. Say *"played three."* Leave it 15 s.
- [ ] This is the control for segment 11. A `confirmationFrames` high enough
      to silence every hover also has to keep reporting these.

### Segment 13 — Rotation → `confirmationFrames` (0:40)
- [ ] With a card on a Battlefield: rotate it ~45° toward exhausted and back,
      twice, 2 s each way, never settling. Say *"rotation hover."*
- [ ] Then rotate it fully to exhausted and leave it. Say *"exhausted, left."*
      Hold 15 s.
- [ ] Rotate back to ready and leave it. Say *"ready, left."* Hold 15 s.

### Segment 14 — End slate (0:15)
- [ ] Hands out of frame, mat untouched. Say *"end of take."* Hold 15 s.

**Total ≈ 9–10 minutes.**

## 3. After the take — split it once

Note the wall-clock start of each segment from the narration (a waveform
view makes the spoken cues easy to find), then cut. Needs `ffmpeg`
(`brew install ffmpeg`); `-c copy` re-muxes without re-encoding, so it is
fast and lossless, but it cuts only at keyframes — expect each clip to
start up to a second early.

```bash
ffmpeg -ss 00:00:55 -to 00:01:30 -i take.mov -c copy seg02-light.mov
```

Name them for the parameter each one feeds:

| Clip | Segments | Sweep |
|---|---|---|
| `conf-light.mov` | 2 | `minimumConfidence` |
| `conf-bait.mov` | 3 | `minimumConfidence` |
| `aspect.mov` | 4 | `cardAspectRatioRange` |
| `radius.mov` | 5, 6 | `matchRadiusInCardLengths` |
| `occlusion.mov` | 7, 8 | `occlusionToleranceFrames` |
| `commit.mov` | 9, 10 | `labelCommitThreshold` |
| `confirm.mov` | 11, 12, 13 | `confirmationFrames` |

Keep `take.mov` as well: the one full-length replay at the end is what shows
the six chosen values working together.

## 4. Replaying a clip

Per run: Camera menu → **Play Video File…** → the clip → **Start**.

- [ ] Change **one** parameter per run. All six interact, and a sweep of two
      at once cannot attribute a change to either.
- [ ] **Restart the clip after changing a value.** The sliders take effect
      live, but tracker state does not reset: accumulated label votes,
      frozen identities, occlusion counters and zone streaks all carry over,
      so a mid-run change is measured against the previous value's history.
      Only `minimumConfidence` and the aspect bounds are per-frame filters
      and safe to change live.
- [ ] Measurement Report → **Discard this session's samples** between runs,
      or the latency and event counts are a blend of both settings.
- [ ] **Export CSV after every run.** The session label carries all six
      values and the file name, so the export is self-describing. Two runs
      not exported are two runs you cannot compare.

### What to score, per parameter

The app cannot tell you whether an identity was *right* — it has no ground
truth. Segments 1–14 and your narration are the ground truth, so these three
are counted by watching:

| Parameter | Count from the overlay / Tracking log | Fails by |
|---|---|---|
| `minimumConfidence` | boxes on non-cards (seg 3); cards missed in dim light (seg 2) | too low: phantom cards. too high: cards vanish when the light drops |
| `cardAspectRatioRange` | which of seg 4's poses keep a box | too narrow: tilted cards drop out. too wide: merged pairs and the mat edge become "cards" |
| `matchRadiusInCardLengths` | ID changes during seg 5; identity swaps during seg 6 | too small: the fast swipe loses the track. too large: the neighbour steals it |
| `occlusionToleranceFrames` | longest seg 7 cover that keeps the same ID | too small: a resting hand costs the identity. too large: a card taken off the table lingers |
| `labelCommitThreshold` | whether seg 9 names A and B correctly; whether seg 10 recovers | too low: the bad look freezes. too high: the name keeps wobbling and never settles |
| `confirmationFrames` | phantom events in seg 11; missed plays in seg 12 | too low: every hesitation reads as a play. too high: real plays are missed |

From the report itself: **4.4.3 untranslated share** and **4.4.5 unknown
zone** counts both rise when tracking is unstable, so they are a useful
cross-check — but neither distinguishes *which* of the six caused it.

### Order to sweep in

Later parameters are measured through earlier ones, so fix them in this
order and leave each one alone afterwards:

1. `minimumConfidence` — everything downstream sees only what passes it.
2. `cardAspectRatioRange` — same reason.
3. `matchRadiusInCardLengths` — identity cannot be judged while tracks break.
4. `occlusionToleranceFrames` — same.
5. `labelCommitThreshold` — needs stable tracks to vote on.
6. `confirmationFrames` — needs stable zones to confirm.

### Starting guesses for beginner-slow play

Not answers — starting points, each with the reason to move it. A slow
player gives the pipeline *more* agreeing polls and *longer* hesitations,
which pushes four of the six up from their defaults.

| Parameter | Default | Try | Why, for slow play |
|---|---|---|---|
| `minimumConfidence` | 0.75 | 0.75 | unchanged — a function of the model and the light, not the pace |
| aspect | 1.20–1.80 | 1.20–1.80 | unchanged — a function of the camera angle |
| `matchRadiusInCardLengths` | 1.2 | 0.8–1.2 | cards travel little between polls, so a tighter radius costs nothing and resists neighbour capture |
| `occlusionToleranceFrames` | 15 (3 s) | 30–50 (6–10 s) | a beginner rests a hand on the table while reading; 3 s is shorter than one pause |
| `labelCommitThreshold` | 6.0 (1.4 s) | 8–12 (1.8–2.7 s) | there is time to look properly, and a frozen misread is permanent |
| `confirmationFrames` | 2 (0.4 s) | 5–10 (1–2 s) | a beginner holds a card over a zone for a second or more while deciding; at 0.4 s every hesitation is a play |

Segment 12 is the brake on the last one: raise `confirmationFrames` until
the hovers stop firing, then check the three real plays are still reported,
and stop there.
