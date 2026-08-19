# RiftChamps — Design Notes for Claude

Read this before changing anything the player looks at. It covers the app
layer only; rules behaviour lives in `RiftboundEngine/CLAUDE.md` and
`RiftboundEngine/docs/architecture.md`.

The point of this file is that most UI work here has been *re*-work. Nearly
every entry below was learned by getting it wrong first, and the reasons are
easier to lose than the code.

---

## 1. Where the design comes from

There is a hi-fi mockup ("V3") and a "Color Scheme and Typography" board.
`DesignSystem/RiftboundTheme.swift` is the transcription of both, and it is
the single source of truth.

**Never write a colour, size or corner radius inline.** Before the theme
existed the same panel blue was three slightly different
`Color(red:green:blue:)` triples across three files. If a value isn't in
`RiftboundPalette` / `RiftboundFont`, either it belongs on the board and
should be added there with the board's own name, or it shouldn't exist.

Naming the tokens is what makes "does this match the reference" a checkable
claim instead of an eyeball one.

### Palette, by role

| Token | Hex | Where it belongs |
|---|---|---|
| `mainBackground` | `#10415E` | Window, header, bottom bar |
| `secondaryBackground` | `#0A496A` | Right-hand column — separates without a divider |
| `elementShadow` | `#1D3145` | Element shadow/stroke; fill behind chip art; camera letterbox |
| `primaryButton` | `#A36F18` | Primary buttons, score caption bars, ±steppers |
| `highlightOverlay` | `#CEA73F` | Score numeral backing, active phase pip, selected box |
| `playmatOverlay` | `#C5A560` | Zone frames over the feed, recognized card boxes |
| `elementStroke` | `#D9BC87` | Card-art borders, panel outlines |
| `iconicText` | `#FFE0AD` | 50/80pt display type |
| `regularText` | `#FFF2D6` | Everything at 15pt |
| `disabledHighlightOverlay` | `#545454` | Disabled fills, and the *secondary* button |

Never `Color.black`. The letterbox around the aspect-fit feed is a large
area of the window and pure black is the one shade belonging to no part of
the palette — it reads as a hole. Use `elementShadow`.

### Type

Sora, four weights, five sizes. `body` 15 regular, `subheading` 15 semibold,
`heading` 15 bold, `iconic2` 50 bold (turn banner), `iconic` 80 bold (score).

`RiftboundFont.sora` falls back to system-rounded when the face didn't
register, so a preview or test shows slightly-wrong type rather than a blank
screen. Registration happens twice on purpose — `ATSApplicationFontsPath`
for the built app, `RiftboundFontLoader` for previews.

Monospace is allowed in exactly one place: the camera diagnostic dump, where
column alignment is the content.

---

## 2. Layout

```
┌───────────────────────────────────────────────┬──────────────┐
│ title bar — camera · calibrate · ? · Start    │              │
├───────────────────────────────────────────────┤   Score      │
│ GameStateBar: turn banner + terms legend      │              │
├───────────────────────────────────────────────┤  Card        │
│                                               │  Library     │
│              camera stage (16:9)              │              │
│                                               │              │
├───────────────────────────────────────────────┤              │
│ TurnPhasePanel + status strip │ controls      │              │
└───────────────────────────────┴───────────────┴──────────────┘
```

The header and the bottom bar live **inside the left column**, not spanning
the window. That is what puts the Score panel level with the turn banner and
lets the sidebar run unbroken to the bottom edge.

The camera stage is locked to 16:9 and inset in a gold `elementStroke`
frame. Without the aspect lock the stage took whatever rectangle the split
left it, the feed letterboxed itself inside, and the frame ended up
enclosing two slabs of empty space.

### The title bar must stay visible

`.windowStyle(.hiddenTitleBar)` is **not** available to us, and this is
load-bearing rather than taste.

`.automatic` toolbar items trail the window title. With the title hidden
there is no title to trail, so every item packs against the leading edge
whatever placement it is given. This was attempted four times — a leading
title item, no title item, `.primaryAction`, and finally a hand-drawn
`HStack` — before the cause was found. Hiding the title bar costs the
toolbar its alignment, and no placement or modifier buys it back.

If a future task says "hide the title bar", the honest answer is that the
toolbar buttons move left with it.

---

## 3. Shared components — use these, don't re-make them

| Type | Use for |
|---|---|
| `RiftPrimaryButtonStyle` | The action that advances the current step |
| `RiftSecondaryButtonStyle` | The quieter of a pair; a real style, not "primary, disabled" |
| `RiftSwitchToggleStyle` | The Auto-detect switch |
| `RiftPanelCard` | Any bordered panel |
| `RiftFlowConnector` | The arrow between phase cards |
| `CardArtView` | **Every** card image, both sizes |
| `RiftboundArt` | Asset names for chip art — never string literals at call sites |

