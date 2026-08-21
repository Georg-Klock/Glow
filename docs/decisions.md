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

## 7x per week is not selectable. 1x now is.

**Question.** Does the frequency picker expose 7 as a valid N? Does a one-slot
row look broken?

**Decision.** The picker offers 1 through 6.

7x a week is `daily` wearing a different hat, and having two ways to express
the same cadence means two rows that behave identically but render differently,
which is a bug waiting to be filed. That part has not changed.

**1x was excluded and is not any more** (2026-08-20). The objection was that a
single shape spanning the whole track reads as a progress bar rather than as a
habit. Under the design the app now follows, a met goal *is* a single shape
spanning the whole track, so the thing that made 1x look broken is the same
thing that makes every completed week look right. The design file also seeds a
1x habit, which settled it.

Enforced by construction rather than by the picker: `Frequency(timesPerWeek:)`
normalizes anything at or above 7 to `.daily` and clamps anything below 1, so a
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

## One editor, and the kind decides the screen

**Question.** Both screens create habits now. Does the editor differ by the
screen that opened it?

**Decision** (2026-08-21). There is **one** editor, `HabitEditorView`, and a
habit's *kind* decides which screen it lives on — never the screen it was made
on. `Habit.countedPerDay` and `countedPerWeek` sort every habit by its
frequency, so switching an existing habit from Per Day to Per Week moves it
from Today to This Week, carrying the days it has already been logged on.
Verified by doing it.

The one thing that varies by entry point is **which side the toggle starts on
for a new habit**: Today opens on Per Day, This Week on Per Week. That is a
default, not a second editor. The alternative — always starting on Per Week —
is more obviously neutral, and was rejected because adding from Today would
then default to making something that appears on the other screen, which is a
worse first tap than a pre-selected segment the user can see and change.

Worth knowing when reading the code: nothing about the editor is per-screen
except that one parameter. If a second thing ever becomes per-screen, this
decision is the one being reopened.

## Seeded history: a Settings toggle

**Question.** A fresh install seeded ten weeks of invented completions so the
grid could be judged with something in it. Issue #3 offered two ways out: gate
it behind `#if DEBUG`, or clear it on first edit.

**First decision** (2026-08-20). The gate: real installs opened empty, Debug
builds kept the demo past.

**Now** (2026-08-21). A toggle in Settings, asked for directly. Every install
— Debug included — opens with the habits and an empty grid, and the invented
past goes in and out on demand. The gate's flaw was that it left untracked
invented data in Debug builds that nothing could remove; the toggle is one
mechanism with a full contract: `DemoHistory` records what it seeds by id and
removal deletes exactly that, never a completion the user logged themselves,
even on days the demo also filled.

Today is never pre-filled, as always. Each habit's past is rebuilt from its
own id, so off-and-on-again shows the same demo; the first habit's past is
perfect so a full streak is on screen, and the rest cycle down so a missed day
is too.

## The breath: in, then out

**Question.** Should the open glow pulse, so a live day reads as live?

**First decision.** Yes, asked for directly: the glowing layer's opacity eased
between 85% and 100%, 1.2s each way — shallow on purpose, to catch the eye in
peripheral vision rather than blink at anyone. Reduce Motion switched it off.

**Now** (2026-08-21, #46). Removed, as a reversal rather than a fix — the
breath worked as designed. The app has exactly one signal, and that signal is
brightness, not movement. The glow already says *still open* by being brighter
than white; pulsing said the same thing a second time, in a register nothing
else in the app uses — everything else is a state, drawn once, that changes
only when you change it. The breath was also the only element that moved on
its own, and it could not do that for free: it is what walked Today's rings
sideways (#45), and its removal is what lets the widget and the app agree that
a lit mark holds still. The measurements it produced — the compositor does not
flatten an animated HDR layer, and `.animation(_:value:)` reaches everything
beneath it — are kept in [glow.md](glow.md).
## The rest day: permission, then prohibition

**Question.** What does the rest day mean? `WeekPreferences.restDay` arrived
as a day nothing was expected on.

**First decision.** Permission. The comment in `WeekGrid.dailySlots` said it
out loud: never open and never missed, but a completion logged on one still
counted — "resting is permission, not a prohibition."

**Now** (2026-08-21, #39). Prohibition, as a reversal. A rest day is true
rest: nothing can be logged on it, nothing un-logged, and the week is not made
up around it — you trust that you will do it next week, and ideally the phone
stays down too. Permission to skip is not the same thing as being asked to
stop, and only the second one is restful. The refusal lives in
`HabitStore.toggleCompletion` (`.refused`), the write path the app and the
widget's intent share, so a stale widget surface cannot write around it.
Frequency rows stop with the day: nothing opens and nothing glows on it.

What does not reverse: a completion already stored on a rest day still draws
and still counts — a record of what happened stays a record of what happened —
and per-day habits are untouched, because water and a walk are bodily and not
the thing the rest is from. The grid marks the cut as one vertical line down
the rest day's column, in the missed cross's grey.
## Two greys, on purpose

**Question** (#7). The grid's unlit text is `GlowPalette.labelResting`; the
system-control screens — Settings, the editor, the pickers — use `.secondary`.
Two answers to "what colour is text that is not shouting": unify, or accept?

**Decision** (2026-08-21). Accepted, and documented as the answer rather than
carried as a cleanup. The grid is the design file's surface and takes the
file's grey, which also has to survive the widget's accented rendering as
stored alpha; the system screens are built from `List` and `Form`, and a
system control tinted with a custom grey stops looking like the system. The
border between the two greys is the border between "designed here" and
"designed by Apple" — a real line in this app, worth keeping visible. The
same reasoning already governs type: the grid's sizes are the file's 12pt
scaled (#32), the system screens keep the system's text styles. Full
rationale in [design-system.md](design-system.md), "Outside the grid".

## The widget's background is not the app's to keep

**Question** (#53). Every widget should sit on pitch black, in every home
screen appearance. Under Default it does. Under Tinted and Clear the system
drops the declared background and substitutes glass, and the marks stop reading
as lit and start reading as bright shapes on a photograph. The issue proposed
`.containerBackgroundRemovable(false)` on all four configurations, knowingly
paying for it with StandBy, the iPad Lock Screen gallery and foreground
tinting.

**Decision** (2026-08-21). Not taken, because it does not work. The flag was
added to all four configurations, built, installed and read on screen: the
widget renders on glass under Tinted and on the wallpaper under Clear, exactly
as before. On iOS 26 `containerBackgroundRemovable` governs contexts that have
no background at all; the Home Screen appearances are a restyling and are not
one of them. Only the cost was real.

The obvious second attempt fails too. A black image drawn as *content* behind
the view, carrying the `.fullColor` accented rendering mode that keeps the glow
tile from being flattened, is dropped as completely as the declared background
is — run in red, it never appeared. Under Tinted and Clear the system keeps the
silhouette of the marks and nothing else, halo included: today's ring has its
glow under Default and is a bare white circle under both of the others.

So the appearance stays the person's choice, and it stays a real cost rather
than a solved one. What reopening this needs is a mechanism, not a second
opinion. The measurements are in `GlowWidget.swift` and `GlowImageCache.swift`
so that the flag is not tried a third time.

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
