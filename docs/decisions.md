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

## Icon: free-text emoji

**Question.** Emoji free-text, or a curated SF Symbols set?

**Decision.** Emoji, capped at two characters.

Less implementation work, as the spec noted, and it lets the user pick anything
without a picker to design or a symbol set to curate. If a curated set is ever
wanted, the stored field is a string either way, so it is a UI change and not a
migration.

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

## Dark mode only

**Question.** Not in the spec's list. It arrived from the implementation.

**Decision.** The app is dark, always.

The spec already leaned this way for Phase 3 on the grounds that the glow reads
better on a dark background. It turned out to be structural rather than
aesthetic: the glow layer is an opaque JPEG, because JPEG has no alpha and
because compositing an HDR layer with a blend mode risks it being flattened to
SDR. An opaque tile only disappears into its background if the background is
the black the tile was drawn on. See [glow.md](glow.md).
