<!--
NOT an official document. `core-rules.md` and `how-to-play.md` are verbatim
extractions of Riot's published PDFs and must never be edited to match the
code — they are the citation source this engine is built against, and the
only independent check on whether it is right.

This file is the opposite: the decisions *this project* made where the
published rules are silent, ambiguous, or describe something a camera can't
see. Every entry says what was decided and why. If one of these ever
conflicts with core-rules.md, core-rules.md wins and this entry is a bug.
-->

# House rulings

Riftbound's rules describe a game between people who can ask each other
questions. This app watches a table through a camera and has to decide
things a judge would settle out loud. These are those decisions.

Grouped by whether they're **table practice** (how the game is actually
played, which the rules underdescribe) or **engine simplifications** (real
rules not yet fully modelled, kept honest rather than hidden).

---

## Table practice

### The player-facing turn is five phases, not eight

Rule 517 defines an End of Turn Phase with Ending, Expiration and Cleanup
steps. All three are real, and `TurnSequencer` runs all three. But a player
*does nothing* in any of them — no triggers to declare, no cards to touch —
so presenting them as steps to click through asked for three screens of
acknowledgement every turn.

`GamePhase` (the app's, in `RiftboundVision`) therefore stops at `.action`,
and ending the Action Phase hands over directly to the next Awaken.

> **Decided:** the app shows Awaken → Beginning → Channel → Draw → Action.
> The engine still models 517 in full.

### A spell is laid in the base, then binned

Rule 150 says a spell "creates a game effect according to its instructions
and is then placed in the Trash." Read literally, a spell never occupies a
board zone at all.

At a table it does: you put the card down where both players can read it,
pay for it, resolve it, and only then sweep it away. The app follows the
card rather than skipping to the end.

> **Decided:** a spell is expected in the base first, and asked for the
> trash **after** its cost is paid — not alongside it. Asking for both at
> once would have the player bin the card before turning the runes that paid
> for it, leaving nothing on the table to explain the runes.

### Playing a card is a sequence, and it blocks

The rules treat paying costs as part of the process of playing (557–561),
without saying what happens if a player stops halfway. Physically they stop
halfway all the time.

> **Decided:** a played card opens a `PendingPlay` holding the Action Phase
> open until the card is turned sideways (139.4), its energy runes are
> exhausted (157.2.a), and its power runes are returned to the rune deck
> (157.2.b). A second card is refused meanwhile.
>
> **Why blocking:** a half-paid play is a board the engine and the table
> disagree about. Every action stacked on top inherits that disagreement,
> and by the time it surfaces there's no telling which move went wrong.

### Verdicts are withheld outside the Action Phase

516.2 makes the Action Phase the only one whose contents the player chooses.
During Awaken, Beginning, Channel and Draw they are following a fixed script
(515).

> **Decided:** the app judges moves only during the Action Phase. In the
> fixed phases it says what to *do* instead. Commentary on each card touched
> while following a script buries the instruction being followed.

### The local player takes the second turn

The app has one seat. 645.7 gives the player going second an extra rune on
their first Channel Phase, and `GameState.turnOrder` with one entry cannot
express "there is another player and they went first."

> **Decided:** `playerGoesSecond` defaults to true, so the opening Channel
> Phase asks for 3 runes and every one after asks for 2. The arithmetic is
> delegated to the engine's `RuneChannelPace` rather than restated.

### A contested battlefield scores nobody at Hold

630.2 scores a Hold for a battlefield you *Control*, and 181.4.b says a
player keeps Control while an opponent contests it. The camera can see which
units are present; it cannot see who held it first.

> **Decided:** a battlefield with both players' units present scores nobody,
> and the app says "contested" rather than guessing. Awarding it either way
> would be a coin flip presented as a ruling.

### Draw is confirmed by the hand, not the deck

515.4.b draws 1. A deck is a stack — the detector sees one object on top of
it however many cards are underneath — so a card *leaving* the deck is
invisible.

> **Decided:** the Draw Phase completes when a card arrives in the hand
> zone. Main Deck → Hand is the only way a card gets there during that
> phase. The same reasoning applies to Recycle: it's confirmed by the rune
> area shrinking, not the rune deck growing.

---

## Engine simplifications

Real rules, not yet fully modelled. Listed so they're findable rather than
discovered.

| Rule | What's simplified | Consequence |
|---|---|---|
| 577.3 | The two rune abilities resolve immediately instead of using the Chain | Putting "add 1 energy" on the Chain would need a full pass-around before the energy existed to spend |
| 563.2 | `applyPlay` pushes Spells onto the Chain but resolves Units and Gear immediately | Reaction (725) and Legion (724) timing against a Unit entering play isn't real yet |
| 626.1.d | Damage assignment is a deterministic order, not a player choice | Tank-first (626.1.d.1) and lethal-in-full (626.1.d.2) constrain it enough that this is faithful for now; "assign me last" effects are not modelled |
| 634–639 | No Layers: combat and Cleanup use printed Might | A buffed or debuffed unit fights at its printed value; Assault, Shield and Deflect don't apply |
| 627.2 | Both-sides-survive is unreachable | Needs Shield or Deflect — the arithmetic is at `Combat.resolve` |
| 632.2 | Score abilities don't trigger | Waits on effect execution |
| 520/522/523 | Three Cleanup steps are no-ops | Wait on Layers and effect execution |

---

## How to add to this file

An entry belongs here when the code does something a careful reader of
`core-rules.md` would not predict. Say what was decided, and say *why* —
the reason is the part that survives when someone revisits it. If the
answer is "we haven't built it yet," it belongs in the simplifications
table, not as a ruling.