Two of these exist because a helper got copied and the copies drifted:

- `icon(for:)`/`color(for:)` were duplicated across two panels, so one
  verdict rendered in two colours on the same screen. They live on the type
  now (`Verdict.iconName` / `.tint`) and the compiler keeps the cases in step.
- `CardArtView` was two separate `AsyncImage` call sites, and *both* made the
  same mistake — see §5.

---

## 4. What the player is told, and when

### Verdicts are withheld outside the Action Phase

Rule 516.2 makes the Action Phase the only one whose contents the player
chooses. During Awaken/Beginning/Channel/Draw they are following a fixed
script, and reporting a verdict on every card they touch while doing it
buried the instruction they were following under things like "Nothing to do
for Chaos Rune."

`GamePhase.validatesPlayerMoves` is the gate. During the fixed phases the bar
says what to **do**.

### The status strip sits beside End Turn, not above the cards

Above the cards it pushed the whole row down when there was something to
report and back up when the message aged out — the bottom of the window
moved while the player was reading it. Beside End Turn it uses ground that
was already empty and the row holds one height either way.

It always renders something: with no progress to report it falls back to the
current phase's instruction, so the area never looks broken.

### Message shape

Headline says what happened; detail says what is owed.

> **You've played Tibbers.**
> Turn it sideways and exhaust 2 runes.

One sentence carrying both — name, colon, list — read as a label rather than
something to act on. The detail does not repeat the card's name; "turn
Tibbers sideways" under "You've played Tibbers" reads like a second card.

Say the destination, not just the verb: **"return 1 Chaos rune to your rune
deck"**, not "recycle 1 Chaos rune". *Recycle* is rules vocabulary (594) that
reads as *discard* to anyone who hasn't memorised it.

### `LegalityValidator.Failure` is switched exhaustively

Never add `default:` to those switches. A new rejection reason must fail the
build until someone writes player-facing words for it — with a `default:` a
**rejection** renders as "Action accepted", which is the worst possible
failure for this app.

Rejections are phrased as what to do about it, never as the case name.

---

## 5. Traps that have already cost time

**A missing asset and a slow one look identical.** Card art rendered as black
rectangles for a long time. The cause was the App Sandbox denying network
access (`com.apple.security.network.client` was missing after sandboxing was
added) — but it stayed invisible because the two-closure `AsyncImage`
collapses "loading" and "failed" into one placeholder, and both placeholders
were dark fills. Always split the phases. `CardArtView` does.

**Loose files in the app folder are not resources.** `Group 14.png` sat
beside the sources and would have loaded as nothing at runtime. Only the
asset catalogue and the synchronized groups reach the bundle. After adding
an asset, verify it compiled in rather than trusting a green build:

```bash
xcrun --sdk macosx assetutil --info "<App>.app/Contents/Resources/Assets.car" | grep YourAsset
```

**Judge stance against printed orientation, never the bounding box alone.**
Use `TrackedObject.stance(knowing:)`. Battlefields are printed *landscape*,
so shape alone calls them permanently exhausted — which made the Awaken
phase impossible to finish, since it waits for nothing to be exhausted.

**`type` is authoritative; `supertype` is a tag.** `supertype: "Champion"` is
the champion tag and sits on both Legends and Champion Units. Reading it
first classified every Legend in every deck as a Champion, and the app told
players to move a Legend out of the Legend zone — permanently.

**Don't mutate a `@Model` in a per-frame path.** `BoardStatePersistence`
assigned `lastSeenFrame` before its own `changed` guard, dirtying SwiftData's
change tracking for every card several times a second and making long
sessions slower than short ones. The guard has to come first.

**Cap every diagnostic buffer.** `unrepresentableZoneEvents` and
`visionTrace` answer "what just happened"; an unbounded answer is a leak.
Both share `ExpertSystemAdapter.diagnosticBufferLimit`.

---

## 6. Working style for UI changes here

- **One source of truth per fact.** The worst bug in this project was two
  `ObjectTracker`s on the same detections, so the IDs on screen and the IDs
  on disk were different numbers for the same card. Before adding a second
  anything, check whether the first can be shared; if it can't, write down
  why at the declaration.
- **A type earns its size by having one reason to change.** Past ~300 lines
  for a view, or ~50 for a function, look for the split. When a type's stored
  properties fall into groups that never read each other, that's the seam.
- **A comment naming a limitation beats a workaround hiding it.** Several
  real bugs here were found only because the previous limitation was written
  down where it bit.
- **Screenshots can't be taken from the agent side.** macOS app UI changes
  are verified by build and by reading the composition, not by eye. Say so
  rather than implying it was seen, and expect a round trip on anything
  positional.
