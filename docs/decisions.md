# Decisions

The spec's open questions, and what they were resolved to. Each of these was
marked non-blocking or answerable by assumption, so each was taken rather than
escalated. Any of them is cheap to revisit; the note is here so that revisiting
is a decision rather than a rediscovery.

## Glow colour: per-habit accent

**Question.** One fixed app-wide glow colour, or an accent per habit?

**Decision.** Per habit, chosen from six accents when the habit is created.

A row becomes identifiable by colour before you read its name, which matters on
a screen whose entire job is to be read at a glance. The cost is that the glow
render is cached per colour as well as per size, which is a slightly larger
cache and nothing else.

## Icon: a curated SF Symbols set

**Question.** Emoji free-text, or a curated SF Symbols set?

**First decision.** Emoji, capped at two characters, on the grounds that it was
less work.

**Now.** A curated set of SF Symbols, grouped into four sections.

Emoji renders at whatever weight and colour the font vendor chose. It ignores
the habit's accent, ignores Dynamic Type's optical sizing, and sits next to
system typography looking like a sticker. A symbol inherits all of it and takes
the accent colour, which ties the label to its row.

Nothing had to migrate. The stored field was a string before and still is:
`HabitSymbol.isSymbol` decides whether to draw it as a symbol or as text, so a
habit created with an emoji keeps it.

## 1x and 7x per week: neither is selectable

**Question.** Does the frequency picker expose 7 as a valid N? Does a one-pill
row look broken?

**Decision.** The picker offers 2 through 6.

7x a week is `daily` wearing a different hat, and having two ways to express
the same cadence means two rows that behave identically but render differently,
which is a bug waiting to be filed. 1x a week is a single pill spanning the
whole track, which reads as a progress bar rather than as a habit slot.

This is enforced by construction rather than by the picker: `Frequency(timesPerWeek:)`
normalizes anything at or above 7 to `.daily` and clamps anything below 2, so a
degenerate cadence cannot exist even if it arrives from a future sync or a
future edit screen.

## Week rollover: clean reset

**Question.** What happens to a frequency habit's pills when the week rolls
over with the goal unmet? The spec assumed a clean reset and asked for
confirmation.

**Decision.** Clean reset, no carry-over. This is invariant R7.

Taken as assumed rather than escalated, because the alternative contradicts the
concept: the glow means "still actionable today", and a debt carried from last
week is not actionable today in any sense the grid can express. Carry-over also
needs somewhere to display it, which is a second thing on a screen whose whole
argument is that it only shows one.

The implementation makes this automatic rather than a rule to enforce: slot
state is computed from the completions falling inside the displayed week, so
last week's are not consulted at all. `WeekGridTests` covers it.

## Appearance: follow the system

**Question.** Not in the spec's list. It arrived from the implementation, twice.

**First decision.** Dark, always. The glow layer was an opaque JPEG, and an
opaque tile only disappears into its background if the background is the black
it was drawn on.

**Now.** Whatever the system is set to.

The constraint was real but the conclusion did not follow from it. The tile is
still opaque, because the PQ encoder drops alpha whatever it is handed. But
clipping the tile to the slot's own capsule removes its corners entirely, and a
shape with no corners needs no particular colour behind it. The earlier worry
that clipping would flatten the HDR layer was never measured; it does not.

Dark is still where the glow reads best, and it is still what the app looks
best in. That is now the user's choice rather than the app's. See
[glow.md](glow.md).
