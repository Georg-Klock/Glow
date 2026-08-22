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

What does not reverse: per-day habits are untouched, because water and a walk
are bodily and not the thing the rest is from. The grid marks the cut as one
vertical line down the rest day's column, in the missed cross's grey.

Where that line starts and stops was settled separately (#71): both ends land
on a habit, never on a gap and never on the edge of the list, and it is drawn
at the span bar's weight rather than the missed cross's. `RestCut` owns both
answers so the app and the three week widget families cannot disagree. See
SPEC.md, "How the cut is drawn".

**One clause did reverse, later** (2026-08-21, #72). A completion already
stored on a rest day was said to "still draw and still count". It still
*counts* — nothing is deleted, `completedDays` is untouched, weekly totals are
untouched, and History still shows it — but the week grid stops drawing it, and
so does the rest of the column: no socket, no ✕, nothing. The reason the
original clause was right, that a record of what happened stays a record of
what happened, is satisfied by the count and by History. The week grid's job is
to say what is open, and on a rest day that is nothing — so `SlotState` gained
a fifth case, `.rest`, which is not the same as `.inactive`: a socket says one
is coming, and here none is. It wins over `isDone`, which is what makes "counts
but is not drawn" a single rule rather than two that can disagree.
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
scaled (#32), the system screens keep the system's text styles.

## The code is the source of truth for design

**Question** (#66). Two documents published the numbers the app draws:
`docs/design-system.md` (every colour, type size, radius and effect) and
`docs/widget-large-spec.md` (1,282 lines measuring the large-widget frame
through the Figma Plugin API). Both had drifted. Generate them from the code,
or stop keeping them?

**Decision** (2026-08-21). **Stop keeping them. Both are deleted.** The code
that draws a thing is the only description of it.

The drift was not carelessness, it was structural. Almost nothing the app
draws is a stored constant: the slot is `194 / (7 + 6·24/35)` at runtime, the
ring's stroke is `3/35` of that, and every drop shadow is then multiplied by
`GlowSettings.haloScale(peak)` — 1.7 at the shipping default. So a documented
value could be a faithful record of the design file and still not predict a
single pixel. The tables published `17.5`, `1.5` and `9`; the app renders
`17.4550`, `1.4961` and `15.26`. Anyone building from the docs got numbers
close enough to look right and wrong enough to fail a diff, which is the worst
of both.

Generating the tables from code was the alternative, and it was rejected as
the wrong shape of fix: it keeps a second artefact in step with the first at
the cost of a script, a CI check and a committed file, to serve a reader who
could have read `GlowPalette`. The rationale that was *only* in prose moved
into the code beside the value it explains — the accented-rendering argument
for storing hierarchy in alpha, the two effects of the design container that
are deliberately not reproduced, the Today ring's borrowed ratios, and the
open question of whether `.fullColor` survives a Tinted home screen.

What replaces them where a document genuinely helps:

- **The frame itself**, committed as a 2x PNG in `RenderTests/DesignReference/`,
  with the render diff comparing the shipping view against it. An artefact
  cannot drift from itself, and the harness reports rather than asserts.
- **This file**, for decisions.
- **`docs/glow.md`**, for the HDR engineering and its negative results — that
  is measurement history, not a design spec, and it stays.

Recoverable from git if this turns out to be wrong; the deleting commit is the
one that carries this entry.

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

## labelHalo is a radius, and the doc was quoting a blur

**Question** (#63). A design document's effects table stated its own convention
— a Figma shadow radius is roughly half a CSS blur and roughly equal to a
SwiftUI `.shadow(radius:)` — and then two of its seven rows did not follow it.
It published 1.5 and 2 for the due label and today's letter; `GlowPalette`
computes 0.75 and 1.0. Is the doc wrong, or is every glowing label in the app
under-blurred by half?

**Decision** (2026-08-22). The doc was wrong, and it is already gone.

The two cases are not inconsistent, they are read from different quantities.
`haloRadius` and the ring's radii were taken from the file as *Figma shadow
radii* and are used undivided, because a Figma radius is about a SwiftUI radius.
`labelHalo` and `headerHalo` were taken as *CSS blurs at 2x*: halve for 1x,
halve again to get from a blur to a radius. The table quoted the 1x blur for
those two rows and the radius for the other five — one column, two quantities.

This is the same arithmetic the project has already got wrong once in the
opposite direction, halving numbers that were already halved and landing every
glow at a quarter of its reach. The rule that separates the cases is whether the
source number was a blur or a radius, and **nothing about the value itself says
which** — so it is now written at the two lines it governs rather than in a
table.

**What would reopen it.** 0.75pt against 1.5pt of blur on 12pt text is not
something a simulator can settle: it has no EDR headroom, and the halo is
exactly the part that needs it. If a due label ever reads under-lit on a device,
the thing to suspect is that the file's number was a radius after all and one of
the two divisions is spurious. That is a device observation, not an argument,
and it is the only thing that should move these numbers.

## An empty Monday is not a failure on Tuesday — until it is

**Question** (#82). `SlotState.missed` was documented as daily-habits-only: for
a habit due a number of times a week, an empty Monday is not a failure on
Tuesday, because the week is still winnable. Does a weekly row ever miss?

**Decision** (2026-08-22). Yes, and the old rule is **bounded rather than
reversed**. The week is still winnable right up to the point where it is not.
Once a rep has no day left to land on, the row says so.

The test is **strict**: a rep is lost when `repsLeft > actionableLeft`, not
`>=`. On Saturday with two reps owed and Sunday still live, both are still
reachable and the row stays clean; the ✕ arrives on Sunday. This is the whole
character of the mark — it reports a miss that has *become unavoidable*, and it
is never a warning and never a prediction. A mark that appeared while you could
still act would be the app telling you it expects you to fail.

**The design file is a day ahead of this**, and the rule wins. Its last row
shows the ✕ on Saturday of a week with no rest day, where `2 > 2` is false.
Recorded here so the next reading of the file does not re-derive the loose
inequality from the mock.

The same number governs the month: `MonthGrid` asks `WeekSpans` how many reps a
week lost and crosses that week's unlogged **past** days. It used to decline the
verdict — "a week already lost is a judgement this grid does not invent" — and
it still does not invent it; it asks. The strictly-past condition is the same
rule again at day resolution: a lost 3×/week week on Saturday has still not lost
Sunday.

## The Today ring's grey was the outlier

**Question** (#75). SPEC §1 says every completion glows. `SlotMarkView` sends
`.doneToday` and `.donePast` straight to `GlowImageView` and always has —
`DayRingView` instead painted logged arcs `GlowPalette.labelResting` grey. One
of the two was wrong.

**Decision** (2026-08-22). The ring was. **Light marks the habit, open or
closed; what stays dark is what never happened.** A completion is a thing that
happened, so it glows, and the Today ring was the last surface saying otherwise.

The rule the grey was reaching for is real and survives: brightness must not
mean *well done*, or the app becomes a machine for congratulating you. But the
corollary is not "a completion goes dark" — it is that **light cannot also be
what separates open from done**, because it is already carrying something else.
So *shape* carries that distinction instead, which is what the week grid has
always done: a ring for a slot open today, a dot for one already logged. The
Today ring now does the same thing at its own shape — an outlined band for a
repetition still open, a line for a logged one.

`CLAUDE.md`'s opening paragraph said the glow "is not a reward for finishing"
and the ring was built to match it. Both are corrected. What is *not* corrected
is the sentence after it — every mark still means one thing, and the app still
has exactly one signal; that signal is just "this happened" rather than "this is
outstanding".

The gap halved with it, from two band widths to one, and that is not taste: the
old number was one width of clear space *plus* one for round line caps, which
extend a stroke half its width past each trim endpoint. A pill is bounded
exactly by its own start and end angles, so there are no caps left to pay for.

## A weekly row says when, not just how much

**Question** (#47). A habit due fewer than seven times a week drew as N spans
that lit or went dark together. That says *how much* is left; it says nothing
about *when* anything happened. The proposal: the line stops being the light,
and the days carry it.

**Decision** (2026-08-22). Taken, with the issue's five open questions answered
here rather than left in the code.

**Seven positions or N?** N spans, keeping the geometry they already have, with
day-pinned dots over them. Seven positions joined by lines would make an
N-times row indistinguishable from a daily one and throw away the span
vocabulary; and it would undo #81 and #82, which had just made the row draw
exactly N of them, honestly, however late in the week it is.

**What colour is an achieved span?** The issue worried, correctly, that putting
an achieved span in the missed grey puts a success and a failure in the same
colour. The answer avoids the question: an achieved span draws **the same line
an upcoming span already draws**, because they are the same thing — a share of
the week with no ask left in it. No new grey, no third state. The row is the
week divided into N, and light where days happened.

**What happens before the goal is met?** The open span still glows. That is not
a third state: it is the same rule #75 settled for the Today ring — light marks
the habit, and *shape* separates open from done. A lit dot is a day that
happened; a lit outline is the day still asking.

**Completions past the goal?** They light their day. `WeekDots` reads
completions and never reads `target`, so a fourth completion on a three-a-week
habit lights its Thursday even though it has no span. The row is a record of
what happened, not of what was owed.

**Does #4 dissolve?** Not entirely, and it is left open. Its stakes drop a long
way — the open span's boundary stops being the thing the row is read by — but
the boundary is still drawn, so where it falls is still a question somebody
could answer differently.

What this costs: R5 and SPEC §6 both said an N-times row is not day-pinned, and
half of that is now false. Amended rather than deleted — the *spans* are not
day-pinned and the *dots* are, and saying which is which is the whole change.
No model change and no migration: `Completion.day` has been stored and
normalized since the first version, and `WeekGrid.frequencySlots` was simply
counting the completions and throwing the weekday away.

## The span rule stands, and the mock has a sixth slip

**Question** (#4). `WeekSpans` divides the week for a habit due N times a week,
and the rule was read off the design rather than specified. The file does not
agree with itself: five of six spanning rows across two large-widget frames
follow the rule, and one — Early night, two a week, nothing done, today Tuesday
— spans Mon–Wed where the rule gives Mon–Tue.

**Decision** (2026-08-22). The rule stands. The mock is wrong in that row.

Three things point the same way, and none of them is "the code is easier".

The **same row in the other frame**, on a Friday, follows the rule exactly:
Mon–Fri, which is "through today", where the Tuesday frame shows an even split
of seven into two. One row doing both in two frames is a slip, not a rule.

**Matching it would break a different row in the same frame.** Touch Grass, in
the Tuesday frame, follows the rule; a division that produced Mon–Wed for Early
night gives the wrong answer there. There is no rule that satisfies both, which
is the definition of a file contradicting itself.

And the file has **four other self-contradictions already on record**, so a
sixth is a likelier reading than a rule nobody has been able to state.

**#47 lowered the stakes rather than settling it.** With the lit dots carrying
the record of *when*, the open span's boundary is no longer what the row is read
by — it is structure. Where it falls decides less than it did when this was
filed, which is why closing it as decided is now cheap. If the design ever wants
the even-split reading, the place to change is `WeekSpans.divide` and the thing
to check first is Touch Grass.

## The open ring has no fill

**Question** (#65). `GlowPalette.ringWash` — a 1% white — was declared and never
applied. The design file gives the open ring a `#FFFFFF` @ 1% fill; the code
draws it with `Capsule().strokeBorder`, which paints a border and no fill, so
the wash has never been on screen in any release. Wire it up, or delete it?

**Decision** (2026-08-22). Deleted.

Three things pointed the same way. The document that specified it no longer
exists — see "The code is the source of truth for design" above, and a token
kept alive only by a deleted document is a token with no argument left. The
ring's interior is *deliberately* clear rather than incidentally so: the glow
modifier masks its HDR tile with the view it wraps, and a mask reads alpha, so
any fill inside the glowed layer lights the interior instead of leaving it dark
— which is the opposite of what a ring is. And the one real problem that
interior has, halo bleed from the neighbouring marks making it read grey rather
than black, is fixed by black drawn *beneath* the glow, never by white inside
it. A 1% white is the wrong sign for it.

What this is not: a claim that the design file was wrong. A 1% wash on a
`fill`-then-`overlay` construction is a coherent thing to ask for. It is a claim
that the app does not draw the ring that way, has not for its whole life, and
gains nothing by starting.

The risk this closes is the one the issue names: a declared-but-unapplied colour
is exactly what gets "restored" by the next person reading a design file, after
which nobody can say whether the change was a fix or a regression. The comment
left in `GlowPalette` where the token was says so.

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
