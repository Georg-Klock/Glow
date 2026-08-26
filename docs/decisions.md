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

> **Superseded** (marked 2026-08-25, #288). The app committed to one glow
> colour for every habit — see "Two colours, both opaque" (#111, 2026-08-22)
> further down, and the note on `Habit.accentRaw`, which is retained unread
> only so the schema does not change. The text above stands as the record of
> what was decided when the question was first taken.

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

## The Dynamic Island may say well done, because it is not a mark

**Question** (#58). When a goal is met, the Dynamic Island says so — a short
glowing line, then it goes away. SPEC §3 lists celebratory flourishes as a
non-goal, and this is one. The issue offered two ways out and said the choice
had to be made before it was built.

**Decision** (2026-08-22). **Route 1: the pop is not a mark.** SPEC §3 gains a
bounded exception rather than §1 being rewritten.

The non-goal is about the surfaces that *record state* — the grid, the rings,
the widgets — and about keeping one signal in one register on them. The pop is
outside all of them, lasts two seconds, and records nothing: no streak is
counted, no badge is kept, and the grid is identical whether it fired or not.

Route 2 was to rewrite §1 so that light may also mean *well done*. Declined,
and the reason is the same reason #75 was decided the way it was: the app has
one signal, and it already means "this happened". Giving it a second meaning on
the surfaces that carry it is the change that would actually cost something —
and it is not needed to put words in the Island.

**Two things were measured rather than assumed.**

The Island **does not render an activity while its own app is in the
foreground**. So a goal met inside the app fires a pop nobody sees, and the case
the feature exists for is a goal met from the *home screen*. That inverts the
issue's framing, where the widget case was "the hard one" — it is the only one.

`LiveActivityIntent` **does not bring the app forward**. That was the property
in doubt, because the whole point of `ToggleHabitIntent` and `TapHabitIntent` is
that they never leave the home screen. Both now conform, and a widget tap still
leaves the Home Screen in front, with the intent's own log line proving it ran.

**Still unmeasured: whether it glows.** The pop uses the same `glowing` modifier
and the same PQ tile as everything else, and whether that survives the Island's
rendering needs a device. This project already wrote the widget off as unable to
glow on exactly this reasoning — a separate process that archives its render —
and that was wrong when it was finally measured, so the assumption is not being
made in either direction. The answer belongs in glow.md when there is one.

## The container gradient is refused, permanently

**Question** (#87). The design file draws the widget's container as a near-black
gradient, about `#08080D` at the corners. The app draws pure black. Which is
right, and what stops the file's version coming back?

**Decision** (2026-08-22). Pure black, permanently, and this entry exists mostly
to stop the reversal.

The glow is a claim about light against dark, and every level the ground sits
above zero is a level taken off it. On a home screen that matters most, because
the wallpaper is right beside it: the gradient was followed for a while and read
as a *panel sitting on* the wallpaper rather than marks floating on it.

**The reversal is baited.** `RenderTests/DesignReference/README.md` records that
the ~13-level container difference alone accounts for most of an **84%**
render-diff against the design export. That number is a standing invitation to
"fix" the diff by re-adding the gradient, and the diff would indeed collapse. It
would be a regression wearing a green number, which is exactly why the harness
has no pass/fail threshold and why this is written down.

`GlowPalette.widgetBackground` is declared as `Color(.sRGB, 0, 0, 0, 1)` rather
than `Color.black` for the same reason — `Color.black` is a system colour and
free to be something other than zero. Nothing caught that before; a test does
now, along with a pixel sweep of all five widget families.

**What the halo does is not a violation.** A lit mark spreads white onto the
ground on purpose. On the small Today family the ring's halo reaches 46.6pt and
covers a 158pt frame corner to corner, so its corners read 1,1,1 with the glow
up — and 0,0,0 with it down, which is how the sweep tells the two apart rather
than loosening a tolerance until both pass.

**Not settled here: Tinted and Clear.** They substitute glass for the declared
background, and #53 records that the substitution cannot be opted out of. That
is a different question from this one, which is about what Default renders.

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

## vision.md is kept in sync, dated, or deleted

**2026-08-22.** #75 reversed the Today ring's rule — open and done are now both
lit, separated by shape — and corrected `CLAUDE.md`, `README.md`, `SPEC.md` and
`DayRing`'s own comment. `docs/vision.md` was missed, and kept saying "at the
goal the ring is quiet… the glow is what is still open, never what is
finished".

An ordinary stale doc line is a small debt. This one was not, because of what
`CLAUDE.md` says vision.md *is*: "the target… where the code disagrees with it,
the code is the backlog." A reader who found that paragraph was being told to
restore the grey. That is the same failure #65 closed for `ringWash` — a
declared intent nobody can date, faithfully re-implemented as a regression.

So the rule is now written into the document's own opening: a document that
outranks the code is kept in sync, dated, or deleted. It carries a revision
date, and the paragraph explains why the date is load-bearing rather than
decorative.

Two other sections were checked rather than assumed, which is what turned up
the rest of the drift: "Habits gain a second kind — which the data model does
not have today" had landed, and the "Deliberately later" section still deferred
export, which shipped in #23. Both are corrected in place rather than deleted —
the value of the list is what the vision *asked for*, and a target with nothing
left to hit is worth being able to see.

## The week row's dots get one voice, not six

**2026-08-22.** #47 put a lit dot on each day a weekly habit was logged, which
is the whole *when* of the row. VoiceOver could not reach any of it: the dots
are `GlowImageView`s, hidden from accessibility from the inside, drawn in an
overlay with no label of its own. A sighted reader got which days; a VoiceOver
user got what the row said before #47 existed.

**One element for the run**, not one per dot. The dots are one fact — a list of
days — and the row already carries up to six span elements announcing how much
is left. Six more stops saying "logged Tuesday", "logged Friday" would make the
row longer to swipe through in order to say something a single sentence says
better. `WeekDots.spokenDays` builds it, so the app and the widget cannot
disagree about it any more than they can about which dots to draw.

**No button trait**, matching the rest slot from #72: the dots carry no
`actionDay` and nothing there is tappable. Editing the past is a different
question and not this one.

**The list's locale is the calendar's, explicitly.** A bare
`.list(type: .and)` takes the *process* locale, so the days were named out of
an en_GB calendar and then joined by en_US rules — measured as "Monday,
Wednesday, and Sunday". Naming and joining now come from the same place.

**What could not be verified here.** The intended check was VoiceOver in the
simulator, swiping the row. VoiceOver does not engage there: the Accessibility
toggles ignore automated taps, and setting `VoiceOverTouchEnabled` with the
cache notifications and a respring leaves it off. What was verified instead is
the string, against the real types and including the rest day's absence from
it, and that wrapping the dots in a `ZStack` to hang the element on moved
nothing on screen — a full-screen diff of the two builds is 3160 pixels apart
at one level out of 255, which is render dither and not a dot that shifted.
The spoken result on a device is untested.

## The pop fires from the home screen only

**2026-08-22.** The Dynamic Island does not render a Live Activity while its
own app is in the foreground. Measured when #58 landed: requested from inside
the app, `Activity.request` succeeds and `chronod` subscribes an Island
renderer with the right metrics, and the Island stays a plain pill until the
app is backgrounded.

So the app's own two call sites requested an activity, drew a Lock Screen
presentation, showed nobody anything, and ended it two seconds later. Nothing
harmful — but a feature whose entire content is two seconds on screen should
not have a path that spends them on nothing.

`GoalPopCentre.popIfMet` is now called from `TapHabitIntent` and
`ToggleHabitIntent` and nowhere else. Those run in the app's *process* but not
in its foreground, because a widget tap happens on the home screen — which is
precisely where the pop is visible. The rule is therefore "the intents", not
"the widget".

**Two alternatives, both declined.**

*Keep it, for the case where someone meets a goal and immediately swipes home.*
Real, and narrow. It keeps the rule at one line — "a goal met fires a pop" —
at the cost of that line being false almost every time it runs.

*Gate on foreground rather than on caller*, so the rule matches the measured
condition exactly and covers a Shortcuts run too. `UIApplication.shared` is
unavailable in app extensions and `Glow/Store` is compiled into the widget
target, so this needs a static the app updates from `scenePhase` — mutable
global state introduced to fix two cosmetic seconds. Not worth it. The
narrow case it would additionally catch is a habit logged through Siri while
the app is open.

**Not pursued: giving the app its own acknowledgement.** The app already has
one — the ring closes, the label dims, the row goes quiet — and adding a second
would reopen SPEC §3, which was amended once already to allow this much.

Structurally there is nothing to test: the guarantee is that no view calls
`popIfMet`, which is a property of the call graph rather than of a value. The
note on the type is what carries it.

**Both directions were measured on screen.** A goal met by tapping the week
widget on the Home Screen expands the Island to "you did it / Early night", and
the app process logs `pop: you did it`. The same goal met by tapping the same
habit on This Week logs nothing at all — no request, no refusal — and the row
simply closes.

Getting there needed a temporary probe, because the first attempt produced no
pop and no reason for one. `popIfMet`'s three conditions were traced and all
three came back true — `enabled=true met=true auth=true` — with the pop
following on the next tap. The first attempt had gone to a process that was
one second old, launched by the intent immediately after an install. Worth
knowing before reading a single silent run as a broken feature.

## One pop at a time, whose words change

**2026-08-22.** #58 gave `GoalPopAttributes` a `habitID`, on the reasoning that
a second goal met while the first pop was still up should queue as its own
activity rather than replace it. That was a guess, and #102 asked for it to be
measured. Two per-week habits were each put one tap from their goal and both
were tapped from the week widget.

**What was measured.** ActivityKit does not refuse the second request — both
activities run — and it does not queue them either. The Island renders only the
newest. So the first habit's line was drawn, immediately hidden behind the
second, and ended two seconds later on a timer nobody saw start. Its Lock
Screen presentation was rendered for the bin.

**One activity, updated.** The attributes are now empty and a second goal
`update`s the running activity's content. The same thing on screen, with one
session and one timer — and the outcome becomes this app's decision rather than
a side effect of how the Island stacks activities, which is undocumented and
could change.

`PopWindow` is the part that can be wrong, so it is pure and tested: every pop
takes a number, and only the newest may end the activity. Without it the first
tap's ending would land two seconds after *its* tap and close a pop the second
goal had just refreshed.

**Why the third option is not just more work — it is unsafe.** #102 offered
"queue deliberately", extending the first pop so the second gets its own two
seconds. Trying to observe an overlap needed a longer window, and at 30 seconds
the pop stopped ending at all. The reason is in the log: `willExpireAssertionsSoon`
followed by `Firing background task expiration handlers`, 26 seconds after the
intent ran. **A pop's ending depends on the process that requested it still
being alive**, and a widget tap's process is a background one that is not.

At two seconds that is comfortably inside the assertion. Anything that stretches
the window walks toward a cliff, and past it the activity is never dismissed and
sits on the Lock Screen as exactly the notification-shaped thing
`dismissalPolicy: .immediate` exists to prevent. Two seconds is now a
correctness bound, not only a taste one.

That also caps what can be verified here. The guard's *live* behaviour — the
first ending arriving while a second pop is up — cannot be observed in this
setup: the taps cannot be driven closer than about 2.4s apart, and the window
cannot be widened without crossing the cliff above. The logic is unit-tested;
what was seen on screen is the second goal logging `(replacing)` and the Island
carrying its new line in the same activity.

## Every control states its own tint

**2026-08-22.** `CLAUDE.md` already carries this trap for one control — "a root
`.tint()` beats `role: .destructive`" — and #124 found it on a second. The
three `Toggle`s in Settings never stated a tint, so they inherited the root's
white.

Which is worse than arbitrary here. White is what this app reserves for *lit*,
and a switch track is not lit; the ON track was measured at pure 255,255,255,
the same value as a completion. The Glow slider one section above already
carries an explicit `.tint(GlowPalette.color)` that is a no-op today — it exists
so the colour is a statement rather than an inheritance. The toggles now do the
same with `GlowPalette.grey`.

**The check that mattered was direction, not colour.** A toggle's whole job is
to read as more-on than off, and Apple's OFF track is a system colour this app
has never touched — so a grey chosen for text could in principle land *below*
it and invert the control. Measured on screen, ON against OFF:

| | ON track | OFF track |
| --- | --- | --- |
| before | 255, 255, 255 | 90, 90, 94 |
| after | 181, 181, 183 | 90, 90, 94 |

Twice the OFF track's brightness. The direction holds, and the value is
`GlowPalette.grey` over the row rather than a number invented for this control.

**Note for #111.** That issue would collapse `GlowPalette.grey` to an opaque
`#171717`, which composites near black and would take this ON track from 181 to
roughly 23 — below the untouched OFF track at 90, which inverts the switch. This
call site is one #111 has to look at, and the number above is what it has to
beat.

## The Settings preview scrolls, and a shadow's reach is not its radius

**2026-08-22.** #91 fixed a clipped halo by lifting the glow preview out of the
`Form` and pinning it above one, which cost the preview its scrolling: two views
in a `VStack`, only one of which moves. #109 asked for the untested half of
#91's reasoning to be settled before designing around it.

**Both halves were wrong, and in the same direction.**

*A `Form` row does not clip content that fits.* Put back as the first section
with `.listRowInsets(EdgeInsets())` and a clear row background, the halo renders
exactly as it does outside — profiled down the capsule's centre column, the
falloff reaches black at the same distance in both layouts.

*What clipped it was the reservation being short.* #91 derived the padding from
the same expression the halo is drawn from — `height × haloRadius ×
maxHaloScale`, 34.97pt — and treated that as the halo's size. It is the
`.shadow` **radius**: the blur is still painting well past it. Measured at 12×,
from the capsule's edge to the last pixel above black: **237px at 3.0 px/pt =
79pt**, against a 34.97pt radius — 2.26×. The old reservation cut the light at
exactly the radius, which the profile shows as the falloff dropping from 34 to 0
in one step instead of fading.

The reservation is now `radius × haloReach`, with `haloReach = 3` — the usual
figure quoted for a Gaussian's visible extent, the next round number above what
was measured, and its margin costs black on black. Verified uncut at 1×, 6× and
12×.

**The navigation bar took two attempts.** The preview scrolls under it now, so
the bar has to be opaque or the capsule shows through.
`.toolbarBackground(Color.black, for: .navigationBar)` renders black and
**silently removes the title**, large and inline both — a real trap, since it
compiles and looks deliberate. `.toolbarBackground(.visible, for: .navigationBar)`
alone, over this view's own black background, gives the same black and keeps the
title: a column down the left edge reads 0,0,0 straight through the bar and past
its boundary.

Leaving the bar alone was the alternative and it is worse than it sounds: the
system material dims the capsule to grey and prints "Settings" over it, so the
product's one lit object slides under the title as a smear. Both were
screenshotted before choosing, which is the only reason the choice is defensible.

## Every width a row hands out is a width

**2026-08-22.** The suite passed while logging
`Invalid frame dimension (negative or non-finite)` at test-host startup, and
`RowGeometry` had an arithmetic path straight to it (#136).

`nameMaxWidth` is a *difference*, not a product: `labelWidth + labelGap -
iconWidth - iconGap`. Every other value on the type is a positive constant times
a scale that cannot go below 1, so they were safe by construction and this one
was not. A narrow proposal squeezes the label column to nothing and the result
goes negative — **−13.5pt at `totalWidth == 0`**, which is the first pass of
every `GeometryReader` — and straight into `.frame(maxWidth:)`.

Two floors, and neither is defensive padding. `nameMaxWidth` is clamped because
it is the one subtraction. The initializer's width is clamped because
`.infinity` and `.nan` both arrive through layout, and a `.nan` propagated from
here surfaces three properties later in a frame modifier that names no source.
Non-finite collapses to zero rather than to a screen-sized number, so the
failure mode is a row with no room rather than a row scaled to infinity.

The tests sweep sixteen proposals — zero, narrow, ordinary, oversized, negative,
both infinities and `.nan` — and assert every exposed value is finite and
non-negative, named so a failure says which. Run against the unfixed code they
report exactly the values the issue predicted: `-13.5`, `-13.08`, `-9.3`, `inf`.
One more test pins the ordinary case, because a floor that also flattens a real
layout would pass the sweep and fail the app.

## An export is defused, and it does not outlive its share sheet

**2026-08-22.** Two separate holes in the same feature (#142), both in the gap
between "this is text" and "this is text somebody else's software will act on".

**A habit name can be a formula.** The CSV escaped RFC 4180 syntax and nothing
else, so a habit called `=1+1` — or something less playful — arrived in a
spreadsheet cell as a program. The name is the *only* user-controlled field in
the row: the date is formatted and the cadence, target and count are ours, so
this is the single place a person's own text becomes a cell.

`HistoryExport.defused` prefixes an apostrophe when the first significant
character is `=`, `+`, `-` or `@`. Two details are the whole of it:

- **Leading whitespace is dropped before the test.** Excel discards it and then
  decides, so ` =1+1` is still a formula and a check on the raw first character
  misses exactly the case worth defending against.
- **The apostrophe goes in front of the whitespace**, because it only does
  anything as the cell's first character.

The cost is that the apostrophe stays in the data, and that is the right way
round: a cell reading `'=1+1` is mildly wrong, one that evaluates is a
vulnerability. **JSON is deliberately untouched** — a parser has no notion of a
formula, so there is nothing to defuse and an apostrophe there is just a wrong
name.

**The file outlived its purpose.** The export was written into the temporary
directory and never removed, so a full history sat on disk after the share sheet
had gone. Not a breach of the feature's promise — the file never leaves without
a tap — but exactly the kind of leftover that promise exists to rule out.

`ExportStore` owns a subdirectory, and that scoping *is* the safety property:
sweeping means deleting, and a sweep of the temporary directory itself would
reach files this app never wrote. `discard` refuses any URL whose resolved
parent is not the store's own folder, so neither a symlink nor a `../` can point
it elsewhere. `write` sweeps first, which is the fallback for the one case no
dismissal handler covers — being killed while the sheet is up.

Cleanup hangs off `sheet(item:onDismiss:)`, because sharing and cancelling are
the same event as far as the file is concerned and treating them as two is how
one gets missed. The URL is held in its own state rather than read back off the
sheet's item: `sheet(item:)` clears its binding **before** `onDismiss` runs, so
a handler that asked the item for the URL would find nil every time and delete
nothing.

Verified in the simulator, both ways round: export → cancel leaves zero files,
export → complete (Copy) leaves zero files, and the folder the file lands in is
the store's own.

## A blank row is a position, not an identity and not a general-purpose slot

**2026-08-22.** #129 and #143 are one change, because they land on the same two
functions and fixing either alone leaves the other's reproduction working:
`addHabit`'s reuse of a blank row, and `delete`'s conversion into one.

**The identity had to be retired.** `delete` cleared a habit's name, icon,
cadence and completions and left the row behind — keeping its `id`. Widget
configurations and widget intents both resolve by `id`, so the row was a live
handle to a habit that no longer existed: a configured widget could silently
start showing an unrelated new habit, and a tap from a snapshot WidgetKit had
not yet replaced could write a completion that later belonged to whoever filled
the row. `delete` now assigns a new `UUID`, and so does the reuse in `addHabit`.
Retiring the id is what makes both stale references resolve to nothing, which is
what a deleted habit should be.

**And the store now refuses the write rather than trusting the caller.** A blank
row takes no completion of any kind, and a per-day habit takes no day toggle —
a ring is not a row of days, and one tap there means *one more*, not *done*.
This is the rest day's argument again, and it generalises: the widget is a
second process drawing a surface that can outlive what it draws, so a rule
enforced by not offering a button is not enforced.

**Blank rows belong to This Week.** They are layout — a position in the week
grid so habits can be clustered — and Today has no blank-row layout at all, a
fact SPEC already stated for the add button. Yet `addHabit` filled the first
blank row whatever the cadence, and `delete` blanked every row whatever the
cadence. So adding a Today habit deleted a gap somebody had placed on a screen
it never appears on, and deleting one inserted a gap there. Now only weekly
rows take or leave a blank row; per-day rows append and are removed outright.

**No migration, and that is a decision rather than an omission.** A blank row
created by deleting a per-day habit is indistinguishable from one placed
deliberately — `delete` zeroed the cadence, so there is nothing left to read.
Treating every existing blank row as deliberate is the only safe reading, and
it is also the one that preserves whatever layout someone has arranged.

**One test bug worth keeping in mind.** The first version of "a new habit has a
new id" compared `second.id` to `first.id` and failed with the two equal — not
because the fix was wrong, but because a SwiftData object is live rather than a
snapshot: `first`, the blank row and `second` are the same instance, so
`first.id` afterwards asks the *new* habit for its own id. The value has to be
read before the delete.

## The trace's privacy claim is now a property, not a comment

**2026-08-22.** `WidgetTrace`'s own doc comment said it records "habit IDs,
entry counts and timings. Never a habit's name, never anything a person typed."
Four call sites interpolated `habit.name` straight into a line — both widget
providers and both entity queries — and `Tools/pull-widget-log.sh` exists
precisely to carry the result to a Mac (#141).

A diagnostic that quietly collects what a person typed is worse than no
diagnostic. A comment claiming it does not is worse still, because it is the
thing a reader checks instead of the code.

**The id was always the better record anyway.** Every question this trace was
built to answer is *whether the right habit reached the provider*, and an id
answers that; a name only answers it by accident, and only while no two habits
share one. `WidgetTrace.tag` and `WidgetTrace.resolution` are the spellings now.

**The enforcing test reads this repository's own sources.** No unit test of
`record` can make this claim true — the type cannot see which substring of a
line was somebody's habit — so the test walks `Glow/` and `GlowWidget/` from
`#filePath` and fails on any `WidgetTrace.record` call with `.name` in it,
naming the file and line. Reintroducing the old call site reproduces exactly
that failure. It also asserts the scan found files at all, because a source scan
that finds nothing passes vacuously, which is the failure mode of every test
like it.

**The Lock Screen decision, made rather than inherited.** The Live Activity is
the one surface here a locked phone shows, and it prints a habit's name — which
is whatever a person typed, and can be a great deal more revealing than
"Workout". The name is now `.privacySensitive()` in both the Lock Screen
presentation and the Island's expanded one. The line beside it is ours and says
nothing personal, so a locked pop still reads as an acknowledgement; it just
does not say what of.

The Home Screen widgets are deliberately **not** marked. They are only visible
on an unlocked phone — this bundle declares no accessory families — so redacting
them would cost the week grid its labels and buy nothing.

## Both executables carry an audited privacy manifest

**2026-08-22.** The repository had no `PrivacyInfo.xcprivacy` at all, and both
targets use `UserDefaults`, which is a required-reason API (#132).

**Audited, not copied.** Every required-reason family was searched for across
both targets: file timestamps, disk space, system boot time, active keyboard,
pasteboard. None of them appears. `UserDefaults` is the only one, and it is used
two genuinely different ways, so both reasons are declared and both are true:

- `1C8F.1` — the App Group's defaults, which is how the app and the widget share
  the glow level, the week preferences, the pop switch, the tap burst and the
  trace.
- `CA92.1` — the app's own defaults. `HabitSeeder` records the first-run seeding
  in `UserDefaults.standard`, and `GlowSettings` falls back to it if the group
  container is ever unavailable. The seeder is gone (#228) and the reason is
  not: `DailyHabitMigration` records its sweep there, the Low Power notice
  records that it has been shown, and the fallback is unchanged. Both manifests
  name the writers they actually have.

A manifest that over-declares is as wrong as one that under-declares, so the
test asserts the family count as well as its contents.

**`NSPrivacyCollectedDataTypes` is empty, and that is a product statement.**
Nothing is uploaded, synced or sent anywhere; there is no `URLSession` and no
Network framework in either target. History leaves the device only through the
share sheet, on a tap, to wherever the person sending it chooses.

**The appex needs its own.** An extension is independently shipped and the app's
manifest does not cover it — and it is the one that is easy to forget, because
the app's is what a reviewer looks at first.

**Two guards, and the stronger one is not the test.** The manifests are listed
*explicitly* in `project.yml` even though `xcodegen` would pick them up from the
directory anyway. That redundancy is the point: deleting either file now fails
`Tools/generate.sh` outright —

    Spec validation error: Target "GlowWidget" has a missing source directory
    ".../GlowWidget/PrivacyInfo.xcprivacy"

— before anything builds. The tests cover the other direction, reading the
**built** `.app` and every `.appex` inside it rather than the repository,
because a manifest that exists in the source tree and does not reach the shipped
bundle is exactly this issue wearing a different hat.

## The reload lives next to the write, and coalesces

**2026-08-22.** "Call `reloadAllTimelines()` at the call site" kept being
forgotten (#134). Swipe-delete and reorder both saved without one. So did the
week's first day and the glow level, which are not model writes at all but do
change what a widget draws. A widget then showed an order, a row or a set of
columns that no longer existed, until something unrelated happened to reload it.

**So the reload moved next to the write.** Every committed write in `HabitStore`
now goes through a private `commit()` that saves and then invalidates. A new
write path cannot forget, because forgetting means not saving. The view-layer
reloads that followed a store write are gone; the ones that do not follow one —
the two intents, the seeder, the demo history, and the three preferences — say
so themselves and say why.

**A refusal still invalidates nothing**, because nothing was saved. The intents
ask separately in that case, and deliberately: after a rest-day refusal the
widget's surface was stale *before* the tap, which is how the tap happened.

**Coalescing is the other half.** One gesture is often several writes — a
reorder rewrites `sortOrder` on every row — and requests made in the same turn
of the main actor become one reload, so the reload count is proportional to
gestures rather than to rows. Whether that also helps the delay measured in #121
is untested and not claimed here; this is about correctness, not latency.

**`WidgetKind` is one source for four strings.** A kind is a persistent
identifier: WidgetKit stores it against every widget a person has placed, so
renaming one orphans their widget rather than renaming it. Spelled out at each
`StaticConfiguration` *and* wherever a reload names a kind, the two drift and
`reloadTimelines(ofKind:)` quietly does nothing. Each widget's `kind` now reads
from the enum, so there is no second spelling; the test pins the raw values,
which is the part a rename would break for people who already have the widget.

**And the week grid observes the week's first day.** `WeekCalendar` read the
preference, so the value was correct — but a value read only inside
`WeekCalendar` is a dependency SwiftUI cannot see, and the grid kept its old
columns until something else redrew it. Read in `week`, the same way
`HabitRowView` reads the rest day.

## Demo seeding stays on the main actor, and the number is why

**2026-08-22.** #125 proposed moving `DemoHistory.seed()` and `.remove()` off
the main actor into their own `ModelContext`, on the reasoning that 400–500
inserts inside one SwiftUI transaction is a freeze. The shape of that is right.
The cost is not what it assumed.

Measured on disk, both operations, median of five, in one process:

| habits | completions | seed | remove |
| --- | --- | --- | --- |
| 8 (today's default) | ~240 | **33ms** | **33ms** |
| 20 | ~610 | 82ms | 82ms |
| 40 | ~1210 | 165ms | 165ms |

Linear, and at the shipping habit count it is a third of a frame budget's worth
of hitch rather than a freeze. #123 would take the default to 13 habits, which
lands around 55ms.

**So it stays on the main actor for now**, and the reason is not that the
refactor is hard. It is that the refactor's own key risk is unverified: #125
notes that *when* a background context's committed save becomes visible to a
live `@Query` is a timing question this codebase has never exercised, and every
existing cross-context case in this app is cross-*process* and routes through an
explicit reload rather than a query noticing by itself. Trading a 33ms hitch for
an unverified refresh path is a bad trade. It stops being one somewhere north of
~500ms, which on this curve is about 120 habits.

**A busy state was considered and dropped.** While the write is synchronous
there is no turn of the run loop in which a spinner could be seen, so it would
be a control that renders one state forever.

## Two timings from two `xcodebuild` runs are not a comparison

**2026-08-22.** The measurement above nearly produced a change that made things
worse, and the way it did is worth recording.

Scoping `remove`'s fetch with a predicate instead of fetching every completion
and filtering in Swift is obviously better — cost proportional to what the demo
added rather than to the whole record. Measured across two separate
`Tools/test.sh` invocations it first looked like a large win (572ms → 275ms at
20 habits) and then, on the next pair of runs, like a large regression
(83ms → 293ms).

Both were artefacts. `seed`, whose code did not change at all, reported 34ms in
one run and 103ms in another — a 3× spread on identical work. Machine state
between `xcodebuild` invocations dominates everything being measured here.

Run in **one process, alternating**, the two strategies are indistinguishable:
82 vs 86ms, 165 vs 165ms, 33 vs 35ms. So the change was reverted, having bought
nothing.

This is the same lesson as the pixel-scanning script that produced three code
changes chasing a four-point baseline error. A timing comparison in this
codebase is only a comparison when both arms run in the same process, alternated,
and reported as a median.

## A cached relationship array is not a source of truth

**2026-08-22.** Three crash reports from one session, all the same frame:
`_InvalidFutureBackingData.getValue` under `Habit.completionCounts`, under
`snapshot()`, under `WeeklyGridView.grid` (#145).

SwiftData fetches a to-many relationship once and caches it on the model
object. Reading `.day` on an element whose row has since been deleted trips a
`precondition` *inside SwiftData* — a hard trap, not a Swift error, so nothing
in this codebase could have caught it.

**The rows go out from under it because two processes write this store.** The
intents open their own `ModelContainer` against the same App Group file, and
nothing tells the app's context to re-fetch when the widget's deletes a
completion. The app tells the widget about every write it makes; the reverse
path does not exist and never did — `GlowStore`'s own comment said "SwiftData
handles the concurrent access", which is true of the file and not of anybody's
fetched objects. That comment is corrected.

`completionCounts` and `completedDays` now fetch through the context instead. A
fetch cannot hand back a row that is already gone, which **sidesteps
cross-process invalidation rather than requiring it** — the complete fix is a
change-notification path, and whether SwiftData exposes persistent history the
way Core Data does is not established here. It should be its own investigation
rather than this crash's blocker.

They fall back to the cached array when there is no context to ask, which is a
model object built but never inserted — a fixture, where the array is the only
truth there is.

**Two in-process contexts reproduce it exactly**, which is what made a
cross-process crash testable at all. Against the unfixed model the suite does
not fail, it *dies*:

    SwiftData/BackingData.swift:1039: Fatal error: This model instance was
    invalidated because its backing data could no longer be found the store.

— the same file and line as the crash reports. Anyone reverting to check should
expect an aborted run rather than a red test.

One test covers the other direction, which never crashed and so was never
noticed: a completion *added* by the other context was equally invisible to the
cached array, and the fetch fixes both.

## How often the Island speaks is a preference, not an invariant

**2026-08-22.** #119 reverses a decision this project stated twice, and it is
the repository owner's call, made deliberately. Both statements are kept and
marked superseded rather than deleted, because they are the argument anyone
will re-derive from first principles.

`GoalMet` said:

> firing on every completion would put twenty of these a day on a screen whose
> whole argument is that it says one thing.

**What that got wrong is the screen.** A pop is not on the screen whose argument
is that it says one thing. It is two seconds over the Dynamic Island, on the
home screen, and it leaves nothing behind — no streak, no badge, no change to
the grid. The one-rule invariant is about the surfaces that *record state*, and
this records none. So its frequency is a question about how often a person wants
to be spoken to, which is a preference.

Settings has three positions: **Never**, **Goals**, **Everything**. Goals is the
default and is exactly what "on" always meant — the stored `1` still maps to it,
so nobody's setting changes underneath them.

**Two vocabularies, and that is what preserves what the old rule was protecting.**
The real risk in speaking more often was never volume; it was that the rare
thing would stop reading as rare. So a repetition gets a flat acknowledgement —
"logged", "counted", "got it" — and a goal keeps the celebratory one. They are
drawn at the *same index* from two lists, so the pair a single tap produces
reads as one moment rather than two unrelated phrases.

**The goal-completing tap says both, sequentially inside one two-second window.**
Not one activity carrying two lines: a compact Island state has room for one
short phrase. The routine line holds for 0.7s and the goal line replaces it,
through the same update path #102 established. Splitting the window rather than
extending it is also the safe choice — two seconds is a correctness bound, not
only a taste one, because the process that requested the pop is what ends it.

**A correction says nothing.** Un-logging never reaches the pop at all, because
the toggle path only calls it on `.completed`. The reset of a full ring needed
an explicit guard — it lands in `TapHabitIntent` as a count of zero, and a
"logged" there is the app congratulating somebody for an undo.

**Verified on screen**, all four paths, from the home screen widget:

| setting | tap | log |
| --- | --- | --- |
| Everything | completion, goal not met | `pop: there it is` |
| Everything | completion that meets the goal | `pop: got it`, then `pop: well played (replacing)` 0.73s later |
| Goals | completion that meets the goal | `pop: well played` only |
| either | un-log | nothing |

## The generator is pinned, and the project it writes is verified

**2026-08-22.** `Glow.xcodeproj` is generated, gitignored and unreviewed, so
whatever produced it is part of the build. CI ran `brew install xcodegen`, which
resolves whatever is current on the day; a developer machine resolved whatever
it happened to have. The generated project is a function of `project.yml` *and*
of the generator, and only one of the two was written down.

**XcodeGen is now pinned by digest, not by version.** `Tools/xcodegen.pin`
carries `2.46.0` and the SHA-256 of its release archive;
`Tools/install-xcodegen.sh` downloads it into a gitignored cache, checks the
digest before unpacking, and then reads the version back out of the unpacked
binary — a binary with the right filename and the right `--version` string is
exactly the substitution a pin exists to catch.

**Whatever is on `PATH` is not used, even when it reports the pinned version.**
An earlier draft took it as a fast path, which reintroduces precisely the
substitution the digest is there to catch; only the checked bytes generate. It
costs one 4MB download per version, once. Verified by pointing the pin at a
wrong digest: the download is refused and nothing is unpacked.

**The repair stayed; the check that it worked is new.** `generate.sh` rewrites
the `SystemCapabilities` string xcodegen emits into the dictionary Xcode reads.
That repair is a string substitution, so it fixes what it recognises and is
silent when it recognises nothing — which is precisely what a changed output
format looks like. `Tools/check-project.py` now reads the generated project back
through `plutil`, as a property list rather than as text, and **fails the
generation** unless both targets carry the capability as a real dictionary with
App Groups enabled and unless the entitlements file each one names actually
contains the group. A string and a dictionary are indistinguishable to a search
for the key, which is why the old check could not have caught this.

Verified against three mutations: raw xcodegen output with the repair skipped,
the extension-only setting stripped from the project, and the widget's generated
entitlements emptied to `<dict/>`. Each fails, naming the target and the
configuration.

**`Tools/generate.sh` is now the only documented path.** The README told device
users to run `xcodegen generate` directly, which produces a project that opens,
builds, installs, and leaves the widget unable to see the store.

## The widget compiles with `-application-extension`

**2026-08-22.** The widget target compiles four of the app's source folders
wholesale — `Logic`, `Models`, `Store`, `Glow` — which is the right trade for
four folders of value types (see the note in `project.yml`), but it makes the
*folder* the boundary, and folders grow. #107 was this shape already:
`UIApplication.shared` cannot be used from an extension, and
`UIAccessibility.isReduceMotionEnabled` had to be read on the app's main actor
and carried across.

`APPLICATION_EXTENSION_API_ONLY = YES` makes the compiler the boundary instead.

**It surfaced nothing.** The widget compiles clean with `-application-extension`
today; the audit that suspected otherwise was wrong, and the setting is here to
keep that true rather than to fix something. Confirmed both ways: a clean build
of the target shows `-application-extension` on the swiftc invocations, and a
temporary `UIApplication.shared` added to `Glow/Logic` fails the widget build
with `'shared' is unavailable in application extensions for iOS` while leaving
the app build alone. Without the flag the same file compiles into the extension
and fails at runtime as a widget that will not load.

The setting is asserted in `Tools/check-project.py`, so it cannot be dropped
from `project.yml` and rediscovered later, and CI builds the widget target on
its own so an extension-safety failure reads as one rather than as a test
failure.

**What this does not do.** It does not narrow the widget's compile surface. A
new file in `Glow/Store` still joins the extension automatically, and the
compiler only objects if it reaches for API the extension cannot have; app-only
code that happens to be extension-safe — seeding, export, demo history — still
compiles in and still adds to the appex. The `GlowShared` target that would make
that a target-graph error is #139's remaining half and is not done here.

## The migration proves a copy before it adopts one

**2026-08-22.** The move into the App Group container copied the database, the
write-ahead log and the shared-memory file one at a time and logged whatever
went wrong. A sidecar that failed left the database in place at the new path —
and because the next launch tested for exactly that file, the half-copy became
the store forever. It opens cleanly. It is simply missing whatever had not been
checkpointed out of the log yet, which is to say the most recent days (#131).

**A copy is now staged, proven and then promoted.** The complete set goes into
`Migration-Staging/` beside the destination, the staged copy is opened as a real
`ModelContainer` and its habit and completion identifiers are read back, and
only then is it moved into place. Opening it is the validation: a truncated
database, a schema this build cannot read and a file that is not a database at
all all fail there, before anything has moved.

**The order of the moves is the atomicity.** Sidecars first, database last,
because the database file is what every later launch tests for. Cut short before
the last move there is no destination and the next launch simply starts over;
cut short after it, every file is already there. That is as close to atomic as
three files on one volume get without moving the store into a directory of its
own, which would change the store's path for a second time to fix a bug about
changing the store's path.

**A destination without a record is inspected, not trusted.** The record —
`Glow.store.migration.json`, written last, carrying a format version, a
generation id and the counts — is what makes an ordinary launch cheap. Its
absence is the interesting state, because it means either an install migrated
before the record existed or a promotion that was interrupted. So the
destination is opened and compared against the source *by identifier*, not by
count and not by modification date:

- a superset of the source is adopted and recorded — that is a store somebody
  has been using;
- an unopenable one, or a strict subset, is a partial copy: it goes to
  `Quarantine/` and is replaced;
- two stores that each hold what the other does not are **both kept**. Neither
  can be called the later state of the other by looking at it, so the one the
  app has been writing to stays in use and the record names the other for a
  merge that does not exist yet.

**Nothing is deleted, including on success.** The source stays where it is after
a successful migration, and a displaced destination is moved aside rather than
overwritten. Reclaiming that space is a separate decision that can be taken once
a copy has survived more than one launch; taking it here would mean the recovery
path had to be right the first time.

**And a migration that cannot be completed stops the launch.** `makeContainer()`
now throws instead of opening, because the alternative is an empty store created
beside a person's real one — and the moment they add a habit to the empty one,
the two have diverged for good. `fatalError` was the previous answer and it
crash-looped, which from the outside looks exactly like the data being gone.
`StoreUnavailableView` says what happened, says nothing has been deleted, and
offers a retry that re-opens in place. Verified in the simulator: a planted
unopenable store shows the screen, and restoring the store behind it and tapping
*Try again* brings the grid back without a relaunch.

**What the tests are.** `Tests/StoreMigrationTests.swift` works on real files
with live write-ahead logs, because in-memory stores cannot express a bug about
there being three files. The faults are real ones rather than injected hooks: a
sidecar chmodded unreadable so the copy genuinely fails partway, a database file
copied without its log, a stray sidecar left where an interrupted promotion
would leave it. One test asserts its own premise first — that the database file
alone is behind the store it was copied from — so that it fails loudly if
SwiftData ever stops leaving writes in the log, rather than passing on a fixture
that no longer proves anything.

## A run that never reached the tests is not a test failure

**2026-08-22.** `Tools/test.sh` exists because a scheme that runs no tests must
not look like a pass — it asserts a non-zero count for exactly that reason.
This is the mirror image, and it was undefended: a run that failed *before* any
test reported printed "FAILED. Failing assertions:" followed by a graphics
warning, and threw the actual cause away (#148).

The warning is `IOSurfaceClientSetSurfaceNotify failed`, which the simulator
also logs on runs that pass. It was matched only because the grep included a
bare `failed`. So the report named a red herring, with high confidence, in the
one place someone looks when they need the truth.

Three outcomes now, not one:

- **assertions found** — reported exactly as before, `✘` and `error:` and
  `Testing failed:`, no bare `failed`;
- **no test reported at all** — says so, gives `xcodebuild`'s exit code and its
  last thirty lines, which is where the reason lives;
- **tests reported but the run still failed** — says that too, rather than
  claiming an assertion that is not in the log.

**No automatic retry.** It was considered: two agents hit this in one evening,
one of them twice in a row. But a retry that hides a genuinely flaky
environment is the same class of mistake as the message this fixes — it makes
the report say something more confident than the run earns. A named cause is
what lets someone decide whether to re-run.

Both directions were exercised. An invalid `-destination` now reports
`FAILED before any test reported … xcodebuild exited 70 with no test run`
followed by the invocation, where it used to report one graphics warning. A
planted failing test still reports `✘ Expectation failed: 1 == 2` exactly as
before.

## Nothing prominent is styled by the tint

**2026-08-22.** Both "Add Habit" empty-state buttons rendered a **white label
on a white capsule** (#162). `.borderedProminent` fills with the environment's
tint and draws the label in the contrasting colour; `RootTabView` sets
`.tint(GlowPalette.color)`, which is pure white, so the contrasting colour is
white too.

Measured on screen before changing anything, on both tabs: the capsule's
interior sampled **8077 pixels, one distinct colour, 255,255,255** — not one
pixel of a label. After: 236 colours, darkest 0,0,0, **3149 near-black pixels**
where the words are. Identical numbers on Today and This Week, which is what
you would expect from two copies of the same four lines.

Both are now drawn rather than styled — a `Text` in black on a `Capsule` filled
with `GlowPalette.color`, `.buttonStyle(.plain)` — the same shape
`StoreUnavailableView` already used after hitting this in #131.

**This is the third instance of one trap**, and `CLAUDE.md` now says so
generally rather than naming a third control. `role: .destructive` was the
first, `Toggle` the second (#124), `.borderedProminent` the third. The pattern
is not "some controls need an explicit tint"; it is that **a pure-white tint
makes every control that derives a foreground from it invisible**, and the list
of such controls is not knowable in advance.

Not fixed here, and left on #162: whether the root tint should exist at all.
It is there so the Glow slider and the lit marks read as the product's white;
if most controls have to opt out of it, it belongs on the surfaces that want it
rather than at the root. That is a design decision, not a bug fix.

**A third empty state has no button and so no bug**: Settings → History shows
an icon and a sentence. Worth knowing before someone "fixes" it for symmetry.

## The demo's provenance is on the row, and seeding is one save

**2026-08-22.** Two writes that had to agree, in two stores that cannot be
written together (#140). The demo saved its completions and *then* recorded
their ids in the App Group defaults; the default seeder recorded that it had run
and *then* inserted eleven habits one save at a time. Each has a gap, and each
gap is durable: a crash in the first left ten weeks of invented history that
nothing could name — the toggle read as off and the fiction stayed on the grid
for good — and a crash in the second left a partial list under a flag that said
"seeded", so nothing would ever repair it.

**The demo's fix is that there is no second write.** `Completion.demoSessionID`
is `nil` for a row a person logged and carries the seeding's id for a row the
demo invented, and it is saved in the same transaction as the row it describes.
Either both landed or neither did. Removal fetches on that predicate, so it also
takes back a seeding that was interrupted half-way — those rows carry the same
mark as the ones that never got written.

**Exactness is unchanged, and it was the constraint.** Removal still deletes
what the demo added and nothing else, still by record rather than by
recomputing which days "look seeded". The record simply moved to where it cannot
disagree with the data. The one thing it gains: it survives the defaults being
lost, which is exactly the case the old scheme could not survive.

**A session id rather than a flag**, because the id says *which* seeding, and
that is free — one column either way. Removal deliberately ignores it and takes
out everything with any id, so two ids can never strand each other.

**An install that already has a demo is adopted, once.** Its ids are still in
the defaults and nothing is on its rows, so `DemoHistory` reads that list, stamps
those rows in one save, and deletes the key. Dropping the key unread would have
handed exactly these people the bug being fixed. Verified on a simulator: a
store built by the previous build, with three completions recorded the old way,
opens under the new one with the column migrated in, the rows stamped, the key
gone and the toggle reading on; switching it off takes back those three and
leaves the completion logged by hand.

**Seeding is one transaction, and the flag goes last.** `HabitStore.addAll`
inserts the whole list and saves once, and `didSeedDefaultHabits` is written
after that save returns. A failure anywhere leaves an install that is exactly as
it was and a next launch that tries again. The save and the flag are still two
stores and still cannot be atomic, so that one step converges instead: a launch
that finds habits it has no record of seeding records that, rather than adding
eleven more rows to a list somebody is already using.

**The flag stays a Bool.** A seed *version* was the obvious next step and is
refused, because a version that bumps means re-seeding, and re-seeding is the
behaviour that "deleting every habit does not bring them back" exists to
prevent. A changed seed set is for installs that have not been seeded yet.

**And a failed save now rolls back** — in `HabitStore` and in `DemoHistory`
both. A `ModelContext` keeps its pending changes when a save throws, and the next
save from anywhere else in the app commits them, so a write reported as failed
would arrive later, in pieces, attached to an unrelated gesture.

**This is about atomicity, not latency.** The seeding measurements stand and
nothing moves off the main actor. The only timing-shaped change is that the
default seed commits once rather than eleven times, which is not claimed as a
speed-up here because it was not measured as one.

## The date rides on the mark, and a year is counted

**2026-08-22.** #137. A row swiped end to end said "Read, missed" seven times
over. The states were right and the dates were nowhere: the only thing on the
screen that carries them is `WeekdayHeader`, seven letters over seven numbers,
and that is `accessibilityHidden` — correctly, because read aloud it is a table
somebody has to hold in their head while they swipe a row underneath it.

**So the header stays hidden and the date moves onto the mark.** "Read, Tuesday
18 August, missed" is one stop that needs no other stop to make sense of it.
The date goes on all seven columns rather than on the tappable one alone: a
person who stops in the middle of a row should know where they are, and the six
that cannot be tapped are precisely the history this issue is about. `SlotVoice`
builds the sentence for the app and the widget both, the way `WeekDots` does.

**A span is not given a date it does not have.** A habit due N times a week is
not day-pinned — #47 divided the week into shares that say *how much* and put
the *when* on the dots — so a span speaks the day it would act on, which is
today's, and nothing else. Naming the columns it happens to cover would
announce a date the control does not touch.

**A week of columns speaks; a month and a year of them count.** This is #104's
rule about the dots, applied to a longer stretch. Seven dated marks is a row,
and the row is what the app is. Thirty-one is a picture of a month and 365 is a
picture of a year: swiping those one cell at a time is not navigation. The
month widget hangs one sentence on the habit's name, and the year makes each
week column one stop — fifty-two of them, which is also what the grid is drawn
to be read as, since a vertical band there is a good week. Both sentences are
counted off the marks the grid draws rather than off the completions, so the
picture and the words cannot drift apart; `YearHistory` is the year's own
verdict moved out of the view so that the counting has one definition. It is
also cheaper than what it replaced: the fill rule used to rebuild a dictionary
of completion sets, and a `Set` per habit, on every one of 365 cells.

**The widget's row was the tappable column and nothing else.** Today's slot
spoke, the rest day spoke because #72 gave it a voice, and the five columns of
history in between said nothing at all — on the surface most people look at
most often, while the app's identical row said all of it. It says all seven
now. The month widget is the other half of the same decision and goes the other
way, because thirty-one is not seven.

**Reduce Motion reached one animated surface out of four.** SPEC §3 says
"Reduce Motion snaps" and it was written about the Today ring, where it was
true, and about the widget's burst, where it was true — the setting is recorded
at the tap and the timeline carries one still entry (#107). The week grid read
it nowhere: a completion closed on a spring, the row's label dimmed on the same
spring, and a press grew 32% and sprang back. "It is honoured here, so it is
honoured" is how a rule ends up half-applied, and the fix is not four more
`if`s: `MotionPolicy` holds the predicates and all four surfaces ask it.

**The reduced path is the app's own instant path**, not a second one written
for accessibility. Every one of these surfaces already had a branch that draws
the settled truth with nothing scheduled behind it — it is what un-completing,
a day rolling over and an edit all take — and Reduce Motion takes that branch.
A shortened animation would still be an animation.

**What was measured.** The completion, on an iPhone 17 Pro simulator, as
frames: with the setting on, the mark goes 63px to 9px between two consecutive
recorded frames and takes no intermediate size; with it off, the same tap on
the same row draws 63, 57, 49, 41, 33, 9. The screens are unchanged — a
full-screen diff of the two builds on This Week is 4160 pixels apart at one
level out of 255, which is render dither, and on History the two builds are
identical outside the clock in the status bar.

**What could not be verified here.** The spoken result. VoiceOver does not
engage in this simulator: #104 recorded the attempt — the Accessibility toggles
ignore automated taps, and setting `VoiceOverTouchEnabled` with the cache
notifications and a respring leaves it off — and the toggles held out again
here, since Settings' own Demo history switch will not flip under an automated
tap either. What is asserted instead is
the strings, against the real types, including the cases that must stay silent:
a rest day says "rest day" and never "done", a lost rep says "missed" and names
no day, and a month with no cells produces no sentence at all. The declaration
that cannot be observed — that a view honours Reduce Motion — is asserted as a
property of every animating file at once: if it contains `withAnimation` or
`.animation`, it reads the setting. Nothing here has been heard on a device,
and Dynamic Type at accessibility sizes and a right-to-left layout were not
checked at all.

## Two colours, both opaque

**2026-08-22.** #111 replaced the palette's grey ramp with a single opaque
`#171717`. The app draws two colours now: glow white for anything lit, `#171717`
for everything else, and nothing between them.

**What it was.** One grey at `white.opacity(0.553)` and three more derived from
it — the resting label and the weekday letter at full strength, the ✕ at half,
the socket at 16%. Composited on black and sampled off a simulator screenshot:
141, 141, 71 and 23. Four steps for a distinction the app does not make, and in
the widget especially the grid read as a grey scale when the premise is that
brightness means one thing.

**`#171717` is not a new colour.** `0.553 × 0.16 × 255 = 22.6 → 23 = 0x17` — it
is exactly what the socket already composited to. The arithmetic assumes SwiftUI
blends alpha in gamma-encoded sRGB; a linear blend would have put the same alpha
near `#545454`, so it was read off the screen rather than trusted. The socket
samples 23, 23, 23. So the sockets stayed where they were and every other grey
darkened to meet them: label 141 → 23, header 141 → 23, ✕ 71 → 23, span line
23 → 23.

**The five names collapsed to one.** `labelResting`, `headerRest`, `missed`,
`restCut` and `upcoming` were the same value under five names; keeping them
would only have recorded what they used to differ by. The file's own header had
already flagged two of them as one name waiting to happen.

### #53 does not block this, because the grey is a style

The issue said this was blocked on `containerBackgroundRemovable(false)`, and
the reasoning was sound: under accented rendering the system tints every pixel a
single white and keeps only the alpha, so an opaque grey comes out identical to
a lit mark and the hierarchy collapses into one tone. #53 is still open.

What unblocks it is that `GlowPalette.grey` is a `ShapeStyle` rather than a
`Color`. `resolve(in:)` is handed the environment the mark is drawn in, so one
name answers three questions in the one place they can all be answered:

| environment | resolves to | why |
| --- | --- | --- |
| the app, and a `fullColor` widget | `#171717` opaque | the colour the app draws |
| Increase Contrast | `#8D8D8D` opaque | see below |
| accented rendering | white at 55.3% | the only quantity the system has not discarded |

This is not a third colour. It is the same grey expressed as alpha in the one
mode where colour has already been thrown away, and it means the reason the old
rule existed is handled rather than forgotten. #53 remains a live question about
StandBy, the iPad Lock Screen gallery and foreground tinting; it is no longer a
prerequisite for this.

**Measured on a Home Screen, not argued.** The medium week widget was placed and
the appearance switched through all three. Lit dot against socket: **Default
255 / 23**, **Tinted 255 / 149**, **Clear 255 / 162**. The hierarchy survives in
all three, which also confirms that `widgetRenderingMode` really does reach a
custom style's `resolve(in:)` inside a live widget.

### What it costs, and the one mitigation

A habit name that is not due today, and every weekday letter that is not today,
went from 141 to 23 — about **1.1:1** against black, against the 4.5:1 WCAG asks
of body text. That is the intended reading of *what stays dark is what never
happened* carried through to type, and it is a real regression rather than a
side effect.

The answer is to honour the setting rather than to compromise the design:
`colorSchemeContrast == .increased` lifts the grey to `#8D8D8D`, which is
**6.3:1** and is not a number invented for the setting — it is the value
`GlowPalette.grey` composited to before this change. Verified with
`simctl ui … increase_contrast enabled`: every unlit mark reads 141 again, and
141 → 23 when it is turned off.

### The Settings toggles keep the alpha, and the switch does not invert

#124 measured the toggles' ON track at 181,181,183 against an untouched system
OFF track at 90,90,94, and warned that `#171717` would take that ON track to
roughly 23 — below the OFF track, inverting the control. That is correct, and it
is why the toggles do not take the body grey.

A `Toggle` in a `Form` is one of iOS's own components on a support screen, which
is where #111 draws its own scope. The value moved to `GlowPalette.controlTint`,
declared under its own name rather than borrowed from a grid colour it is no
longer allowed to share. Re-measured after the change: **ON 181,181,183, OFF
90,90,94** — unchanged, twice the OFF track, direction holds.

Settings has two `Toggle`s, not the three #124 recorded; #119 turned the third
into a segmented `Picker`.

### The Year is the part that needed a decision

`YearView` drew four levels as four brightnesses — full, partial, empty, future
at 255-with-a-glow, 115, 23 and 9. Two colours carry two of them, and #111 asked
for the carrier to be named rather than picked silently. What it is now:

- **full** — the glow, unchanged.
- **partial** — a white ring. Something happened, so there is light in it; the
  day did not close, so it is an outline and not a dot. That is the app's own
  silhouette rule — a slot open today is a ring, a completion is a dot — applied
  to a day instead of a slot.
- **empty** — a filled `#171717` dot.
- **future** — nothing at all, at the cell's own size. `SlotMarkView` already
  draws a rest day this way and for the same reason: there is no slot here yet.

**A filled white dot was tried for `partial` first, and the render is why it is
a ring.** A year of demo history came out a solid white block: at 10pt cells with
a 3pt gap the only thing separating a full day from a partial one was the halo,
and neighbouring halos close the gap. Collapsing `empty` and `future` to the same
value was also tried on paper and rejected — the year would no longer be able to
say how far through itself it is.

This section is the half of #111 that is a proposal rather than a measurement.
The alternative for `future`, if a blank right-hand side reads as a bug rather
than as a boundary, is a grey dot at less than the cell's width — carrying it on
size instead of on presence.

### What the render tests had to change

Two thresholds in `RenderTests/WidgetRenderDiffTests.swift` were calibrated
against the ramp and would have passed on halo bleed alone afterwards.
`renderIsReal` counted "grey" as anything above 40, which caught a ramp from 23
to 141; it is now a 20–26 band, one level of slack either side of the one grey.
`restCutStartsAndStopsOnAHabit` used a floor of 40 for a cut that composited to
72; it now uses the same `lineFloor` of 15 every other unlit-line scan in the
file already used.

`Tests/WidgetBackgroundTests.swift` gained a suite for the claim itself: that the
grey is `#171717` and opaque, that it is the old socket's value rather than a new
one, that Increase Contrast clears 4.5:1 where the shipping grey does not, and
that the only two values still carrying alpha are the two the app does not paint.

**"Two greys, on purpose" (#7) still holds**, and one clause in it no longer
does: the grid's grey is not "the file's grey, which also has to survive the
widget's accented rendering as stored alpha" — surviving accented rendering is
`GlowGrey`'s job now, not the value's. The decision it records, that the grid and
the system screens keep different greys, is unaffected.

## A test may not poison the machine it ran on

**2026-08-22.** `Tools/test.sh` reported 42 failures on `main` while CI reported
success on the same commit (#168). The cause was not the code and not a race:
`weekRestDay = 7` — Saturday — was sitting in the **simulator's App Group
defaults**, and every run on that device inherited it. A whole weekday vanished
from generated history, so `SeedingTests`, `MonthGridTests`, `WeekSpansTests`
and `WeekDotsTests` went red together.

`UserDefaults` outlives the process. `TestPreferences.withWeek` restores on the
way out, and a process that dies does not get a way out — a crash, a cancelled
run, or a hard trap like the SwiftData precondition #145 is about. Several of
those happened during one long session, and one of them left the value behind.

**Under a test bundle, `GlowSettings.store` is now a private suite**, keyed by
process id and cleared on first use. Nothing a test writes can reach the app's
real defaults, so nothing it writes can outlive it. Production is untouched: no
test bundle, no override.

Proved both ways on the same deliberately poisoned device: **45 failures without
the change, 0 with it.**

**#105 was wrong, and so was the first diagnosis here.** #105 concluded the
hazard was impossible because `parallelizable: false` serialises the suites; the
hazard was never about ordering within a run. Worse, the first attempt at this
entry blamed xcodebuild running the two test targets in parallel, on the
strength of a comparison that looked decisive — five red runs against three
green ones — and the two arms had been run against **different simulators**, one
poisoned and one clean. The flag "fixed" nothing; the clean device did.

That is the third time this project has been misled by its own measurement, and
the rule from the pixel-scanning episode applies unchanged: when a measurement
disagrees, suspect the measurement. Specifically — an experiment that changes a
setting must hold the *machine* fixed, and on this project the machine includes
which simulator `Tools/test.sh` happened to pick.

The first version of the regression test carried the same flaw in miniature: it
asserted the App Group did not hold `7`, which fails on precisely the machine
where the bug was found. It compares before against after now.

## The app edits any day of the week; the widget edits today

**2026-08-22.** R2 read "Only today's slot responds to taps. Past days are never
editable." It was one of the oldest rules here, and it was doing two jobs: it
kept the interaction model at one tap, and it kept the record honest. The first
job is worth keeping on a widget and is a limitation in the app, where the
obvious thing to do with a day you forgot to log is to log it.

**Decision.** R2 becomes a property of the surface rather than of the app.
`SlotEditing` is `.todayOnly` — the widget, its intents, the month grid — or
`.week(allowingFuture:)`, which is the week view and nothing else so far.
`WeekGrid.slots` and `WeekSpans.spans` both take one, with **no default value**,
so a new call site has to say which surface it is instead of inheriting the
permissive answer by forgetting to think about it.

**Why the asymmetry is the point.** A widget is a glance and a single confirmed
action; it renders in another process from a snapshot that can outlive what it
draws, and it has no touch location to resolve a span's column with. The app is
where a record gets corrected. Making both surfaces editable would have been the
easier change and a worse one.

**The future is demo history's, and only its.** Outside the demo you can correct
the past, not claim the future: a completion logged ahead is a claim about
something that has not happened, and the app's one signal is a record of what
did. With demo history in, the whole screen is already an invented past and
painting days ahead is the same job, so the gate is `DemoHistory.isSeeded` — no
new switch. `HabitStore.toggleCompletion` guards it as well as the grid, next to
the rest day's refusal and for the same reason: a surface can outlive the setting
it was built under.

**What a past edit does to the ✕.** SPEC called a lost rep "inert and permanent
for the week". Permanent is now wrong in the app and stays right everywhere else,
and the reason is not that the mark became unstable: logging a day the week had
given up on means the rep happened, late, so `WeekSpans` no longer counts it as
lost. The mark still never changes on its own. SPEC §7 says so in those terms.

**A span writes the weekday under the finger.** A span is not day-pinned, so a
tap on one had to choose between the span's nominal day and the column actually
touched. The column wins: the completion then draws on the day it really
happened, which is already how the month grid and the row's own dots render
these habits. The inverse geometry lives in `SlotLayout` beside the forward
direction, tested as its round trip, rather than as arithmetic inside `SpanView`.
Two fallbacks, deliberately different: the rest column refuses, because
`RestWindow` subtracts it from the shape and there is visibly nothing there to
press; a future column inside the lit open span falls back to the span's own day,
because that part of the capsule is drawn identically to today's column and a lit
shape that ignores a tap is worse than one that does the obvious thing.

**The hit area had to become the slot rather than the ink.** A `Button` takes its
label's drawn shape, and a ✕ is two 1pt bars — so the first build of this made a
past day tappable only within about half a point of the crossing. It had never
mattered, because until now every tappable mark was a ring or a dot filling its
frame. `SlotView` and `SpanView` set `.contentShape(Rectangle())`; measured on
the simulator by tapping a column centre before and after.

**No edit mode, no long press, no confirmation.** Every slot in the week view is
a plain button. A stray tap on Monday changes Monday, and nothing distinguishes a
correction from an original — that is what "edit any day" means, and a mode to
guard it would put the whole screen behind a switch to protect the rarer act.

`Slot.isToday` was an alias for `actionDay != nil`, which was true only while
today was the one day carrying an action. It is a real comparison now; without
it a Monday completion would have started drawing as today's.

Followed by #117, which widens the same case from one week to several.

## The seed set: eight weekly habits in three clusters, five for Today

**2026-08-22.** `DefaultHabits.all` was the design file's list taken literally,
and two things in it had been carried on purpose with a comment saying so: two
rows both called **Touch Grass**, which in a mock shows both row shapes side by
side and in a real install is two rows nobody can tell apart, and **Watch
Sunset** drawn with the `sunrise` symbol because the mock's glyph pointed up.
Both were faithful to a frame nobody is building from any more. The set is
replaced (#123).

**Eight weekly habits, clustered morning / midday / evening** — Gratitude,
Stretch, Read Book · Workout, VO2 Max, Tutorial · Watch Sunset, Early night —
and **five per-day habits** for Today: Sunlight ×2, Protein Meal ×3, Move ×4,
Breathe ×3, Hydration ×8.

**One array, two screens.** The split is not made here. `Frequency` has two
kinds that never share a surface, and each screen asks the store its own
question — This Week and the week widget query `Habit.countedPerWeek`, Today
queries `Habit.countedPerDay` — so the seed is one list in one order and the
sorting happens on the way out. `HabitSeeder` hands whatever it is given to
`addAll`, which is still one save (#140).

**Two blank rows, and they are dividers rather than padding.** Three clusters
need two. The previous set's three were explicitly there to reach eleven, the
large widget's capacity; this one reaches ten and the count is a consequence
rather than a target. Spacers can only ever land on the weekly side —
`countedPerWeek` is `timesPerDay == 0`, which a blank row satisfies and a
per-day habit never does — so the Today five need none of their own, which is
#143's rule seen from the seed's end.

**Hydration changes shape.** It was `.daily`, one check for the whole day; it is
`.timesPerDay(8)` now, which is the cadence something drunk across a day
actually has. It is not the same habit appearing on both screens — it is not in
the weekly eight at all.

**The medium widget spends one of its five rows on a blank row.** Measured on
the home screen rather than reasoned about: the medium family fits five rows and
the cut is hard (SPEC §"as many as fit"), so it shows Gratitude, Stretch, Read
Book, a gap, and Workout — four habits, and the cut falls inside the midday
cluster. The previous set put all three of its blank rows last and so showed
five. This is the documented behaviour meeting a set that groups from the top,
and it is the cost of the clustering: the large family shows all ten rows, and
the medium one shows the morning cluster and the first habit after it.

**Every icon was checked against the generated catalogue** rather than assumed,
and then read off the screen, because the check and the render are different
claims — `figure.yoga`, `dumbbell`, `figure.run`, `play.rectangle`, `sunset`,
`bed.double`, `pencil`, `book`, `sun.max`, `fork.knife`, `figure.walk`, `wind`
and `drop` all resolve in `HabitSymbol`'s `known` set and all drew as symbols on
a fresh install. A test asserts the set membership so a typo cannot reach a
first launch; the screenshot is what says none of them fell back to literal
text.

**On the framing, honestly: there is no single published list of habits jointly
authored by Huberman and Ferriss.** Several picks trace to specific, named
protocols each has separately and publicly discussed — twice-daily sunlight,
VO2 max, sleep timing, gratitude journaling, structured learning. Others —
stretching, reading, resistance training, protein-forward meals, movement
snacks, hydration — are general-wellness areas both cover without one protocol
this set is drawn from. That distinction is the reason the attribution stays out
of the app and out of its code comments: an app should not assert a citation it
does not really have.

**This set reaches installs that have not been seeded yet, and no others.**
`didSeedDefaultHabits` is a Bool with no version in it, for the reason recorded
under #140: a version that bumped would push a new list onto people who had
already arranged the old one.

**Superseded by #228, below.** The set is not pushed at all now — it is offered
on the empty state and arrives on a tap. The question the flag answered stopped
having consequences, so the flag went with the seeder; what replaced it is that
this list only ever reaches a store somebody asked to fill.

## A completion belongs to a day, not to a midnight

**2026-08-22.** `Completion.day` stored local midnight and every lookup compared
those instants by equality, against a calendar rebuilt from `Calendar.current`.
The same civil date is a different instant in every zone, so a completion
logged on 19 August in Los Angeles compared unequal to 19 August in Berlin: the
mark left the grid, and the next tap wrote a second row for a day that already
had one. That is #130.

**`DayID` is the identity now** — year, month, day, no zone — stored as
`yyyy-MM-dd` in `Completion.dayKey`. `Habit.completionDayCounts` is the one
place rows become history, keyed by `DayID`, and everything week-shaped reads a
projection of it onto whatever calendar is drawing. A midnight is still what the
grid compares; it is just no longer what the store remembers.

Measured on a store the app itself wrote, with the app launched under
`SIMCTL_CHILD_TZ`: two habits logged on Saturday 22 in `America/Los_Angeles`,
relaunched in `Europe/Berlin` where the same moment is Sunday 23. The stored row
is `2026-08-22 07:00 UTC` — Los Angeles midnight, not Berlin's — and both marks
stay on the 22nd, in both directions of travel. The same two taps against the
build before this change go dark on the 22nd after the same relaunch.

### The backfill reads a legacy row, it does not guess a zone

A legacy row holds `utcMidnight(D) - offset` for some unrecoverable offset. The
rule is **the UTC midnight nearest the stored instant**, which is D for every
zone inside ±12 hours: Berlin's midnight sits at 22:00 the day before, Los
Angeles' at 07:00 that morning, and both round to the right day.

The alternative — read the instant in the device's current zone — was declined
because it makes a person's history depend on where they are standing when the
app happens to open. Two people with the same history would get different
histories; one person would get a different one depending on which airport they
landed in. Rounding gives the same answer everywhere.

**The limit is stated rather than hidden.** A row written at UTC+12:45, +13 or
+14 — Chatham, Apia, Kiritimati — recovers as the day before, and one at UTC-12
as the day after. There is nothing in the instant that separates those from a
neighbouring day written in Europe. `Tests/DayIdentityTests.swift` asserts both
the eleven zones it gets right and the three it does not, so the limit is a
recorded fact rather than a lurking one.

### The migration is not load-bearing, on purpose

This is the change in the backlog that can destroy a year of somebody's
history, so it is arranged so that no step of it has to succeed.

- `Completion.dayID` infers a missing key with the same rule the backfill
  writes, so an unmigrated store, a half-migrated store and a migrated store
  all show the same history. The widget's read-only container cannot write at
  all, and does not need to.
- `Completion.day` is never rewritten. It is the only evidence a better
  inference would have, so the backfill is reversible in the sense that
  matters: a later build can redo it from the original observation.
- The work is defined as "rows with no key", not as a cursor, so an interrupted
  run leaves the rest for the next launch and a finished one finds nothing.
- Nothing is created or deleted; the row count is checked either side of the
  save, and the keys are proved readable *before* it, while a rollback is still
  possible.
- `StoreMigration.stampDayIdentities` returns rather than throws, and
  `GlowStore.makeContainer` opens the store regardless.

It builds on #131 rather than beside it: the durable record's `format` is the
hook it was described as, now 2, with `dayFormat` and `stampedDays` beside it.
Those two are optional rather than defaulted, and that is not a style choice —
Swift's synthesized decoder does not apply a property's default to a missing
key, so a non-optional addition would make every format-1 record already on
disk fail to decode and read as absent. A store with no record does not gain
one here: the backfill is defined by what is unstamped, not by a file, and
inventing a record would hand `run` a reason to skip work it has not done.

Verified on a real store by blanking every `ZDAYKEY` with `sqlite3` — which is
exactly the shape SwiftData materializes for a store written before the column
— and relaunching in Berlin. The marks were already correct on the first frame,
the record went from `stampedDays: 0` to `2` with its `generation` unchanged,
and `ZDAY` came out of it byte-identical.

### What this cost elsewhere

`HabitStore`'s day lookups now fetch through the context instead of reading
`habit.completions`, which is #145's rule applied to the write path: a stale
cached array on a read was a wrong number, and on a toggle it is a duplicate
row. They filter on `DayID` in memory rather than on a `dayKey` predicate,
because a legacy row's key is empty and a predicate would skip exactly the rows
this is about. Once a store is fully stamped the predicate can be pushed into
SQLite, which is #135's to take — `completionDayCounts` is the seam, and the
migration record is how a caller can know the store is ready for it.

Twenty assertions across five suites had to name their calendar. They were
storing days through `TestCalendar.monday` and reading them back through
`Calendar.current`, and passed only because the raw stored instant was the
identity on both sides. Making the projection explicit is the point of the
parameter.

## How far back the week view reaches (#117)

**Question.** #116 made any day of the visible week editable and left the
visible week as one week. The pager that follows needs a floor: the issue named
three candidates — the first completion on record, `Habit.createdAt`, or an
arbitrary window — and an unbounded pager over `.distantPast` is a scroll with
no end.

**Reopened and changed by #186** — the cap is gone. What follows is the
argument as it stood; the entry at the end of this file says which half of it
was overruled and which half was repaired.

**Decision.** As far back as the record reaches, capped at twelve weeks.
`WeekReach` holds it as two week starts and nothing else. Both halves earn their
place. The record's, because a week before anything existed holds nothing to
correct: a fresh install pages nowhere, which is the truth about it, and the
reach grows with the app's own history. Capped, because the record is not a
bound anybody can feel — and the cap is also what makes the one unusable
candidate harmless, since `Habit.createdAt` defaults to `.distantPast` for every
row written before that column existed. Twelve weeks is a quarter and more than
the ten `SeededHistory` invents, so the demo's whole past is reachable. Further
back the surface is History, which is a year of days and does not respond to
touch on purpose.

**The record is both tables.** `HabitStore.earliestRecordedDay` takes the
earlier of the first completion and the first habit, because the demo writes
completions ten weeks before the habits that carry them and `createdAt` alone
would hide its own past. It is a read on the type that says reads do not go
through it; the exception is narrow and stated there — a `min` over two tables
is not something `@Query` can express without fetching both into a view.

**A past week is editable end to end, stated rather than inferred.** Every day
of a week already over is a day that happened, so all seven columns carry an
action and `allowingFuture` decides nothing — it is a no-op on every week but
the current one. `SlotEditing` did not gain a case: it is about the surface, not
about which week is on screen, and widening the reach was a change to which
weeks exist rather than to what a tap may do.

**Nothing was added to `HabitStore`.** A day three weeks ago is behind *now*
exactly as Monday is, so reaching back is not a new kind of write and the
store's existing guard already covers it. The floor is a bound on navigation,
not on what a record may hold — it is derived from the very record it would be
guarding, and the store's other refusals exist because a widget renders in a
second process from a surface that can outlive its settings. The pager runs in
one process and recomputes its bounds with the record.

**Buttons, not a swipe.** The issue says "swipe back through earlier weeks", and
the rows say otherwise: every one of them already carries `swipeActions` for
edit and delete, so a horizontal drag starting on a row is spoken for. A pager
sharing that gesture would work on the header and on the empty space below the
last habit and nowhere in between. Two chevrons in the leading toolbar instead,
opposite Edit and Add, so nothing new sits over the marks.

**The pager is always drawn and disabled at its ends.** It first hid itself when
there was no earlier week to reach, and then never appeared at all: the reach is
read from the store in a `.task`, so the first render of every launch has none,
the `ToolbarItem` resolved to an empty view, and it was not re-added when the
value arrived. Measured on the simulator — the control showed on one launch and
was missing on the next with identical data. A toolbar item that is sometimes
empty is a toolbar item that is sometimes gone.

**Which week you are on is the title's job.** It names the month of today when
today is in the visible week and of the week's first day otherwise, which leaves
the current week saying exactly what it said before — a week straddling the end
of August still reads "September" on the 2nd. The year appears only when it is
not this one, which paging back a quarter from January reaches. The dates under
the weekday letters carry the rest, and a week with no today in it lights no
column, so no new chrome competes with the marks.

**The ✕ again.** #116 made a lost rep correctable in the week view; a finished
week is where that is sharpest, because every rep it still owed has run out of
days and the row is a completed block plus a ✕ for each of the rest. All of
those columns are now reachable. Nothing about the mark changed: it still never
moves on its own, and logging the day means the rep happened, late. SPEC §7 says
so in those terms.

## A surface reads the days it draws

#135 was written as "stop rebuilding complete history on every calendar and
widget render", and the obvious reading of it is *stop doing it n times* — one
shared pass over the store instead of one fetch per habit. That reading is
wrong, and the measurement is what says so.

Twelve habits with two years each, 8,760 completions, both arms alternated in
one process and reported as medians of eight rounds, over three runs:

| what a list-shaped surface does | median |
| --- | --- |
| one fetch per habit, whole history | 184–194ms |
| one shared fetch, whole history | 179–205ms |
| one shared fetch, bounded to a week | 2.3–2.5ms |

The first two rows are the same number. Grouping *n* habits' rows into one
query saves *n − 1* round trips and spends them again faulting the habit each
row points at, and it still materializes every row there has ever been. **The
cost is the rows, not the queries.** Reading seven days reads seven days.

So `Habit.snapshots(of:within:calendar:)` takes the days a surface actually
draws and `Habit.dayCounts(of:within:in:)` pushes the bound into SQLite. The
week grid passes `week.dayIDs()`, the year its first and last column, the month
widget `MonthGrid.dayRange(containing:)`, Today's rings and the Today widget one
day. `snapshot()` with no range still means the whole history, and the export is
what calls it — the shared pass is not offered without a range, because it
measured no better than the loop it would replace.

**A bounded snapshot holds only those days**, which is the thing to know before
handing one on. That is safe because everything week-shaped counts inside the
week it is given, and `Tests/HistoryProjectionTests.swift` asserts it against
`WeekGrid`, `WeekSpans`, `WeekDots`, `GoalMet`, `MonthGrid` and `YearHistory`
themselves — whole history in one side, the bounded read in the other, same
output — rather than against a reading of their source.

### The predicate does not need to know whether the store is stamped

#130 left this open: "once a store is fully stamped the predicate can be pushed
into SQLite, which is #135's to take, and it needs a way to know the store is
ready for it". It turned out not to. A legacy row's `dayKey` is empty and its
day is inferred from the untouched instant, so the predicate fetches the range
**and every row with no key at all**, and settles those in memory:

```swift
$0.dayKey == "" || ($0.dayKey >= low && $0.dayKey <= high)
```

On a stamped store the empty-key branch matches nothing and the range does all
the work. On an unstamped one it degrades to the scan that was already
happening. Both answer the same, at every point in between, with no reading of
the migration record and so no second thing that can be wrong about it.

### Nothing is cached across renders

The other half of #135 as filed was a cache behind `completionDayCounts`, and
ARCHITECTURE.md said that seam was where one belongs. It is not, and the reason
is #145: `ToggleHabitIntent` and `TapHabitIntent` open their own container
against the same App Group file, and nothing tells the app's context when they
write. A cache the other process cannot invalidate is a wrong number that
survives until something unrelated redraws — which on this app means a
completion logged from the home screen not appearing in the grid. The pass is
shared within one render and dropped at the end of it. That is a cost the number
of habits no longer multiplies, and the bound is what took the rest.

### What this cost elsewhere

The week grid was taking two whole-history reads per redraw, not one: once
mapped over the habits for `RestCut`, and again inside the row loop. It now
takes one bounded read and indexes into it. Today's rings were calling
`snapshot()` per ring to answer a question about one day. The month widget was
projecting every weekly habit's whole history to draw one habit's month, and
both configuration pickers were doing the same to display a list of names —
`TodayStore.perDayNames` and `MonthStore.weeklyNames` read no completions at
all now.

Verified in the simulator, which is where geometry and state are verifiable and
the glow is not: This Week and Today both redraw correctly through a write —
a slot toggled to a filled dot, a two-rep ring filled to a solid circle by two
taps, the label going grey behind it — and History draws the year with today
lit. The widgets' own render was not put on a home screen; their providers call
the same bounded reads the app does.

## A green tick has to mean something

**2026-08-22.** `xcodebuild` exiting 0 says one thing: nothing that ran
reported a failure. CI was reading it as three, and #138 is the list of what it
could not see.

The render-diff test computed a difference against a design export and
**deliberately asserted nothing** — in an audit run it reported 90.04% of
pixels beyond tolerance and passed. The background audit next door printed
`bg-audit: week small exact-black 97.3%` and printed nothing else; a percentage
in a log is not a gate. And `Tools/test.sh` accepted any non-zero test count
grepped out of human-readable output, which cannot tell 380 tests from 40, and
certainly cannot tell that `GlowRenderTests` stopped running while `GlowTests`
kept the total high.

**That last one is not hypothetical, and it was not found by argument.** The
first run of the new validator on this branch failed a run `xcodebuild` had
exited 0 on: the app host had crashed as `GlowRenderTests` started, one "test"
was recorded for the whole bundle, and `GlowTests`' 370 passes were enough to
make the old check print `L1 370/370`. The run that proved the gate was the run
the gate was written for.

**Three gates now, each fail-closed.**

*Inventory.* `Tools/test-inventory.json` names every test bundle and the
smallest number of tests it may report. A **floor, not an equality** — adding a
test never touches the file, which is the whole reason a hard-coded expected
count was rejected: a number people bump reflexively stops being read. Lowering
a floor means tests were deleted, and it should be as visible in a diff as
deleting them was. A bundle that runs and is not declared fails too.

*Diagnostics.* Warnings come out of the result bundle and have to be zero,
against a fingerprinted allowlist that carries a reason and an issue per entry.
Six existed; all six were in test code and all six are fixed. The one entry left
is `llvm-profdata`'s complaint about coverage data from a previous build, which
is a property of a DerivedData directory rather than of the code and quotes an
absolute path, so it is allowlisted by prefix.

*Visual.* Not a PNG diff against the design export. The export is a flat mockup
of an HDR app and disagrees with the render by design; adopting that 90% as a
baseline would have been adopting a number nobody derived. The baseline is a
committed **16 × 16 grid of mean brightness** per widget family, plus the share
of the frame that is exactly black, rendered for a pinned date at a pinned glow
setting. Each cell averages roughly 450 pixels, so antialiasing along an edge
moves a cell by well under one level while a mark that moves a column moves
cells by tens. Measured rather than assumed: two simulator models produced
**bit-identical grids**, so the tolerance of 3 is headroom for a future
renderer, not slack for today's. Moving `WidgetMetrics.labelWidth` from 98 to 94
— four points, the size of the error that once cost this project three real code
changes — turns it red and attaches expected, actual and diff images.

**Every gate here was watched failing before it was believed.** The validator's
own mutations run under `--self-test` on every push, on a Linux runner, because
a checker nobody checks can weaken silently; the visual gate was proved by the
four-point mutation above; the inventory and diagnostics gates were proved by
running one bundle instead of two with a warning injected, which named the
missing bundle and the warning separately.

**Runtime warnings are counted and not yet fatal, on purpose.** The result
bundle records them as one opaque `Multiple Runtime Warnings` node per test —
92 of them on a run that passes — so a gate on them would either go red on
every build or need every one enumerated first. The count is in
`validation.json` and in CI's run summary, beside gates that do fail. Naming
them is the next piece of work, not a line in the validator.

**What CI still cannot do.** An iOS 18 lane was in scope and is not possible on
the pinned runner: `macos-26` carries iOS 26.2, 26.4 and 26.5 simulator runtimes
and no 18.x at all, so a minimum-deployment-target *test* lane would have to
download a runtime on every run. Compile-time coverage of the floor already
exists — the deployment target is 18.0 and the SDK is 26, so newer API is an
error at the call site — and runtime behaviour on 18 remains something only a
device answers. The lane that did land is an unsigned Release build against the
device SDK, which is the configuration and the SDK that ship and which the
simulator test lane never compiles.

## Edit mode gives the week's width back (#164)

**Question.** `List`'s edit mode draws a delete circle at the leading edge and a
reorder handle at the trailing one, and they landed beside a row that had not
changed at all — icon, name and seven columns of week still holding the width
they hold when the week can be tapped. What should the row show while it is
being reordered?

**Decision.** Everything weekday-shaped leaves, and the name takes the middle of
what is left: the track, the rest-day cut, and the header's letters all fade on
one 0.15s `easeOut`, and the label recentres between the system's two controls.

The three fade together because none of them labels anything once the others are
gone. The cut is positioned from the same geometry as the track and marks a
weekday exactly as the track does; the letters stand over columns that are no
longer there. The track is *removed* rather than dimmed, which is also what
keeps #137's rule — what is not drawn is not spoken — without a second
declaration: no slots in the hierarchy, no dates for VoiceOver to read out of an
empty row.

**The label hugs its content rather than keeping its column.** A label still
filling a label-shaped frame would have centred that frame, and the name inside
it would have stayed at the frame's leading edge — centred by measurement and
visibly not centred. Measured on the simulator at 3x: the delete circle ends at
x=116 and the handle begins at x=1054, midpoint 585; the label's box spans
444–724, centre 584. The ink looks a few points right of that because the icon
column is 24pt wide and a pencil is not.

**Reading `\.editMode` from the environment is correct here, and it was checked
before anything was built on it.** CLAUDE.md carries the opposite case as a paid-for
trap, and the difference is which side of the `NavigationStack` the view is on:
`TodayView`'s own `body` builds the stack, so the value it reads is its parent's
and never the one the toolbar's `EditButton` toggles — it owns `@State` and
injects it. `HabitRowView` and `WeekdayHeader` are plain descendants of the stack
`WeeklyGridView` builds, so they read the live value. Verified on the simulator
with a temporary on-screen indicator in both types before the fade existed: every
row and the header flipped on the tap. `EditModeTests` keeps the distinction from
drifting — no view that builds a stack may read the environment's copy.

**Leaving edit mode does not fade; entering does.** Measured off a 60fps capture
of the toggle, on the luma of one row's track: entering ramps from 26.9 to 16.9
over 0.13s, which is the animation asked for. Leaving jumps in a single frame
while `List`'s own chrome is still sliding out — the row's content is rebuilt as
the list drops out of editing, so the inserted track has no state to animate
from. It reads as the marks being back rather than as a jump, and the fix would
be to hold the whole track in the hierarchy at zero width and zero opacity,
which buys one direction of one transition with an invisible, still-hit-testable
week. Not taken; recorded here so the asymmetry is a decision rather than a
surprise.

**Timing: 0.15s `easeOut`, roughly half of `SlotView.close`.** A completion is a
change worth noticing and settles on a spring; this is a surface getting out of
the way, and it leaves. The number lives on `HabitRowView.editFade` and the
header borrows it, so the two cannot drift apart. Reduce Motion snaps it, as it
snaps everything else the grid does — the label changes width and position here,
and a shorter version of that is still a version of it.

## The host app read no version at all (#133)

**2026-08-22.** `project.yml` sets `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION`, the widget's generated `Info.plist` reads both as
`$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`, and the host's read
neither. Omitting the two keys does not leave them out: xcodegen writes its own
defaults, so every build this repository has ever produced shipped an app at
`1.0` / `1` embedding a widget at `0.1` / `1`. An extension whose version
differs from its host is an App Store rejection, and nothing anywhere says so —
the app builds, installs and runs, and the answer arrives from App Store Connect
after the upload.

It also made `Tools/ship-testflight.sh` do half of what its own header claims.
The script overrides `CURRENT_PROJECT_VERSION` on the archive command so that
every upload gets a unique build number; that override reached the widget and
left the host on the literal `1`.

**The host now reads the same two settings the widget does**, which is the whole
fix for the mismatch. Measured on the Release build for the device SDK:
`Glow.app` and `GlowWidget.appex` both report `0.1 (1)`, where before the app
reported `1.0 (1)`.

**A build is now read back before it ships.**
`Tools/check-release-build.py` opens a `.app`, an `.xcarchive` or an `.ipa` and
fails on: a host and appex that disagree on either version key, naming both
values; a declared appex that is not embedded; an appex that is embedded and not
declared; a bundle identifier that is not the declared one, or is not the host's
plus one component; an unexpanded `$(BUILD_SETTING)` still sitting in a shipped
plist; and a missing `PrivacyInfo.xcprivacy` at either bundle root. With
`--require-signing` it adds the two facts only a signed bundle carries — the App
Group as **codesign left it**, read out of the signature rather than out of the
entitlements file that asked for it, and an embedded profile that has not
expired.

**One file, two callers, and that is the point.** CI runs it on the unsigned
Release build for the device SDK, so a mismatch is a red pull request;
`Tools/ship-testflight.sh` runs it on the archive before the export and on the
exported `.ipa` immediately before `altool`. A gate and a release path that each
carry their own idea of what "matching" means will eventually disagree, and the
release path is the one nobody watches. What is checked is declared in
`Tools/test-inventory.json`, next to the test floors, so the bundle identifiers
and the App Group are reviewable in a diff rather than spelled out as script
arguments.

**Watched failing on real artifacts, not only on fabricated ones.** Each
mutation below was applied to a copy of the actual Release build and named its
values: the host put back to the pre-fix `1.0`; a stamped host build number
against an unstamped widget; both plists left holding `$(MARKETING_VERSION)`;
the widget deleted from `PlugIns`; a second appex added; the widget's privacy
manifest removed; an empty directory in place of an archive; a path that does
not exist; the app ad-hoc signed with the group stripped from the appex; and an
`.ipa` repackaged with a host at `9.9`. Sixteen fabricated scenarios run under
`--self-test` on every push, on the Linux runner beside
`validate-test-result.py`'s, and they were themselves watched failing: with the
version comparison replaced by `if False`, three of the sixteen go red.

**Signing checks are separable from reading them, deliberately.** The Linux
runner has no `codesign` and no `security`, so the self-test exercises the
*decision* on fabricated facts and the macOS callers supply real ones. What
could not be verified in this session: an expired profile and a distribution
signature, both of which need signing credentials this checkout does not have.
The entitlement check was proved with an ad-hoc signature instead, which is the
same read through the same `codesign -d --entitlements`.

**The App Group check no longer passes hardest when there is nothing to
check.** `Tools/check-app-group.sh` searched for a built app with `find … |
head -1`, reported success when it found none, and declared a `BUNDLE`
identifier it never used. It now takes the app's path, reads the identifier it
declared, fails when the app or the widget is absent, and says what to build.

**The build-number allocator is left alone.** #133 also proposed replacing the
minute-resolution UTC stamp with a monotonic allocator, because two uploads in
one minute collide. That is a real problem and a separate one: it changes what
goes to App Store Connect, and it cannot be tested without uploading. The
mismatch this entry is about is fixed and verified; the allocator is still open.

## A test process should not be running the app

**2026-08-22.** CI failed twice on a commit containing no Swift — a Python
validator, `project.yml` version keys and shell — with
`Swift/FlatMap.swift:49: Fatal error: Unexpectedly found nil`, failing a
different test each time, preceded by a background-thread publish storm the
xcresult attributed to `TestPreferences.withWeek` (#179).

**The mechanism, read off the code rather than guessed.** The test host is
`Glow.app`, and it builds the real interface. Those views observe preferences
through `@AppStorage` — `WeeklyGridView` the week's first day, every
`HabitRowView` the rest day, `GlowImageCache` the glow level. `TestPreferences`
writes exactly those keys, and Swift Testing runs tests off the main thread. So
every `withWeek` published into a live SwiftUI hierarchy from a background
thread, which is undefined behaviour — and the way it fails is somebody else's
`nil`, in a test that had nothing to do with it.

The seed set landing at eight habits (#123) made it worse: the rest day is
observed once per row.

**Measured, through the result bundle's own runtime-warning count** — which
exists because #138 started recording it a few hours earlier:

| | runtime warnings |
| --- | --- |
| `GlowTests`, before | **106** |
| `GlowTests`, after | **0** (twice repeated) |
| `GlowRenderTests`, either way | 0 — it hosts no interface |

**The fix is that the test host opens nothing and draws nothing.** Under a test
bundle `GlowApp` skips the container and presents a plain black view.
`GlowSettings.isRunningTests` is now named once and read twice: it decides that
tests get a private defaults suite (#168) and that the host stays inert. Both
are the same idea.

It also removes a second failure this repository had already seen: a test host
that opens the real store races the tests that open their own, and #138's work
watched it die when the migration suite left a deliberately malformed file
where the host looked.

**This is the fourth time the same root has surfaced**, and it is worth saying
plainly. #105 said suites cannot overlap because they are serialised. #168
found a preference outliving the process. #175 found the host dying under load.
Each was true and each was treated as the whole answer. The common cause is
that **decision logic reads a process-wide store**, and every fix so far has
made that harmless in one more situation rather than removing it. The real
answer is still what #105 named: the rest day should arrive as a parameter, the
way `calendar:` already does. This entry is not that fix either — but the count
of interims is now four, and that is the argument for doing it.

## A host that dies mid-run says so

**2026-08-22.** `Tools/test.sh` now classifies four outcomes rather than three,
and the new one is the host being killed (#175).

Three separate investigations tonight went looking for a bug in whichever test
happened to be running when the process died — a parameterised `WeekReach` case
in #117, an unnamed one during #130's verification, and a third during #138's,
which is where the load correlation was finally measured. The failure names an
innocent test every time, because it names whatever was in flight.

It now says the host died, quotes the fatal error, and prints the load average
beside the threshold this machine was measured at. The advice is to re-run
before reading anything into which test failed.

**A second red herring went with it.** #148 removed a bare `failed` from the
pattern, because the simulator logs `IOSurfaceClientSetSurfaceNotify failed` on
runs that pass. `error:` had exactly the same defect one layer down: CoreData
logs `CoreData: error:` lines, and the migration suite plants a malformed store
on purpose, so a crashed run reported that noise under "Failing assertions".
The pattern now requires a file and a position — a compiler error carries one;
a log line does not.

Both directions were induced rather than reasoned about. A deliberate
out-of-range subscript produces the crash message with
`ContiguousArrayBuffer.swift:692: Fatal error: Index out of range` and the load
average; a deliberate type error still produces
`FAILED. Failing assertions:` with the file, line and column. Both probes were
removed.

The two layers are complementary, which is worth noting because they were
built hours apart: the script says the host died, and #138's validator
independently names the test the result bundle recorded as failed.

## The rest day is a parameter (#181)

**2026-08-22.** The entry above ends "the count of interims is now four, and
that is the argument for doing it." This is it. `WeekPreferences.restDay` is no
longer read by anything that decides what a week looks like.

It arrives the way `calendar:` has always arrived: `WeekGrid.slots`,
`WeekSpans.spans`, `WeekDots.columns`, `MonthGrid.cells`,
`SeededHistory.completions`, `YearHistory.fill` and `SlotEditing.day` all take
`restDay: Int?`, with **no default anywhere**, so a new call site has to say
which day it rests on rather than inheriting an answer by forgetting to think
about it. That is `SlotEditing`'s own rule (#116), and #116 is also the shape
this copied: a decision threaded through the same two functions without changing
what either computes.

**Read once, at four boundaries.** A view reads it through `@AppStorage` —
`HabitRowView` and now `YearView` — because a value SwiftUI cannot see is a row
that keeps the cut line on the old day until relaunch (#134's lesson, applied
again). A widget reads it once per render, because it renders out of process
from an archived surface and has no live hierarchy to observe with.
`HabitStore` and `DemoHistory` read it at `init`, beside their calendar.

**The store's default is deliberate, and it is not an exemption.** `HabitStore`
could have been made to take the rest day from its caller like everything else.
It must not: the refusal exists precisely because a surface can outlive the
setting it was rendered under — a widget holds a rendered button in a second
process — so a rest day supplied by that stale surface would make the guard
agree with it and refuse nothing. The store is a boundary; boundaries read.
There is a test for each half: one builds a store with an explicit rest day and
asserts the refusal, one pins the preference and asserts the store finds it
unaided.

**No assertion changed.** 476 tests before, 478 after — the two new ones are the
source scan and the store's default. Every existing test kept its content and
gained an argument, which was the acceptance criterion: a behaviour change here
would have been a bug in the refactor rather than a finding. One test's
*scaffolding* had to move rather than its claim: `WidgetRefreshTests` built its
store outside the block that pinned the rest day and relied on the read
happening at toggle time. It now builds a store that rests on that day, which is
what the app does.

**What is asserted is the absence of a call**, and no runtime assertion can
watch an absence — a test that sets no rest day and finds nothing resting passes
whether or not the read exists. So `TestIsolationTests` scans `Glow/Logic/` for
`WeekPreferences.restDay`, exempting the file the stored value lives in. The
technique is #141's, #168's and #179's. It was checked by putting the read back
into `WeekDots`: the scan failed, and named the file.

**What this ends, and what it does not.**

- `TestPreferences.withWeek` stops being load-bearing for the rest day. It still
  pins `WeekPreferences.firstWeekday`, which `WeekCalendar.calendar` reads, and
  which is the same shape of problem one type away.
- #168's private defaults suite and #179's inert test host stay. They are
  belt-and-braces now rather than the only thing holding, which is the point of
  doing this after them rather than instead of them.
- `project.yml`'s note on `parallelizable: false` no longer rests part of its
  case on `WeekGridTests` being lucky. That suite's sweep over all 128
  completion histories names the rest day it means.
- **#175 is not closed by this, and was not expected to be.** It is the test
  host being killed, not a value being read. Checked rather than assumed: the
  full suite was run with the machine deliberately loaded to a 1-minute load
  average of 285 — four times the ~70 the issue names as its threshold — and
  passed 478/478. That is one data point against a correlation, and the load was
  CPU-only where the original was concurrent *builds*, which also bring memory
  and I/O pressure this probe did not. #175 stays open.

## The unlit grey moves to #242424

**2026-08-23.** #194 moves `GlowPalette.greyOpaque` — the app's one "not lit"
colour since #111 — from `#171717` (23,23,23) to `#242424` (36,36,36). It is one
declaration, and every unlit mark in the app moves with it: the resting habit
name, the weekday letter that is not today, the ✕ on a day that went unlogged,
the rest day's cut, the socket on a day still to come, the year's empty day.
That every one of them moved from one edit is the design of #111 working, not a
side effect of it.

**Why.** 23 was too dark in use. #111 picked it because it was the value the old
ramp's darkest step already composited to, which is what made collapsing four
greys into one a change that invented nothing — a good argument for the collapse,
and, it turns out, not an argument for that particular value.

**"Not a new colour" stops being true here, which is the part worth recording.**
`0.553 × 0.16 × 255 = 22.6 → 23 = 0x17` was a real derivation and is now history.
36 is derived from nothing: it is a judgement about what reads on a black screen.
The #111 entry above is left exactly as written — it records what was decided
then, and editing it to say `#242424` would misreport it.

**What it measures.** About **1.35:1** against black by WCAG relative contrast,
up from about **1.17:1**. Body text asks 4.5:1, so this is still nowhere near
legible and is not trying to be — legibility is `greyIncreasedContrast`'s job
(`#8D8D8D`, 6.3:1), untouched by this. No target ratio was set in advance: the
ratio is the consequence of a value chosen by eye, and it is written down so the
next person to move it has something to move *from*.

**Sampled on screen, before and after, same build path.** iPhone 17 Pro
simulator, iOS 26.5, `xcrun simctl io … screenshot` — a true 3x, which divides
cleanly, rather than the MCP screenshot, which does not.

| sampled | before | after |
| --- | --- | --- |
| weekday letters that are not today | 23,23,23 (1396 px) | 36,36,36 (1388 px) |
| the ✕ row on the first habit | 23,23,23 (500 px) | 36,36,36 (500 px) |
| the ✕ row on the last habit | 23,23,23 (497 px) | 36,36,36 (497 px) |
| the year's empty day | — | 36,36,36 |
| Settings toggle ON track | 181,181,183 | 181,181,183 |
| Settings toggle OFF track | 90,90,94 | 90,90,94 |

The mark counts are the evidence that this is the same picture at a different
level rather than a different picture: the same populations, shifted by 13.

The two toggle rows are the check #124 asked for by name. `controlTint` is
declared independently and this move must not reach it; it does not. Both
sampled regions come back pixel-for-pixel identical, ON still twice OFF, and 36
is still less than half of 90 — the inversion #124 warned about is not close.
The switches will not flip under an automated tap, so the ON track was reached
by writing `weekRestDay` into the App Group plist and relaunching.

`greyAccented` is declared independently too — `white.opacity(0.553)` — and is
not affected. Not re-measured: #111's Home Screen figures (Default 255/23,
Tinted 255/149, Clear 255/162) were taken on a device, none of the accented ones
depend on `greyOpaque`, and the simulator cannot settle it. What changes in that
table is the Default column, which is now 255/36.

Nothing on the simulator reads as lit at the new value, which was the risk worth
naming: white marks stay 255 with a halo, and 36 against 0 is plainly a dark
mark. The glow itself is unverifiable here as always — no EDR headroom.

### The render baseline moved, and the gate did not ask

`RenderTests/Baselines/render-signatures.json` is 16 × 16 mean-brightness cells
per family, and its `cellTolerance` is 3. The move landed at **worst +3** — the
tolerance is `> 3`, so all six frames passed and `Tools/test.sh` never printed
its approve command. Cell by cell, against the previous baseline:

| frame | cells moved | worst | exactly-black |
| --- | --- | --- | --- |
| week small | 44/256 | +3 | 70.3% → 70.2% |
| week medium | 19/256 | +3 | 73.7% → 73.6% |
| week large | 57/256 | +2 | 84.2% → 84.1% |
| month small | 41/256 | +3 | 90.2% → 90.2% |
| today small | 0/256 | 0 | 0.7% |
| today medium | 0/256 | 0 | 53.9% |

Every moved cell moved **up**, none down, and the two Today frames are bit
identical — the Today ring has drawn no grey since #75, so there was nothing in
them for this to move. The black share falls by a tenth of a point on three
frames because an antialiased edge that rounded to 0 against a 23 mark rounds to
1 against a 36 one.

**It was approved anyway.** A baseline that still describes the old grey would
hand the next unrelated change a budget this change has already spent, and the
run after that would fire and name the wrong commit. Approving is the deliberate
act the file is for; the re-run reproduces it with 0/256 cells moving on every
frame.

Worth saying plainly, since it is the second time a gate here has passed on
something real: a palette move of 13 levels is within one level of invisible to
this baseline. The tolerance is right for what it defends — a mark that moves a
column moves cells by tens — and it is not a colour gate. `TwoColoursTests` is.

### The tests, which had to be rewritten rather than patched

`Tests/WidgetBackgroundTests.swift`'s `TwoColoursTests` was written to lock in
`#171717` *and its provenance*, so updating the literals would have left the
suite asserting a claim the code no longer makes.

- **`greyIsTheOldSocket` is deleted.** It asserted `0.553 × 0.16 × 255 == 23` and
  that the palette matched it. Its whole premise was that the grey is not a new
  colour; it is now. There is no derivation for `#242424` to put in its place,
  and one that reconstructed 36 from 36 would be a test that cannot fail.
- **`theUnlitGreyClearsTheGround` replaces it**, asserting the claim that
  survives the move: the grey stays above 15, which is `WidgetRenderDiffTests`'
  `lineFloor` — the floor every unlit-line scan in the render bundle uses to
  separate a span or a cut from black. That bundle cannot import this one, so
  the coupling is asserted from this side.
- **`increasedContrastIsTheOldGrey` was firing correctly** on exactly this
  change: its `contrastOnBlack(23/255) < 1.2` was chosen to defend 23. The
  replacement reads the ratio off `GlowPalette.greyOpaque` rather than off a
  literal — so it cannot pass while the palette moves — and the ceiling is
  **1.5:1**, which is 44/255, `#2C2C2C`. That leaves room to nudge the grey by
  eye the way this change did, and fails on a change that starts walking it
  toward legible body text. Legibility is the Increase Contrast path's job.
- `greyIsOpaqueSeventeen` → `greyIsOpaqueTwentyFour`, and
  `defaultEnvironmentResolvesToTheOpaqueGrey` now expects 36. Both are the same
  test at the new value.

One test out, one in: 478 before, 478 after, no floor in
`Tools/test-inventory.json` touched.

`RenderTests/WidgetRenderDiffTests.swift` needed one number that #194 did not
name. `renderIsReal` demands evidence that something unlit was drawn by counting
pixels inside a narrow band around the one grey — 20...26 for `#171717`. At 36
that band is empty, and the test would have failed with "nothing unlit in the
render" on a render that was fine. It is 33...39 now. The band is a literal
rather than a value read from `GlowPalette`, deliberately: a band computed from
the number it is checking agrees with every number.

## Reset to Default Habits: typed, not tapped (#193)

**Question.** First-run seeding refuses a store that holds anything, on purpose
— a seed set that changed would otherwise rewrite a list somebody had arranged.
So an install seeded three days ago can never see the current defaults again.
What is the escape hatch, and how is it guarded?

**Decision.** A row in Settings → Data that empties the store and installs
`DefaultHabits.all`, behind a confirmation the person has to **type**.

The seeding guard is not touched and not weakened. What is added is the opt-in
opposite of it: an explicit request for the shipped list, made by someone who
knows it throws away what they have. Not a merge, and no attempt to reconcile
old habits with new ones by name — "Workout" appearing in both lists is a
coincidence, not a match worth preserving history over.

**Why typed.** Everything else destructive in this app is either recoverable or
small: a deleted habit is one habit, and an unchecked day is one day. This is
all of it, at once, with no undo, sitting one row below a demo toggle that is
flipped casually and often. A confirm button that one tap dismisses is a bad
evening for somebody who reached for the wrong row. So the destructive button
stays disabled until `RESET` is in the field — the cost is four seconds for the
person who meant it, and the whole action for the person who did not.

**The alert really does enforce it, and that was checked rather than assumed.**
SwiftUI alert buttons are widely reported to ignore modifiers, and `.disabled`
on one re-evaluating live against a `TextField` in the same alert is exactly the
kind of thing that compiles and does nothing. Screenshotted on an iPhone Air
simulator at each step: empty field, Reset dimmed; four characters typed, still
dimmed; the fifth typed, Reset enabled **and red**. Red because an alert is one
of the few contexts that ignores the app's root white tint — the same exception
the grid's swipe action already documents. The Settings row itself does not get
that exception and is drawn red by hand, like Delete Habit.

**The match is case-insensitive and trimmed**, which is looser than the issue's
`text != "RESET"` and looser in the only dimension that carries no intent.
Typing `reset` is exactly as deliberate an act as typing `RESET`; a confirm
button that stays dead over a shift key, with nothing on screen saying why, is a
worse outcome than the one the strictness was guarding against. The field asks
for capitals with `.textInputAutocapitalization(.characters)`, so most people
never meet the difference. Nothing else is forgiven: no prefix, no substring, no
empty field, and it still has to be typed rather than tapped. The rule is
`ResetConfirmation` in `Logic/` rather than an expression inside the
`.disabled(…)` — it stands in front of the one action that deletes everything at
once, and every other rule that decides whether a write may happen is a pure
function with a test on it.

**One thing found on the way, and fixed here because shipping around it would
have meant shipping text nobody can read.** A `Section` footer built from
several `Text`s renders the first and drops the rest. The Data section held two
and has been showing only the export sentence — the demo-history paragraph has
never appeared on screen, which is visible at the bottom of the scroll where it
is absent rather than cut off. The Week section next door has always written its
footer as one string with a blank line in it, which is why both of *its*
paragraphs arrive. The Data footer now does the same, and all three paragraphs
render; screenshotted before and after.

**What the reset clears, and what it deliberately does not.**

- **Every habit and every completion**, in one `commit()`. One transaction is
  the point: a failure leaves the store exactly as it was, which is #140's
  property applied where the half-finished state would be a deletion. The
  completions are deleted explicitly rather than left to `.cascade`, because a
  cascade cannot reach a completion whose habit is nil, and "nothing survives"
  with an exception in it is a different promise.
- **`DemoHistory`'s pre-provenance key.** The issue asked for this as a
  correctness fix and it is not one any more, which is worth writing down rather
  than quietly doing: since #140 the demo's provenance is `demoSessionID` on the
  row, so a reset that deleted every completion already reads as no demo. The
  key is dropped because it would otherwise name fifty completions that no
  longer exist — tidiness, in a call whose claim is that nothing is left over.
  The Settings screen re-reads `isSeeded` from the store afterwards rather than
  assuming, which is what actually keeps the toggle honest.
- **Not `HabitSeeder.seededKey`.** It means "this install has at some point
  ended up in a seeded state", and a store holding exactly `DefaultHabits.all`
  is that state. Clearing it would arm a seeder that then refuses the store
  anyway, and on the one path where it would not refuse, it would add a second
  copy of the list the reset just installed. A test asserts both halves.

  **Both the flag and the seeder are gone** (#228, below). There is no first-run
  insert left for a reset to re-arm, and `resetToDefaults` is now the only way
  the defaults ever go in — from Settings, and from the empty state.
- **Not the widget reload at the call site.** The issue's sketch called
  `WidgetCenter.shared.reloadAllTimelines()` directly; that is the habit #134
  removed. Going through `commit()` means the reset coalesces like every other
  write — asserted as exactly one reload for the whole thing.

**Numbered from zero.** The sketch reused `addAll`, whose `nextSortOrder()`
would have been answering from rows already staged for deletion, leaving the
same list at `sortOrder` 3…17. Invisible on screen and harmless today, and a
difference between "reset" and "fresh install" that nothing would ever
reconcile. `addAll` and the reset now share a private `insert(_:from:now:)`.

**Verified on screen**, on an iPhone Air simulator: a store with the demo in,
a hand-typed habit, two completions logged by hand and a rest day set — 15
habits and 1,728 completions read out of the App Group's SQLite — reset to 15
rows matching `DefaultHabits.all` at `sortOrder` 0…14 and **0** completions, the
demo toggle reading off, and This Week redrawing to the first-launch screen.
The rest day survived, as a preference should.

## The week pager becomes a swipe, and the title becomes a date range (#190)

**What this overturns.** Two of #117's decisions, both recorded above under *How
far back the week view reaches*: **buttons rather than a swipe**, and **which
week you are on is the title's job**, answered with a month name. The twelve-week
cap is not reopened and did not move. The old entry stays as written — it is a
record of what was decided then, and the reason it is being overturned is that
one of its two premises was never tested.

**The chevrons were decided by reading the code.** #117 inferred the conflict:
every row carries `swipeActions`, so a horizontal drag starting on a row is
spoken for, so a pager sharing that gesture would work in some places and not
others. The inference is correct and the conclusion did not follow. The gesture
does not have to live on the rows. It lives on `WeekdayHeader`, which owns no
horizontal drag of its own, and the rows are untouched: **`swipeActions` did not
change in this issue.**

**Discrete, not interactive.** Past a 24pt threshold the week jumps, exactly as
a chevron tap did; nothing tracks the finger and there is no half-dragged week
to abandon. Left pages forward and right pages back — **confirmed against
Calendar.app in the simulator** rather than assumed: in Day view a left swipe
moved Sunday 31 December to Monday 1 January and a right swipe moved it back. A
two-direction gesture with no affordance reads as broken if it is backwards, so
this was worth ten seconds.

**The simulator cannot exercise a drag at all, and that is the finding.** The
gesture logged nothing there — as `.gesture`, as `.simultaneousGesture`, under
`swipe` and under a twelve-point `touch_path`, with the reach confirmed open in
the same console. The control that settles what it means: **this app's own row
`swipeActions` do not open under the same synthetic input either**, and they
ship. So the negative result is a property of the harness, not of the code —
the same trap as the pixel script whose baseline was four points off. The
assumption that remains is recorded in #205, with the four swipes on a device
that would overturn it. `.simultaneousGesture` is what shipped, because the
competing recognizer is a scroll view's pan and simultaneous recognition does
not ask it to yield the touch stream.

**Nothing replaces the chevrons in the toolbar, so VoiceOver needed a control.**
The chevrons were also the only paging a rotor could reach, and a gesture on a
header that is `accessibilityHidden` reaches nobody. The readout is therefore
adjustable — up for a later week, down for an earlier one. That does not reopen
#137: what stays unspoken is the seven letters over seven numbers, which is a
table read aloud, and one element naming the week is not that.

**"This Week" is drawn, not styled**, for the third time (#162, and
`StoreUnavailableView` before it): a root tint of pure white fills a
`.borderedProminent` capsule white and writes its label in white. A `Text` in
black over `Capsule().fill(GlowPalette.color)`, `.buttonStyle(.plain)`. It sits
inside the list between the header and the first row, outside the `ForEach`, so
reordering and deletion still index the habits and nothing else — and it stays
drawn in edit mode, where the header fades (#164). Editing is about rows; the
pill is a way out of a week you paged into, and a control that is drawn can be
tapped and can be spoken.

**The title is a range because a month is not an answer.** A month holds four or
five of these weeks and every one of them read the same name. `weekRangeTitle`
says both ends; the month collapses to one name when both ends share it, and
that collapse, the separator and the order of day and month are
`Date.IntervalFormatStyle`'s, not this code's, so a locale that writes the day
first gets what it writes. The year rule survives from `monthTitle` — it appears
only when it is not today's — and it is the one thing the interval style cannot
express, since asking it for a year prints two. A week that needs one is composed
from its two ends instead, with the year dropped from the first when both ends
share it.

**`monthTitle` is gone rather than kept beside it.** Its only two callers were
this view and its own tests. Keeping a formatter nothing draws, with tests
asserting a rule nothing shows, is the code version of a drifted document.

**The large title goes with it, knowingly.** Collapse-on-scroll belongs to
`navigationTitle`, and a `.principal` toolbar view does not inherit it. The
issue accepted that trade. `navigationTitle` is still set to the same string,
because it is what a pushed screen would name its back button. Where the
principal item *sits* turned out not to be ours: measured, it is centred while
it is one line, leading once the second line arrives, and centred again in edit
mode, and a `frame(maxWidth:alignment:)` around it changes none of the three.
So the readout shifts left as you leave this week — at the same moment the
subtitle and the pill appear, which is a state change rather than a wobble.

## The visual gate learns to see tone (#199)

#194 moved `GlowPalette.greyOpaque` thirteen levels — every unlit mark in the
app, `#171717` to `#242424` — and `RenderBaselineTests` did not fail. The worst
cell in any family moved **+3** against a `cellTolerance` of **3**. A
whole-palette change came one level short of invisible to the gate built to
catch exactly that.

**The arithmetic, not the tolerance, is the fault.** The baseline is a 16 × 16
grid of *mean* brightness, and a mean dilutes a change by however much of the
cell is unaffected. Each cell averages roughly 450 pixels; the marks that carry
the grey are thin — hairlines, a 1pt ✕, weekday letters — so thirteen levels on
the marks average down to two or three levels on the cell. The measured spread
from #194: week small 44 cells moved, worst +3; week medium 19, worst +3; week
large 57, worst +2; month small 41; both Today frames 0.

### Why not simply lower the tolerance

The obvious fix is `cellTolerance = 1`, and #138's own reasoning invites it: two
simulator models produced bit-identical grids, so the observed noise floor is
zero and 3 is buying nothing today. It was rejected because "zero on two models
of one Xcode" is evidence that the floor is low, not proof that it stays low.
Antialiasing and colour management are the renderer's business and have already
been seen to move across platform versions elsewhere in this repository — it is
why CI pins its macOS runner. A gate that goes red on all six families the
morning after an Xcode bump is a gate people learn to re-approve without
looking, and a baseline re-approved without looking is worse than a loose
tolerance, because it launders a real regression through a ritual.

It would also have bought less than it looks like. At tolerance 1 the #194 move
does fail — by two levels, in four families. But the dilution factor is what it
is: thirteen levels on the marks arrived as three on the worst cell, so a
tolerance of 1 sees a palette move of about five levels and nothing smaller, and
sees nothing at all in the two Today frames, which moved zero cells either way.
A smaller number divided by the same 450 pixels is the same arithmetic.

`cellTolerance` is unchanged at 3.

### The second statistic

The app paints exactly two colours and no ramp between them (#111). That has a
consequence nobody had used: **an unlit mark deposits every one of its pixels at
one exact level, while the halo around a lit mark deposits a smooth gradient.**
In a histogram of the frame that is a spike standing on a ramp, and the height
of the spike above the ramp is a *count of pixels* rather than an average — so
it does not care how thin the mark is.

`RenderSignature.toneExcess(in:at:)` is that height: the population at a level,
minus the mean of its two neighbours. Measured across all six families, rendered
before and after #194:

| family | excess at 36, grey = 36 | excess at 36, grey = 23 |
| --- | --- | --- |
| week small | 1068 | 10 |
| week medium | 2068 | 42 |
| week large | 4132 | 29 |
| month small | 680 | 0 |
| today small | 8 | 8 |
| today medium | −2 | −2 |

Two orders of magnitude, against three levels of slack in the grid. The gate
asks that a tone the baseline recorded still holds **half** its pixel count —
enormous headroom, because what a move actually does is take it to about 1%. A
*one*-level palette move collapses it just as hard, since the spike lands on the
neighbouring level instead. The check runs in both directions: a family the
baseline says paints a tone has to still paint it, and a family the baseline
says does not must not start.

**The two Today frames genuinely contain no unlit pixel**, which is why they
moved zero cells in #194 and why their census reads 8 and −2. Their only unlit
surface is a habit name in the handled state, and the pinned fixture's one habit
is open, so it glows. The baseline records that as near-zero and the
"must not appear" branch holds it there; the fixture was left alone rather than
grown a second habit, which would have been a real layout change to two frames
in a change about measurement. A tone gate cannot cover a family that paints no
tone, and now the committed file says so in numbers.

### The literal, and what keeps it honest

`RenderSignature.flatTones` is `[36, 255]` — written down, not read from
`GlowPalette`, for the same reason `WidgetRenderDiffTests`'s grey band is a
literal: a level derived from the value under test agrees with every value.

That has a failure mode. Move the palette, re-approve the baseline, and leave
`flatTones` alone: every family then records ~0 at level 36, the census compares
zero against zero six times, and the gate is dead without a word. So
`flatTonesAreReal` renders the families and asserts that **something, somewhere,
is actually painted at each level the list names**. It is the half that notices,
in the same shape as `baselineIsComplete`.

### The re-approval in this change

The committed baseline was re-approved, and every pre-existing number in it is
byte-identical: same widths, same heights, same `exactBlackPercent`, same 1,536
grid cells. The diff is 24 added lines and nothing else — one `tones` object per
family. Nothing about the picture moved; the file learned to record one more
thing about it.

**Proof it now catches #194.** `GlowPalette.greyOpaque` was set back to 23 and
the suite re-run: four families fail by name — week large "has 29 pixels painted
flat at level 36; the baseline says 4132, and this gate wants at least 2066" —
and `flatTonesAreReal` fails alongside them. Restored to 36, green.

### What the gate covers, said plainly

Recorded because `Tools/test-inventory.json` read as covering both and only
covered one:

- **Geometry** — the 16 × 16 mean grid. A mark that moves a column, a row pitch
  that shifts, a label that stops being drawn. Loud, because a mark leaving a
  cell moves that cell by tens.
- **Ground** — `exactBlackPercent` against `blackTolerance`. A gradient, a tint
  or a material anywhere behind the marks.
- **Tone** — the census. Which exact levels the app paints, and how much of the
  frame is painted at each. This is the half that is new.
- **Not covered:** the glow itself. The simulator has no EDR headroom, so every
  frame in the baseline is the SDR render. `GlowRendererTests` holds the
  headroom claim and a device holds the rest.
## The pager becomes asymmetric, and the swipe and the pill come back out (#207)

**What this overturns.** *The week pager becomes a swipe*, two entries above and
an hour old: #190's header swipe and its "This Week" pill are both gone, and the
date-range title is demoted from *the* title to the last rung of a ladder. The twelve-week cap and #116/#117's
rule that every day of the visible week is tappable are not reopened and did
not move. The old entry stays as written; this one says what replaced it.

**The two ends of the toolbar are one decision.** What the trailing group holds
depends on which week is on screen — Edit and Add on the current week, a single
**Today** in the past — so the pager opposite it cannot be decided
independently. Hence asymmetry: `<` alone on the current week, `< >` off it. A
forward chevron on the newest week there is can never do anything, and #117 drew
it permanently disabled, which is a dim button explaining a boundary nobody was
pushing at. Back keeps its disabled state, because that one *is* a boundary
somebody pushes at: a fresh install has no record to page into, and a chevron
that vanished instead would leave the leading slot empty and say nothing.

**List editing is a current-week affordance.** Reordering, deleting and adding
are properties of the list, not of the week on screen; doing them while looking
at three weeks ago means nothing they do not already mean today. This is not new
editing scope — every slot of every reachable week is still a plain button.

**So edit mode had to end when the week does.** Removing `EditButton` from a
past week leaves a hole the issue did not name: enter edit mode, page back, and
the list is fanned open with the week track faded (#164) and no Done anywhere on
screen. A mode with no exit control is a trap. The resolution is to end the mode
rather than to keep a button the week does not otherwise have, which means this
view owns `\.editMode` as `@State` and injects it below the `NavigationStack` —
**not** the trap in CLAUDE.md, which is about *reading* the environment value
from outside the stack, and which `EditModeTests` scans for. Verified on the
simulator: with edit mode on, one tap on `<` lands on a screen that differs from
the same week reached normally only in the clock in the status bar.

**"Today", not "This Week", and in the toolbar rather than over the grid.** The
jump is the same one #190 specified — straight to `reach.latest`, not a repeated
step — but it sits where the screen's other actions are instead of scrolling
with the rows, so there is no second element to keep in sync with the pager. It
is a plain toolbar button rather than a drawn capsule: the root-tint trap (#162)
is why #190's pill had to be drawn, and a toolbar button needs no fill to be
found when it is the only thing on that side of the bar.

**The title says how long ago before it says which days.** "This Week", "Last
Week", "Two Weeks Ago" — the three weeks anybody names that way — and then the
range #190 built. Past the third rung a relative phrase is arithmetic nobody
does in their head, and a date is what identifies a week. The line underneath
carries whichever half the title left out: the dates while the title is a
phrase, "5 weeks ago" once the title is the dates. On the current week the title
stands alone.

**The count stays days-divided-by-seven.** #207 proposed
`dateComponents([.weekOfYear], ...)`, on the correct observation that a *read*
between two normalized midnights carries none of the DST hazard `WeekReach.step`
avoids. The hazard it does carry is a different one, and a test written for #190
already fails on it: `weekOfYear` restarts on 1 January, so twelve weeks back
from mid-January reads as −39. `WeekCalendar.weeksBack` is the number the ladder
switches on, and `weeksBackTitle` now asks it rather than counting again.

**The readout does not shift after all.** #190 measured the principal item
moving from centred to leading when its second line arrived, and recorded it as
a state change rather than a wobble. With this toolbar it does not move: the
title's own centre is 602–604px of a 1206px screen on the current week, one week
back, three weeks back and at the floor. The trailing group is narrower now,
which is the likeliest reason. The measurement is repeated here rather than the
old one being deleted — it was true of the toolbar it was made on.

**The gesture goes unmeasured.** #190's swipe could never be exercised: no drag
of any kind recognises under this simulator's synthetic input, and the control
that makes that negative meaningless is that the app's own shipped row
`swipeActions` do not open under it either. It ships nothing now, so #205's four
device swipes no longer settle anything about this screen. The finding about the
harness is worth keeping; the gesture is not, because #207 asked for buttons.

## The top of the screen fades; the toolbar was never opaque (#195)

**Question.** The preview capsule reads as visible right behind the Dynamic
Island while Settings is being scrolled. Is something clipping wrongly, or is
it just an unlucky scroll position?

**Neither, and the premise was one step off.** It is not a during-the-gesture
effect and it does not need a device to see. Swiped 200pt and screenshotted at
rest on an iPhone 17 Pro simulator, a column through the capsule reads
**249,249,248 at 140pt from the top of the screen**, with the inline "Settings"
title printed over it. The navigation bar's declared-visible background is not
opaque black. #109's measurement — "a column down the left edge reads 0,0,0
straight through the bar" — is real and was read as saying more than it says: a
column with nothing bright behind it reads black whatever the bar is doing.

**Decision.** A fixed gradient pinned to the top of the screen, opaque through
the safe area and falling off 64pt below it, over the content and under the
bar. It belongs to the top of the screen rather than to the preview, so
whatever ends up scrolling through there dissolves the same way.

Two things had to be measured rather than assumed, and both were wrong on the
first build:

- **`.ignoresSafeArea(edges: .top)` is what pins it to the screen.** Without it
  the overlay's top edge is the *form's* top edge, which a `NavigationStack`
  puts below the whole navigation bar. Coloured red and green and
  screenshotted, the band started at 167pt — under the large title, across the
  preview, nowhere near the top of the screen.
- **A `GeometryReader` inside that overlay reports `safeAreaInsets.top` as 0.**
  Once the safe area is ignored there is no inset left for a proxy to report,
  so a height derived from it came out 64pt and the screen measured
  pixel-for-pixel identical to the screen with no fade at all. The inset is read
  from the key window instead: 62pt on this phone, and the fade is 126pt.

**Verified on screen**, same simulator, same scroll position, black rather than
coloured: 104pt from the top the capsule's edge went 137 → 90, 96pt went 31 →
17, and everything above 100pt reads under 5 where it read up to 57 before.
Scrolled far enough that the capsule passes 56–96pt — the position the report
is about — nothing above 92pt exceeds 41 and the capsule is gone into black
rather than cut off in it. At rest the preview is untouched at 255,255,254: the
fade ends at 126pt and the capsule starts at 275pt.

The bar keeps `.toolbarBackground(.visible, for: .navigationBar)` — still
without a `Color`, which still removes the title — because that is what stops
the system material dimming the capsule to grey. It is simply not what was
holding the light back.

## `listSectionSpacing` sets the gap below, and #201 read it as above

**Question.** The "Glow off" banner moves from three sections down to directly
under the preview it explains. #201 says `.listSectionSpacing(0)` has to travel
with it, or the gap the preview's own zero removes "reappears one section
later".

**Decision.** It moves; the modifier stays behind. `.listSectionSpacing(0)` on
a `Section` sets the spacing **after** that section, not before it — so the
preview's own zero already lands on whatever follows, and the banner arrives
tight against the reserved halo band with nothing of its own.

Measured on an iPhone 17 Pro simulator with the slider dragged to its minimum,
built both ways: the banner panel occupies **418–470pt in both**. Carrying the
modifier changes only what is below it, pulling the Glow section's panel from
528pt up to 510pt and its header text with it — which closes the one gap #201's
own acceptance criterion asks to keep ("the normal Form spacing should resume
between the banner and the Glow slider section below it"). The two halves of
the issue disagreed; the screen settles it.

## A `Form` section footer's reflow does not animate (#203, #215)

**Question.** Switching "Say well done" changes the footer's length and every
section below it jumps. #203 asks for `withAnimation` around `popBinding`'s
write, "matching how this app already treats a state-driven layout change".

**Decision.** Not implemented, and the write stays synchronous. Measured on an
iPhone 17 Pro simulator with a burst of screenshots 0.17–0.33s apart:

- With `withAnimation(.linear(duration: 3))`, the Week section's panel reads
  518pt in thirteen consecutive frames and 486pt in every frame after, changing
  between two frames 0.33s apart. No intermediate position.
- Adding `.animation(.linear(duration: 3), value: popLevel)` to the `Form` as
  well: 373pt → 405pt, again between two consecutive frames.

**The transaction is not being lost, which is the part worth keeping.** The
preview capsule given `.opacity(popLevel == .off ? 0.3 : 1.0)` — driven by the
same write, inside the same `withAnimation` — ramped 254 → 168 across thirteen
frames of that three-second curve while the sections below it still jumped in
one. Animations run; the write animates everything it drives except the list's
own layout.

That is the false positive #203 warns about, one level down. It says to check
that the *footer* animates rather than the picker's knob — and the knob
animates, and so does anything else the write reaches. The section reflow is
the exception.

Shipping the wrap anyway would have been a change that reads as a fix, passes
review, and does nothing. What ships instead is the measurement, as a comment
on `popBinding`, so the next reader does not re-derive it. #215 carries the
open design question: accept the snap, or move the explanation out of the
section footer and into a row, where ordinary layout animates ordinarily.

## Per-day habits move to a branch (#209)

**2026-08-23.** `Frequency.timesPerDay`, the Today screen, the Today ring and
the two Today widget families come out of the shipped app. They are 2.0 scope
rather than MVP. Nothing is deleted from the record: the state they were in is
pushed as `feature/daily-habits-2.0` **before** the removal, so the branch is a
snapshot somebody can check out rather than something reconstructed later from
`git log`.

**`Frequency.daily` is not what came out, and the word is the whole hazard.**
The editor's `Daily` segment meant *counted within a day* — a ring, N
repetitions resetting at midnight. `Frequency.daily` means a habit due all seven
days of the week: seven columns on the week grid, Gratitude and Early night in
the seed set, untouched. The two senses shared a screen for as long as the
feature shipped and `HabitEditorView` carried a paragraph warning about it. One
of them is gone and the warning is now a note in CLAUDE.md, where the next
person reading "remove daily habits" will meet it first.

**The widget kinds are removed, not renamed, and that costs somebody a widget.**
`WidgetKind`'s own comment says a kind is a persistent identifier: WidgetKit
stores it against every widget a person has placed. Renaming one orphans their
widget — it stops being the thing they configured. Removing `GlowTodaySmall` and
`GlowTodayMedium` does something different and more honest: the extension that
drew those families stops shipping, so the widget leaves the Home Screen with
it. That is what pulling a feature does. It is intended here rather than routed
around, and it is said plainly in the pull request rather than left to look
accidental.

**Existing installs are swept, and it deletes real history.** #123 shipped five
per-day defaults — Sunlight, Protein Meal, Move, Breathe, Hydration — so an
install seeded by a build that carried them holds habits nothing can now draw.
`DailyHabitMigration` deletes them and their completions once at launch, on the
same flag shape `HabitSeeder.seededKey` uses, written after the save so a
failure is retried rather than recorded. Anybody who logged repetitions during
the window the feature shipped in loses those days. The alternative — leaving
the rows in the store, invisible and uneditable — is worse: they would still be
counted by anything that counts habits, and they would reappear the moment a
later build queried without the filter.

**`countedPerWeek` is renamed rather than deleted, because it still excludes
something.** Its clause is `timesPerDay == 0`, which is now true of everything
the app writes — the name stopped meaning anything the moment nothing set
`timesPerDay`. Deleting it was the obvious move and it is wrong: the rows the
migration has not swept yet are real, and **the widget's process never runs the
migration**. A home screen redrawing between the update and the next launch of
the app would show habits the app has no screen for. So it survives as
`Habit.weekly` — a residue filter with a stated end, which is when
`DailyHabitMigration` goes.

**`Frequency.slotCount` stays optional with no case answering nil.** The per-day
kind was the nil, and the optionality made a caller reaching for a week say what
it meant when there wasn't one. Flattening it to `Int` would rewrite every one
of those call sites in the change that removes the feature and again in the one
that restores it, so it is left as it is and the comment says why.

**`GoalMet.justMet` loses `today:` and `calendar:`.** They were read only to
find *which* day to count, which was the per-day branch's question; the week is
the only window left. A parameter nothing reads is a parameter a caller can pass
wrong for years without finding out, so it goes rather than sitting there
against a future restoration.

**What moved in the render baseline: two frames, and nothing else.** The `today
small` and `today medium` families are removed from
`RenderTests/Baselines/render-signatures.json`. Every surviving frame is
byte-identical — same 16 × 16 cell grid, same tone census, same exact-black
share — which is the evidence that this removal touched no drawing that still
ships. #213 recorded that the two Today frames contained no unlit pixel; with
the frames gone it is moot, and the `toneFloor` comment that carried it now says
what the floor is still for.

**One render test had to be rewritten rather than re-pointed.**
`haloIsWhatLiftsIt` read one corner of the small Today family, whose ring halo
reached `96 * ringHaloRadius * maxHaloScale` = 46.6pt and so covered a 158pt
frame corner to corner. Measured on the four families that remain, **no corner
is lifted at all**: that reach was a property of the ring, not of the halo. The
test now samples the difference itself — every pixel that is exactly 0,0,0 with
the glow down and is not with it up, wherever it falls — which is the same claim
without depending on one frame's geometry.

**The floors in `Tools/test-inventory.json` are not lowered.** `GlowTests` goes
from 486 to 441 and `GlowRenderTests` stays at 13, against floors of 398 and 12.
A floor is a minimum and both still clear it; lowering one that is not binding
would weaken the gate in exchange for nothing. The reviewable event is lowering
a floor, and there was no need to.

**The Today tab's slot is left empty rather than collapsed.** #210 puts the
Widgets tab in the same position. Reflowing the tab bar twice in two builds is a
worse thing to ship than two tabs for one build.

## A span is identified by its division, not by its index (#196)

`SlotSpan.id` was `index`, and `Slot.id` still is. The difference is that a
daily row's seven slots are the seven weekdays forever — index N is weekday N,
and logging a day changes neither the count nor the meaning — while
`WeekSpans.divided()` recomputes the number of spans *and their day ranges* from
`done`, `repsLeft`, `lost` and `live`, which is to say from exactly the numbers
a tap moves. The span at index 2 before a tap and the one at index 2 after it
can be different widths over different days.

`ForEach` believed the index and kept `SpanView`'s `@State` across that. The
state it kept is `closing`, the mid-flight size of the completion animation, so
a span whose range changed under a running animation drew a mark measured for a
different span — and since the `Button`'s hit area is that mark, the row went
dead to taps at the same moment it started looking wrong.

**Measured, with the hold window widened to make the race catchable.** The
`Task` that clears `closing` sleeps `SlotView.closeDuration`, 600 ms, which is
too short to drive by hand; a scratch build raised it to 30 s and changed
nothing else. Week starting Friday so that today, Sunday, sits in column 2; a
3×/week row, nothing logged, drawn as `open:0-2 inactive:3-4 inactive:5-6`. Tap
today, then tap Friday inside the same span, which #116 allows and #117 allows
in any week on the pager: the row redivides to `filled:0-1 filled:2-2
inactive:3-6`, and the first span keeps its state while its range narrows. On
the pre-fix build that span rendered **246 px wide inside a 124 px frame**,
centred on 591 — the closing size of the three-column span it used to be,
overflowing the two-column frame it now is. With the identity fixed it rendered
530–653, pixel-for-pixel the resting geometry of that row.

**The range, and not the state.** #196 proposed hashing `firstDay`, `lastDay`
*and* `state`, and the state is the half that cannot be there. A completion
arriving is precisely a span holding its range while its state goes
`.open → .filled`, and `SpanView` starts the close from
`.onChange(of: span.state)`. Put the state in the identity and that span is a
new view rather than a changed one, `onChange` never runs, and there is no
animation left to inherit because there is no animation. Recorded and stepped
frame by frame on a 2×/week row: with the range identity the mark goes
300 × 68 px → 296 × 64 → 288 × 56 → 279 × 46 → 270 × 36 → 260 × 28 → 253 × 20 →
246 × 13 → 242 × 9 and then holds; with the state in the identity it goes
300 × 68 → the settled line in **one frame**, with nothing in between. That is
the reduced-motion path arriving for everybody, which is not a fix.

So the identity is `SlotSpan.Division`, the two column bounds. Spans partition
the seven columns without overlapping, so no two spans in a row can share one —
asserted across every target, every weekday and six completion sets rather than
argued.

**One thing seen on the way and not chased here.** In the frame capture the
mark vanishes entirely for three frames between the close finishing and the
held bar — the rest of the screen is unchanged in those frames, so it is that
one view. It is not this change: for the transition being recorded the identity
is the same before and after the fix — index 0, columns 0-2 — so both builds run
the same code path. Worth a look when something else touches `GlowImageView`.

## Overriding which day the app thinks it is (#204)

A debug control with real write powers: pick another day of the current week in
Settings and the whole app treats it as today, including the widgets, and a tap
logs a genuine completion dated to it.

**`WeekCalendar.today()` is declared in `Glow/Store/DebugToday.swift`, not in
`Glow/Logic/WeekCalendar.swift`.** The issue's sketch put it beside the rest of
`WeekCalendar`, which would have made that file the first in `Glow/Logic/` to
read the clock *and* the first to read the App Group — the exact rule #181 spent
four issues restoring. The spelling is what the call sites wanted, so the
spelling stayed and the declaration moved to the boundary; `WeekCalendar`'s
header now says where the function lives and why. Nothing but a scan can hold
that line, because an extension in the same module compiles from anywhere, so
`TestIsolationTests` gained a second scan of `Glow/Logic/` — for `Date()`,
`DebugToday` and `WeekCalendar.today` — beside the rest-day one it already had.

**The issue's list of ten call sites predates #209.** Four of the ten were in
`TodayView` and `TodayWidgetConfig` and went to `feature/daily-habits-2.0` with
the per-day kind. Six survive, and the enumeration found five more the issue
never listed:

- `WeeklyGridView.weekStart` established the week on screen through
  `startOfWeek(containing: Date())` — a different spelling, and the one place a
  grep for `WeekCalendar.day(Date())` would have missed.
- `ToggleHabitIntent` and `TapHabitIntent` each read the clock **three times**
  in one tap — the write, the week the goal is counted in, and the pop. That is
  the widget's own write path, so leaving them would have meant a widget tap
  landing on a different day from the one the widget drew as open. Each is now
  one read, handed down. (`TapHabitIntent` went with #209 before this landed.)
- `MonthProvider.entry(for:)` establishes today as `entry.date`, which
  `MonthWidgetView` reads back as today. Its *refresh policy* still runs off the
  real clock: when to reload is not a thing the override has an opinion about.
- `DemoHistory.seed(now:)`. Handled at the Settings call site rather than by
  changing the default, because `now` is an *instant* normalized by that type's
  own calendar, and a default of `WeekCalendar.today()` would hand a midnight
  taken in one calendar to a store built on another. The suites here inject a
  UTC calendar, so that is not hypothetical.

**Three fences, and each of them exists because the failure is a write.** A
forgotten override does not merely mis-render; it dates real rows to the wrong
day, and once written nothing in the store distinguishes them. So: the stored
day is compared against the real current week and cleared when it falls outside
it; `GlowApp.init` clears it at every launch, before the store is opened; and a
persistent banner sits on every screen that reads it, clearing it in one tap.
The banner is the one that matters most — the other two bound how long a
mistake lasts, and the banner is what stops it being made.

**It ships in every build, not behind `#if DEBUG`.** A `#if DEBUG` version
compiles out of every Release archive, including the one installed through
TestFlight, which is where this app is actually used. That is the same tier as
demo history, and it is why the footer says in plain words that what you log
while it is on is logged for real.

**The banner's padding is applied inside its own `if`.** Padding applied by the
caller is still padding when the banner is absent, which would put a 10pt gap
above every screen whenever the override is off. The change has to be inert with
the override off, and the render baseline is the evidence: no frame moved.

## An upper bound needs something under it (#219)

`WidgetRenderDiffTests.openSpanKeepsBothArcs` claimed that an open span
*crosses* the rest day rather than lighting it, and offered `wednesday < 60` as
the evidence. Sixty was derived from nothing, and — the part that matters — a
column with nothing painted in it satisfies it perfectly. The same shape as the
near-miss #199 was filed for from the other end, where a band of `20...26` went
empty when the palette moved to 36.

**It was already passing on emptiness.** The issue supposed the bound was
holding because the rest day's mark composites to 36. Measured, that column
reads **0** at the two places this test samples: `brightestInRestColumn` steps a
quarter-slot either side of the centre to avoid the rest cut, and the window
`RestWindow` subtracts from the span means there is nothing else there. So the
assertion was gating on an empty region rather than on the subtraction it was
written for, and had been since #71 put the cut in the middle of the column.

**The fix is a relationship, not a level.** Four quantities out of one frame —
the two lit arcs, the rest day's own line down the centre of its column, and the
window either side of that line — and three claims between them: the line is
there (`> lineFloor`), the line is unlit beside the arcs, and the window holds
no more light than the line does. `isUnlit(_:beside:)` is a quarter of the
frame's *own* lit level, which sits far above 36 and far below 255 without
naming either, so it survives the next palette move. #194 moved the grey
thirteen levels underneath a bound of 60 and nothing noticed.

**Proved in both arms**, by perturbing the widget and re-running the one test.
The old bound and the new claims were evaluated side by side in the same run:

| perturbation | old `wednesday < 60` | new claims |
| --- | --- | --- |
| rest cut filled `.clear` — the mark is not drawn | **passes** (window 0) | fails: line missing (0) |
| rest cut filled white — the mark is lit | **passes** (window 0) | fails: line lit (255 beside arcs at 255) |
| `restWindow` forced to nil — the span crosses | fails (window 255) | fails, on both the line and the window |

The third arm is the regression the test was written for, and the new form still
catches it; the first two are what the old form could not see. Reverted, the
suite is green and no frame in the render baseline moved — this changed what the
test demands, not what the widget draws.

**The rest of the file was left alone, deliberately.** `metGoalStopsBeforeSunday`
and `metGoalIsCutInTheMiddle` bound the rest column with `< clear` and have the
same one-sided shape — measured, they read 0 and 1 beside a rest cut at 36, so
they are vacuous today too — and `groundIsPureBlack` and `noHueAnywhere` would
both pass on a blank frame. Catalogued in #226 rather than fixed here, the way
#199 catalogued the bands: one reviewable change at a time.

## The other four one-sided bounds (#226)

The follow-up #219 filed rather than fixed. Four assertions in
`WidgetRenderDiffTests` with the same shape — an upper bound, or a whole-frame
claim, with nothing under it — and they are not equally urgent, so they were not
treated equally.

**Two were measurably vacuous and are fixed.** `metGoalStopsBeforeSunday` says
the met-goal line stops at Saturday and offers `sunday < clear` as the evidence;
`metGoalIsCutInTheMiddle` says the line is cut in two and offers
`wednesday < clear`. Rendered and printed, those regions read **0** and **1**
beside a rest cut that reads **36** down the centre of the same column.
`brightestInRestColumn` steps a quarter-slot around the cut on purpose and the
span has been subtracted there, so both bounds were being satisfied by emptiness
— delete the rest day's mark and both still pass. The floor each has on the
*neighbouring* column does not notice, because it is in another column.

The fix is the pairing `restCutStartsAndStopsOnAHabit` already uses, and the two
helpers #219 added: the rest day's own line is there (`> lineFloor`), and it is
unlit beside this frame's own lit dots (`isUnlit(_:beside:)`). A claim about
absence is worth something only next to a claim that the same column was drawn.

**`clear` stays a level, deliberately.** The two helpers are not
interchangeable. `isUnlit` asks whether a tone is grey rather than white and
admits everything up to a quarter of the frame's lit level; what these two scans
rule out is a *grey line* running where it should not, which sits well inside
that. Swapping `< clear` for `isUnlit` would have widened the hole rather than
closed it. `clear` is a level against the ground rather than against the
palette, so it does not move when the palette does.

**Proved in both arms**, by perturbing the widget and re-rendering, with the old
bound and the new claims read out of the same frame:

| perturbation | old form | new claims |
| --- | --- | --- |
| rest cut filled `.clear` — the mark is not drawn | **passes** (0 and 1) | fails: line missing (0) |
| rest cut filled white — the mark is lit | **passes** (0 and 1) | fails: line lit (255 beside dots at 255) |
| `restWindow` forced to nil — the line crosses | fails (36 and 37) | fails, on the same bound |

The third arm is the regression both tests were written for, and the new form
still catches it, because the bound that catches it was kept.

**The other two are left alone, and that is the decision.**
`groundIsPureBlack` (`share > 90` is 100 on a blank frame) and `noHueAnywhere`
(`worst <= 1` is 0 on one) are whole-frame claims stated as if they stood alone.
They do not stand alone: `RenderBaselineTests` holds all four families
individually, against a committed 16 × 16 grid of mean brightness, the same
exact-black share, and a census of the tones each family paints. Measured rather
than assumed — `month small` was blanked and the two suites run together. That
gate went red three ways at once for that family (a cell moved 23 against a
tolerance of 3; the black share went 90.2% → 100.0% against a tolerance of 0.5;
the level-36 tone went 680 pixels → 0) while `groundIsPureBlack`,
`noHueAnywhere` and `haloIsWhatLiftsIt` all stayed green. A content floor here
would restate, more weakly, a gate that already exists. Both tests now name it,
so the next reader does not file this a third time.

**Found while in the file and not acted on.** `metGoalIsCutInTheMiddle`'s "the
left piece is missing" floor samples Tuesday, which is a *logged* day in that
fixture: the column reads 255, the lit dot, not the line's 36. It is not vacuous
— a blank column fails it — but it is not measuring the line either, and it
would go on passing if the line under the dot were lost. Fixing it means moving
where that scan samples or changing the fixture, which is a different change
from this one. The code says so where it samples.

## Tinted and Clear stay glass (#53)

**2026-08-22.** Closed, accepted rather than fixed. `containerBackgroundRemovable(false)` was built, measured on device, and does not do what the issue wanted: on iOS 26 that flag governs contexts with no background at all — StandBy, the iPad Lock Screen gallery — and Tinted and Clear are a restyling of the Home Screen, not one of those, so both still substitute glass regardless of the flag. A black image drawn as ordinary content inside the container fails the same way, silently. Worse than the background: the halo does not survive Tinted or Clear either, with or without the flag, so a lit mark already reads as a bright shape rather than a glow one layer before the background question even applies.

No mechanism was found. The design argument for pitch black in every appearance is unchanged and not wrong; there is simply nothing in the current API surface that grants it. Georg's call: stop paying a real cost (StandBy, the iPad Lock Screen gallery, foreground tinting) for a change that would not have worked anyway, and accept the platform default for Tinted and Clear.

**What this does not reopen.** #111's grey-as-`ShapeStyle` resolution does not depend on this — it was built to survive accented rendering regardless of whether the background is ever forced to black, and the measured hierarchy (Default 255/23, Tinted 255/149, Clear 255/162) holds under the platform default exactly as it would have under a forced one. Nothing about closing this changes that.

**If this is ever reopened**, it needs a new mechanism to have appeared — a future `containerBackgroundRemovable`-shaped API that actually distinguishes Tinted/Clear from StandBy, or a way to keep the halo under accented rendering — not a second attempt at the same flag.

## A presence claim that landed on the wrong mark (#230)

The third variety in the family #219 opened and #226 catalogued, and the
hardest of the three to see by reading: not a bound with nothing under it, but
a floor that measures something real and unrelated to what it claims.

`WidgetRenderDiffTests.metGoalIsCutInTheMiddle` says a met-goal span with
Wednesday resting is drawn as two pieces, and evidenced the left one with
`tuesday > lineFloor`. Wednesday's window cuts that span at columns `0...1` and
`3...6`, and the fixture logged Monday **and Tuesday** — so both columns of the
left piece carried a lit dot and the floor read **255**, the completion, rather
than the line's 36. A completion dot is there whether or not the span was
drawn.

**Measured, not reasoned.** Rendering the frame and printing the row:

| sample | `done: [0, 1]` | `done: [0, 4]` |
| --- | --- | --- |
| `columnCentre(1)` — the floor's own scan | 255 (the dot) | **36** (the line) |
| a quarter-slot either side of it | 39 | 37 |
| midway between columns 0 and 1 | 38 | 37 |
| `columnCentre(3)` — the right piece | 36 | 36 |

**The issue's premise was half right.** It supposed no sample point could be
moved to, because both columns of the left piece are logged. True at column
granularity — but sub-column points do exist and do discriminate: erase the
left piece and the quarter-slot sample falls 39 → 3, the midpoint 38 → 2, both
under `lineFloor`. What the sweep also shows is why they are the weaker
evidence. Nowhere in the left piece does the line read 36 with that fixture:
the two dots' halos raise the whole two-column piece to 38–39, so any floor
there is reading the line plus two or three levels of light it did not ask for,
and the distance to a floor of 15 is halo the palette can move. On the far side
of the cut, where no dot is near, the same line reads exactly 36.

**So the fixture moved instead**, by one column: `done: [0, 4]` — Monday and
today — rather than `[0, 1]`. The goal is met either way, so `WeekSpans` still
returns one span across the whole week and the cut is the same cut; what changes
is only which columns carry dots. Tuesday now carries the line and nothing else
and the floor stays exactly where it was, which is the point: the assertion is
unchanged and now means what it says.

The fixture is per-test — every call to `oneHabit` builds its own entry — so
`metGoalStopsBeforeSunday` and `daysCarryTheLight` keep theirs, and no frame in
the render baseline moved.

**Proved in both arms.** The left piece was erased in `SlotMarkView` — the
span's line masked off everything before `restWindow.lowerBound`, leaving the
right piece and both dots alone — and then `RestWindow` was forced to nil, with
both fixtures read out of the same run:

| perturbation | old fixture `[0, 1]` | new fixture `[0, 4]` |
| --- | --- | --- |
| the span's left piece not drawn | **passes**: Tuesday 255, the dot | fails: left piece missing (0) |
| `restWindow` forced to nil — the line crosses | fails: Wednesday 37 | fails: Wednesday 36 |

The first row is #230: the old floor is green with the thing it names missing.
The second is the regression the test was written for, and the new fixture still
catches it.

**And both floors now say which mark they found.** `isUnlit(_:beside:)` on the
left piece and on the right, against the frame's own dots — a floor says a
column is not empty, and a column is not empty for lots of reasons. Naming the
tone is what stops the next fixture edit putting a dot back on a sample point
without anything noticing.

## A fresh install chooses its starting point (#228)

**2026-08-23.** `HabitSeeder` is deleted. A fresh install used to open with
`DefaultHabits.all` already in the store; it opens on the empty state now, which
offers two buttons — **Add Your First Habit**, and **Start with a Pre-Selected
Set** which installs the same eight habits on a tap.

**What is being traded, stated plainly.** #123's seeder existed so that a first
launch showed what the grid is *for* rather than an empty screen and a plus
button, and that reasoning was good: an empty tracker teaches nothing about
itself. What replaces it is not an empty screen — it is the same demonstration
turned into an offer. The screen still says what the app is about (the empty
state's icon is a real slot rendered by the real code path, and on a device it
glows there before there is anything to track), and the list is one tap away
instead of already decided. The cost is one tap on the way in. What is bought is
that nobody arrives at a list of eight habits they did not choose and has to
delete them to disagree.

**The flag goes with it, and that is the part worth checking.**
`didSeedDefaultHabits` existed to answer "has this install ever been seeded",
which is a different question from "is the store empty" — and #140 recorded, at
some length, that answering the second with the first makes a tracker impossible
to empty: delete every habit at night and find them all back in the morning.
That failure needs an automatic insert to happen at all. With nothing seeding by
itself, an empty store is one state, however it got there — nobody has added
anything, or everything has been deleted — and both want the same two buttons.

**Verified rather than reasoned**, on an iPhone 17 Pro simulator: the curated
set installed from the empty state, then every habit deleted (each habit leaves a
blank row, so emptying the grid is two passes — #143), leaving the two-button
empty state; then home, terminate, relaunch — and the empty state again, with an
empty store. The one regression this change could plausibly have introduced is
the one that used to need a flag, and it is not there because there is no longer
anything that could cause it.

**`resetToDefaults` rather than a revived seeder.** #193 split `insert` out of
`addAll` precisely so the reset and the seed shared one definition of "the
defaults go in", and the empty state's button calls the reset directly. Its name
describes a reset because #193 built it for a store with something in it; on an
empty store, resetting and seeding are the same act, so no special case is
needed. It is also why the button needs no confirmation: destructive is a claim
about what the store held, and this caller is only ever on screen when it held
nothing.

**"You can edit them anytime" is on the screen, not behind it.** The one
hesitation a pre-selected set raises is *am I stuck with these?*, and the answer
belongs where the question is asked — a second sentence in the empty state's
description — rather than in a confirmation sheet after the tap. Every habit it
installs is an ordinary habit: rename, retarget, reorder, delete.

**Both buttons are drawn, not styled.** The primary is a `Text` over a filled
`Capsule` for #162's reason — the root tint is pure white and `.borderedProminent`
fills with it, which measured 8077 interior pixels of one colour with no label in
them. The secondary is plain text on the app's black, which is the same trap's
opposite: the trap needs a filled background to take the tint, and there is no
fill here. Measured on the fresh-install screenshot rather than assumed: the
capsule's interior is 84.2% white with **5,021 pure-black pixels of label** in
it, and the secondary's band is black with **6,413 white pixels of label**. Both
say something.

**What this does not touch.** `DemoHistory` — a separate concept, invented
*completions* on top of whatever habits exist, still behind its Settings toggle,
and still the only thing in the app that fabricates history; the curated set goes
in with an empty grid. And #193's Reset to Default Habits, which is the same call
from a different place: a typed, destructive confirmation over a store somebody
has used, versus a first-run choice on a store that holds nothing.

**What the tests did.** The suite kept the claims that still have a subject and
retargeted them at `resetToDefaults`: the curated set goes in with no
completions, every row of it is open today, a set that could not save leaves the
store empty and the tap can be repeated. Four went, because what they asserted
does not exist any more — seeding runs once per install, a lost flag converges
rather than duplicating, an install with habits is left alone, and a reset does
not re-arm first-run seeding. `ForgetfulDefaults`, the test double that took a
write and did not keep it, went with the flag it was built to lose. `GlowTests`
runs 469 against a floor of 398, so no floor moved.

## The unlit grey moves again, to #2B2B2B, and stops there (#240)

**2026-08-23.** `GlowPalette.greyOpaque` goes from `#242424` (36,36,36) to
`#2B2B2B` (43,43,43). Same one declaration, same everything-moves-with-it as
#194: the resting habit name, the weekday letter that is not today, the ✕ on an
unlogged day, the rest cut, the socket on a day still to come, the year's empty
day.

**Why 43 and not 44, computed rather than trusted.** `increasedContrastIsTheOldGrey`
holds the shipping grey under **1.5:1** on black, and the comment beside that
bound named 44/255 — `#2C2C2C` — as the value that ratio stands for. It is not.
Through the same WCAG formula the test itself uses:

| level | contrast on black |
| --- | --- |
| 36 (`#242424`) | 1.3528:1 |
| 42 | 1.4631:1 |
| **43 (`#2B2B2B`)** | **1.4832:1** |
| 44 (`#2C2C2C`) | 1.5037:1 |

44 is *over* the bound rather than on it, so the value the old comment offered as
headroom would have failed the test that was written to allow it. 43 is the last
level that clears `< 1.5`, and the comment is corrected in place rather than left
to be repeated. #197's closing line carries the same 44/255 claim and is
corrected there too.

**So this move spends the guardrail rather than working inside it.** The
brightest grey a nudge can reach is now what ships. If the report comes back a
third time that the unlit marks are too dark, the thing being asked for is a
*higher bound*, which is a design decision about whether "unmistakably not lit"
still means what #111 and #194 meant by it — to be argued in the open, not
backed into by picking a fourth number that happens to clear a test nobody meant
to move.

### The tone census caught it, by name, on every family that paints grey

This is the first real exercise of #199's second statistic, and of the three
rewrites (#219, #226, #230) that moved assertions off levels and onto
relationships. Reported here either way, since the point of a gate is what it
does on a change nobody wrote it for.

**`RenderSignature.toneExcess` fired on all four families, and named the move.**
Rendered with the palette at 43 while `flatTones` still said 36:

| family | excess at 36, baseline | excess at 36, after the move |
| --- | --- | --- |
| week small | 1068 | 12 |
| week medium | 2068 | 37 |
| week large | 4132 | 40 |
| month small | 680 | 2 |

`flatTonesAreReal` went red beside it — "no family paints anything flat at level
36 — the most any of them has is 40, in week large" — which is the check that
stops a palette move from being re-approved into a gate comparing zero with
zero. Moving `flatTones` to 43 then fired the *other* branch on all four
families ("now paints 4015 pixels flat at level 43, where the baseline recorded
0"), which is the same event seen from the other side.

**The cell grid stayed green again**, exactly as #199 said it would: worst cell
+2 against a tolerance of 3, on a seven-level move. #194's thirteen levels
arrived as +3. The geometry gate is not a colour gate and this is the second
change to demonstrate it rather than argue it.

| frame | cells moved | worst | exactly-black | tone census |
| --- | --- | --- | --- | --- |
| week small | 17/256 | +2 | 70.2% → 70.2% | 36: 1068 → 43: 1062 |
| week medium | 20/256 | +2 | 73.6% → 73.6% | 36: 2068 → 43: 2007 |
| week large | 24/256 | +1 | 84.1% → 84.1% | 36: 4132 → 43: 4015 |
| month small | 18/256 | +2 | 90.2% → 90.1% | 36: 680 → 43: 682 |

Every moved cell moved **up**, none down, and the count of pure-white pixels is
identical in all four frames (564, 2303, 2394, 39) — the evidence that this is
the same picture at a different level rather than a different picture. The
baseline was re-approved from the run that produced it.

**The relationship assertions survived untouched**, which is what #219 and #226
were for. `isUnlit(_:beside:)` compares a tone against the lit marks in its own
frame (43 × 4 = 172 against 255) and never saw the move; `lineFloor` (15) and
`clear` (10) are levels against the *ground* rather than against the palette,
and neither moved. Nothing in `WidgetRenderDiffTests` needed a new number except
the one literal that is documented as tracking the palette.

### The one place the rewrite did not reach, and what it measured

`renderIsReal` counts pixels inside a narrow band around the grey as evidence
that something unlit was drawn — 33...39 for `#242424`. Its comment says the
band is a function of the palette and moves with it, which is true and is what
this change did: it is 40...46 now.

**But it did not go red first, and that is the finding.** Run with the palette at
43 and the band still at 33...39, the test passed. Measured on the render it
writes out, 676 × 708: **5,315 pixels** fall in 33...39 with nothing painted
there, against a floor of 500 — halo gradient, not marks. The band it was
checking was empty of *tones* and full of *ramp*. For comparison, the same frame
holds 8,042 pixels in 40...46, of which **5,824 sit at exactly 43** against ~420
at each neighbouring level: the spike the census reads.

So the "narrow band" argument the comment makes — that a band reaching to 141
would pass on halo bleed alone — turns out to apply at seven levels wide too, at
least in the large frame, where there is a great deal of halo. The band has been
moved because that is what its comment requires, but what it now demonstrates is
that a *count inside a band* is weak evidence in a frame with gradients, and that
the census next door is the check actually doing this job. Left as a finding
rather than a rewrite: changing what `renderIsReal` asks is a separate decision,
and this change had no business making it while moving a colour.

### What is not verified here

The simulator has no EDR headroom, so every halo in every frame above is drawn at
SDR strength. Whether 43 reads as unlit **beside a real halo**, and whether it
reads as findable at all on a phone, is the question #197 asks and it is still
open — its subject is now `#2B2B2B` rather than `#242424`, which is noted on the
issue. This entry records geometry, level and gate behaviour, all of which the
simulator settles; it does not record what the change was made for.

## An enabled chevron that does nothing is two week starts an hour apart (#242)

The back chevron was reported lit and completely inert — not the habit rows, not
even the title, which is the part that narrows it: `weekStart` itself never
moves. #242 read the path end to end, found nothing wrong with it, and concluded
that the next step was a device and two log lines, because the chevron's
*enabled* state needs multi-week history and that could not be built in the
simulator.

**It did not need a device.** The chevron's enabled state and its action are two
reads of one `WeekReach` — enabled when `weekStart > reach.earliest`, and the
action is `reach.step(weekStart, by: -1)` — so "enabled and inert" is a rule
over `Glow/Logic/` with no view and no store in it:

> if `weekStart > reach.earliest`, then `startOfWeek(reach.step(weekStart, by:
> -1))` is not `startOfWeek(weekStart)`.

Stated on the *week* rather than on the `Date`, because `show(week:)` skips only
when the new value equals the old one: a step that moved `weekStart` by an hour
would still assign, and nothing on screen would move, because the title and the
grid are both drawn from the week and not from the instant. A step that changes
the date but not the week is a dead button with extra steps.

**The rule is false, and where it is false is `WeekCalendar.startOfWeek`.** Swept
over nine time zones, three week starts, a year of days, three times of day and
two record lengths — 777,141 enabled-chevron checks — it fails in exactly one
class of zone: the ones that move their clocks *at* midnight rather than at two
or three in the morning. Havana, Chile, Brazil until 2019. `DayIdentityTests`
already carried one of those for R4; this is the same fact arriving at a
different surface.

`startOfWeek` normalized its argument to midnight and then subtracted days to
reach the week's first one. Day arithmetic keeps the wall-clock time, and a wall
clock reading midnight is not always the start of its day:

- **2025-03-09, Havana.** The clock goes from 23:59:59 to 01:00, so that Sunday
  has no 00:00 at all and `startOfDay` answers 01:00. Six days back from it
  carried the 01:00 along, so the week's Monday came out at 01:00 — while the
  same Monday reached from any other day of that week came out at 00:00.
- **2026-11-01, Havana.** The clock goes back from 01:00 to 00:00, so that
  Sunday has two midnights. `startOfDay` answers with the first; day arithmetic
  landed on the second.

Either way the function answered with two instants an hour apart for the same
week, depending on which day of it was asked about — and the pager compares one
against the other. `reach.earliest` comes from the record, `weekStart` from
today, `weekStart > reach.earliest` was true by that one hour, the chevron drew
enabled, and stepping back clamped to `earliest`: a different `Date`, the same
week, nothing on screen. Exactly the report.

**The fix is one `startOfDay` after the arithmetic rather than only before it**,
in `startOfWeek` and in the seven days `week(containing:)` hands out. `Week`
documents those as midnights and they were not: a two-year sweep over eleven
zones found 228 columns that were not their own day's midnight, and 168 of them
survive fixing `startOfWeek` alone, because the week start's wall clock is
carried into the six days after it.

**`WeekReach.from`'s cap is normalized in the same change, and it is not the
bug.** The cap is twelve weeks of *days* back from a week start, which is the
same weekday but not reliably the same instant, and an `earliest` that is not a
week start is compared against week starts by `contains`, `clamped` and the
pager's own `.disabled` — 1,336 such floors in the sweep. Measured both ways:
with only the cap normalized the sweep still fails 14 times, and with only
`startOfWeek` fixed it fails none. Both ship because both are wrong; only one of
them was #242.

**What it looks like from outside, exactly — one dead press, not a dead
button.** Run the view's own state machine over the failing case (`weekStart`
from `today()`, the chevron's `.disabled`, `step`, and `show(week:)`'s guard)
and the sequence is: the chevron draws **lit at the floor of the reach, where it
should be dim**; one press assigns a `weekStart` an hour earlier; the title and
the grid do not move, because the week did not; and the chevron then dims
correctly. That is the reported symptom word for word — not dimmed, tapping it
does nothing at all, the title text does not change either — and the report
describes a press rather than a series of them. The shortest path to it is also
the likeliest: a store only a few days old, so the floor *is* the current week,
on one of the two days a year that zone's clock moves.

**What it does not explain, and the claim is deliberately narrow.** A chevron
that stays lit across repeated presses, or one in a zone that does not change
its clocks at midnight. Neither of those is this bug, and #242's last hypothesis
— a `ToolbarItem` holding a closure from an earlier render — is unspent rather
than disproven: nothing here says that cannot happen, only that a `WeekReach`
this app can hold answers the chevron's two questions differently without any
help from SwiftUI. If the report comes back from Berlin, it is still open.

**The `?? weekStart` and `?? latest` fallbacks are not reachable**, which is
worth stating because a nil there would make `step` a genuine no-op with the
button enabled. `Calendar.date(byAdding: .day, ...)` on a Gregorian calendar
returned nil in none of 280 probes at `.distantPast`, `.distantFuture` and ±10¹²
seconds from the reference date, across five zones and all seven week starts,
and in none of the 14.5 million steps of the exploratory sweep. They are
defensive, and the dead chevron was never coming from them.

**The invariant is now a test rather than a finding.** `WeekReachTests` sweeps
it per zone and asserts the sweep swept something — a zone that quietly produced
no enabled chevron would otherwise pass by asking nothing — and keeps both
Havana dates as named cases, because a range that happens to contain a date is
weaker evidence than the date.

### What the empty state stopped saying (#243)

**2026-08-23.** The screen above is two buttons now. The 54×54 slot, the "No
Habits" title and the description sentence are deleted, and
`ContentUnavailableView` went with them — its shape is icon-and-title,
description, actions, and a screen that fills one of those three slots is
fighting the type rather than using it. What is left is a `VStack` of the two
buttons, centred, drawn exactly as #228 drew them.

**Both losses are real, and neither is an oversight.** The icon was the first
lit thing on a fresh install — the one thing the app is about, rendered by the
real code path, glowing on a device before there was anything to track. The
description's second sentence answered the one hesitation a pre-selected set
raises, *am I stuck with these?*, at the moment it is raised rather than in a
confirmation sheet after the tap. With it gone, the button's own label is the
whole of what says what the tap does; the answer *is* still true — every habit
the set installs is an ordinary habit — and it is now written in SPEC §2 and
nowhere on the screen. Shortening the sentence rather than deleting it is a
live alternative and was not what was asked for here.

**The accessibility question, measured rather than reasoned about.**
`ContentUnavailableView` was assumed to announce its three parts as one unit,
which would have made the plain stack a real regression for VoiceOver. It does
not. The accessibility tree, walked out of a hosted `WeeklyGridView` over an
empty store, held four separate elements before the change:

| | element | trait |
| --- | --- | --- |
| 1 | "No Habits" | static text |
| 2 | "Add a habit and today's slot will be waiting for you. Start with the pre-selected set and you can rename, retarget, reorder or delete any of them." | static text |
| 3 | "Add Your First Habit" | button |
| 4 | "Start with a Pre-Selected Set" | button |

and two after it — elements 3 and 4, both enabled buttons, in that order. **The
icon produced no element at all**, which is the fact the decision turns on: it
was never part of what this screen said out loud, so what a screen reader loses
here is exactly what a sighted reader loses — the title and the sentence, gone
from both at once. Parity holds, so **no `.accessibilityLabel` was added**.
Adding one would have made the screen say more to VoiceOver than it shows to
everyone else, which is a different decision — restoring the sentence for one
audience only — wearing an accessibility fix's clothes. The screen is not
contextless either way: the toolbar still carries "This Week" and the plus
button, and "Add Your First Habit" only exists on a store with nothing in it.

**VoiceOver itself was not run.** It does not run in the Simulator, and driving
the host machine's screen reader was not available in this environment, so the
tree above is what the accessibility server hands out — the same data VoiceOver
speaks — rather than a recording of it speaking. What that measurement cannot
answer is announcement *order* and phrasing: it is the tree, not the utterance.

**And the buttons are pressed the way a screen reader presses them.**
`EmptyStateAccessibilityTests` activates each element with
`accessibilityActivate()`, which is what VoiceOver's double tap calls: the
second installs `DefaultHabits.all` with no completions, the first presents the
editor and leaves the store empty. Four tests, and the first of them fails if an
invisible third element ever appears — so adding one stays a decision.

**Read off the screenshot, not the diff.** iPhone 17 Pro simulator, fresh
install: no icon, no title, no paragraph, two centred buttons. #162's white-on-
white trap is still absent — the capsule's interior measures 89.1% white with
**5,610 pure-black label pixels** in it, and the secondary's band is black with
**7,374 white label pixels**. Both say something.

### An accessibility test needs accessibility switched on (#245)

**2026-08-23.** `EmptyStateAccessibilityTests` was green on the machine it was
written on and red on every CI run, with all three hosted-view tests failing the
same way: the accessibility tree was **empty**. Not a wrong label, not a crash —
no elements at all.

**The cause is not layout, and not the window.** The obvious suspicion was the
harness's window: it joins the host app's scene only `if` one exists, and a
`UIWindow` outside the accessibility hierarchy vends nothing. Instrumented on an
erased simulator, that is not what happens. One `UIWindowScene`, foreground
active; `window.windowScene` non-nil; the window key; `host.view.window` set;
the view laid out at 402×874 with the navigation bar measured at its real
frame. The hierarchy is on screen and correct.

What is missing is the accessibility runtime. UIKit loads the accessibility
bundles into an app only when the device says accessibility is enabled, and on a
device where it never was, `_AXSApplicationAccessibilityEnabled()` is false, the
UIKit accessibility bundle is absent from the process, and **every node reports
`isAccessibilityElement = false`** — the buttons, the hosting view and UIKit's
own navigation bar alike. An empty tree is what an absent runtime looks like,
which is exactly why it read as a layout failure and is not one.

**Why it split by machine.** `Tools/test.sh` erases the simulator on CI, so CI's
phone is always a fresh one. Of the simulators on the machine the suite was
written on, exactly one carried `ApplicationAccessibilityEnabled`, left by some
earlier session that had turned VoiceOver on; the suite was measured and run
there. The tests were never CI-specific — they fail on any simulator that has
never had accessibility switched on, which is how the diagnosis was made
locally rather than by pushing to CI.

**The fix is to state the requirement rather than work around it.**
`Tools/test.sh` now writes `AccessibilityEnabled` and
`ApplicationAccessibilityEnabled` into the chosen simulator's
`com.apple.Accessibility` domain before handing the device to `xcodebuild`. It
cannot be done from inside a test: the preference is read as the test host
launches. Proof that this and nothing else is the difference — the same built
binary, on the same machine, in the same minute: on the erased device three
tests fail with an empty tree; on a device differing only in those two
preferences, all four pass and the walk finds the two `AccessibilityNode`s
labelled "Add Your First Habit" and "Start with a Pre-Selected Set".

No assertion was relaxed and nothing is retried or skipped — a poll loop around
an empty tree would only have bought a slow red test and eventually a flaky
green one, and `Tools/validate-test-result.py` fails a run that skips anything.
The suite carries a comment saying what it needs, because it is the only one in
the repository that hosts a live view and now the only one with a requirement on
the device: a hand-typed `xcodebuild test` on a fresh simulator still fails
these four and nothing else, and that shape of failure is the diagnosis.

**What this does not change.** The measurement in the entry above stands. It was
taken with accessibility on, which is the condition a VoiceOver user is in — the
tree the tests walk is the tree the accessibility server hands out. That
`ContentUnavailableView` vended four separate elements rather than one, that the
icon vended none, and that the empty state's spoken content is exactly its two
buttons are all unaffected.

## The Widgets tab is part of the target (#235)

**2026-08-24.** `docs/vision.md` named three screens — Today, This Week,
Settings — while the app shipped Widgets, This Week and Settings. Two things had
produced that gap and only one was written down: #209 took the Today screen out
and the document was corrected in a single place, and #210 put a Widgets tab in
the slot it vacated and the document never mentioned it at all.

`CLAUDE.md` says what vision.md is: "the target… where the code disagrees with
it, the code is the backlog." Read literally, the gap made the Widgets tab
backlog — something to remove. That is not what it is.

**The answer is that the Widgets tab is part of the target**, not a tenant of
Today's slot until the per-day kind returns. #210's own title says the Today tab
"becomes" a Widgets tab and its body says the slot is "repurposed rather than
removed", which reads like a placeholder; what #225 built is not one. It asks
`WidgetCenter` what is actually on the Home Screen, previews the shipping views
over the person's own habits, and diffs the two by family rather than by kind.
#237 then took the explanatory prose off it and varied the per-habit previews,
and #238 moved it to the front of the bar. None of that is slot-warming.

The argument underneath it is vision.md's own strongest claim — the widget is
the main product, and the app is where you go when the widget is not enough. A
screen whose job is showing you every widget you could have, drawn by the code
that draws them, is that claim made literal, and it is why the tab leads. **It
is not the stronger claim**, and vision.md now says so in the same breath: the
app is not a widget installer. This Week is where the work happens and where
every launch lands. A screen can be the purest statement of what a product is
and still be the least visited one.

**So this revision went the other direction, once.** `## Three screens` was
brought up to the code rather than the code being brought up to it, and
vision.md says that about itself at the top, with the date. The alternative —
correcting it silently — leaves the next reader unable to tell a decision from
drift, which is the failure the *kept in sync, dated, or deleted* rule above
already exists to prevent.

**What else the same pass found false**, none of it noticed by the issue: the
`## Settings` section described its contents as "the two things that are neither
today nor this week" and pointed at History as "what the year screen is today",
which stopped being a screen when it became History; `## A habit is one kind or
the other` still said the two kinds are "what splits the first two screens",
which they no longer do in either direction — one kind ships, and the first two
screens are the widgets and the week; and the widget section said both of the
first two screens exist because somebody wanted more room than a widget, which
is not true of the Widgets screen. The Today subsection moved into
`## Deliberately later` whole rather than being deleted: the screen exists on
`feature/daily-habits-2.0`, and vision.md is the document that says what is
coming back.

**The cold-launch paragraph was wrong in a new way**, which is the subtle one.
It said This Week opens on a cold launch, with a note that in the shipped app
that is every launch. Still true — but after #238 This Week is no longer the
*first* tab, and a reader comparing the paragraph to the tab bar would find them
contradicting each other. They are not: `RootTabView` holds the landing screen
as `selection`'s default rather than as a consequence of declaration order,
precisely so the two can differ. The first tab says what the app is about; the
landing tab says what it opens to. vision.md now says that where it says the
rest.

## The twelve-week cap, removed (#186)

**2026-08-24.** The week pager reaches as far back as the record does, and
`WeekReach.maximumWeeksBack` is deleted. Both looking and editing are uncapped;
splitting them — see further than you may correct — was considered and refused.
This reopens #117, which is a decision rather than a rediscovery, and it is
Georg's call.

**What the cap was for, and why neither reason survives.** It had two, and they
are not the same kind of claim.

- *The record is not a bound anybody can feel.* Twelve weeks is a quarter, and
  a tracker that lets you edit a quarter of a year may be a tracker whose record
  cannot be trusted — #186 asked whether six weeks or four would make the past
  more nearly fixed. That is a real argument about how much rope a person gets
  and it was **overruled deliberately**: the pager pages back, and edits, as far
  as the record genuinely reaches. Nothing in the code decided this and nothing
  in the code could.
- *`Habit.createdAt` defaults to `.distantPast`.* `HabitStore.earliestRecordedDay`
  returns the earlier of the first completion and the first habit's creation, so
  one row carrying that default made the record start in the year 1 — and an
  uncapped pager over that is a scroll with no end. That half was simply true,
  and it is **fixed at its source**: the default means *unknown*, not *the year
  1*, and a sentinel is now refused where the tables are read.

The second is the whole risk of the change and was fixed first. The predicate is
the fetch's, not a filter after it: `fetchLimit = 1` over an ascending sort by
`createdAt` returns the sentinel row and hides every real date behind it, so
filtering afterwards would have answered "the year 1" exactly as before.

**A habit with the default date and no completions answers nil — no reach.**
This is the case where the sentinel is the only signal, and the three candidate
answers are nil, today, and some invented floor. Invented floors are out on the
app's own terms: light marks what happened, and opening twelve weeks of
correctable past for a store that holds nothing is offering to correct weeks the
record cannot vouch for. Nil and today produce the same reach — the current week
— and nil is the honest spelling of it, because it is also what an empty store
answers and the two stores know exactly as much about when they began: nothing.
#117's own sentence settles it, "a week before anything existed holds nothing to
correct".

**What that costs, stated rather than discovered.** One store loses reach it had
yesterday: a habit created before the `createdAt` column existed, never once
logged. It had twelve weeks of pager and now has none, and there is nothing in
those weeks to correct, because there is nothing in that store at all. Its first
completion is its record, from the day it is made. A habit created before the
column existed that *has* been logged is unaffected — its completions are the
record and always were.

**`WeekReach.from` still normalizes `earliest` through `WeekCalendar.startOfWeek`,
and that is load-bearing.** It landed hours earlier as half of #242's fix: an
`earliest` that is not a week start is compared against week starts by
`contains`, `clamped` and the pager's own `.disabled`, and in a zone that changes
its clocks at midnight the two can name one week an hour apart — a back chevron
lit at the floor, one dead press. The cap it used to normalize is gone; the
`startOfWeek` around the record's own start is not.

**Storage and rendering do not justify a cap, and the second half of that is
measured.** The history is SwiftData over SQLite and the grid draws one week at
a time. Eight habits over ten years is 29,200 completions, and on that store the
bounded read a week costs is the same read whether the week is recent or years
back: medians of eight alternated rounds in one process,
`HistoryProjectionTests.aDeepWeekCostsWhatAWeekCosts`, over two runs: **one
week back 7.18 and 7.57 ms, 300 weeks back 7.72 and 7.91 ms** — the two arms
half a millisecond apart on the same store in the same minute, and the gap
between runs as large as the gap between the arms. A deep week is a predicate
over a different range, not more rows.

What that measurement does not say is that a week is free. The same read on the
smaller store next to it — twelve habits, two years, 8,760 rows — is 3.2 ms, so
the cost of drawing a week does grow with the size of the history behind it.
That is the store's size and not the pager's depth, it is the same cost the
current week already pays, and it is what a bounded read looks like next to the
whole-history read it replaced: 234 ms.

**What the titles do with a much larger N.** #207's ladder — This Week, Last
Week, Two Weeks Ago, then the date range — is a switch over
`WeekCalendar.weeksBack`, which is days divided by seven rather than a
`weekOfYear` difference, and that choice is what survives the change: a count in
week numbers restarts every 1 January and could not express 315 weeks at all. A
hundred weeks back the pair reads "21 Oct – 27 Oct 2024" over "100 weeks ago",
which is a big number and the right one — the range is the identity and the
count is the distance. The year in the range title used to be argued from the
cap ("a week reachable from here is at most a quarter back"); the rule is
unchanged and now earns more of its keep, because the weeks that print a year
are exactly the weeks the cap used to hide.

**`SeededHistory` no longer constrains anything.** The cap had to exceed the ten
weeks the demo invents, and that was asserted as `SeededHistory.weeks <=
WeekReach.maximumWeeksBack`. Nothing encodes the constraint now; the test that
carried it asserts the demo's first week is reachable, which is what the
constraint was ever protecting.

**Tested at the depth the cap used to hide.** #242's sweep keeps its parameters
exactly — twelve weeks of enumeration, 86,349 enabled chevrons a zone — so its
numbers stay comparable to the ones the fix was measured against, and twelve is
now a sweep depth rather than a bound. Alongside it, a six-year record is walked
week by week from the current week to its first: every step must land on a
different week, the walk must take exactly one step per week of record, arrive at
`reach.earliest`, and stop there. Nine zones, three week starts, twelve days
spread across two years including both of Havana's midnight clock changes —
11,268 steps a zone.

## The pop defaults to everything, for a new install (#185)

**2026-08-24.** #185 asked the question and #119 had already supplied the reasoning without acting on it: the objection frequent pops raise — "twenty of these a day on a screen whose whole argument is that it says one thing" — is about the grid, and a pop was never on the grid. It is two seconds over the Island and leaves nothing behind. Georg's answer: people need encouragement. `PopPreferences.Level.unset.effective` moves from `.goals` to `.everything`.

**Only for a new install.** `unset` is the sentinel for "this key has never been written" — nothing else reaches it. An install that turned the feature on under the old boolean scheme has an explicit `1` stored, which resolves to `.goals` directly rather than through `unset`, and that path is untouched: `storedOnStillMeansGoals` still asserts it. So "everything by default" is exactly the asymmetry #185 named rather than backed into — new installs get encouragement, installs that already chose `goals` keep it.

`Tests/GoalPopTests.swift`'s `defaultIsOn` and `levelsAllowTheRightRegisters` moved with it; `storedOnStillMeansGoals` did not need to, and its lack of a diff is itself the evidence the compatibility guarantee held.

## Deleting a habit collapses its row; adding one appends

**2026-08-24.** #129 and #143 settled that a delete leaves a blank row where the habit was and the next habit added takes it — one pair, one idea: a row's existence is stable and only its contents change, so removing a habit never silently regroups the habits below it. #257 reverses both halves.

The reasoning behind the old behaviour was real and is not being called wrong. Collapsing a row *does* pull everything below it up a line, and on a grid somebody arranged that is a change they did not ask for. The entry above this one is left exactly as it was, because it remains an accurate record of why the app behaved that way.

**What it missed is what a delete means.** A row that is still there after you delete it reads as a delete that did not work — and it then has to be deleted a second time to actually go, so the cost of removing one habit is two acts and a moment of doubt in between. The regrouping the old rule was protecting against is visible and immediately undoable; the doubt is neither.

The reversal has to be both halves or neither. `addHabit` filling the first blank row only made sense as the mirror of `delete` leaving one: together they conserved positions. On its own it is worse than the old behaviour rather than better, because the only blank rows left are **deliberate** ones — the grouping — and consuming one would take away a separator somebody placed on purpose. That is the same failure as leaving a row behind, from the other side.

So: `HabitStore.delete` deletes every row outright, spacer or habit; `HabitStore.addHabit` always appends; `firstBlankRow()` is gone with its only caller.

**The half of #129 that is not about layout survives, and is stronger for it.** A deleted habit's `id` had to stop resolving, because widget configurations and widget intents both resolve by `id` — a configured widget would otherwise start showing an unrelated habit, and a tap from a widget snapshot taken before the delete would land as history on whatever came next. That used to be arranged by giving the surviving blank row a fresh `UUID`. Deleting the row removes the `id` along with it, which is the same guarantee without the row that carried it.

`Tests/SpacerIdentityTests.swift`, `Tests/SeedingTests.swift` and `Tests/PersistenceTests.swift` each carried an assertion of the old rule; all three now assert the new one and say in the test which way they were turned. Two new tests hold the parts that are easy to lose next time: that a deliberate blank row survives an add, and that a delete moves the rows below it up.

## The two-tier grey retires; the default reads as Increase Contrast always did

**2026-08-24.** #111 set one rule and #194 and #240 both nudged inside it without questioning it: the default grey stays dark enough to be unmistakably not-lit, and legible body text is what Increase Contrast is for. #240 said explicitly that the next report of "still unreadable" would be a request to move that rule rather than a fourth nudge inside it. It came the same day, against a reference screenshot of ordinary dark-mode secondary text — not a simulator capture, not another guess at a hex code — and the answer was to retire the rule rather than raise its ceiling again.

`GlowPalette.greyOpaque` is now `greyIncreasedContrast`'s own value, `#8D8D8D` — not a new number. #111 asked, when it first collapsed the four-step ramp, whether a value already in the file meant what was wanted; #194 and #240 both answered that question by inventing a new point on the scale instead. This is the same question asked again, with the file's own accessibility value as the answer: the two tiers — dark by default, legible on request — collapse into one, because the setting's whole existence was arguing that the default should have been this bright from the start.

**What moved, mechanically:**

- `GlowPalette.greyOpaque = greyIncreasedContrast` — a reference, not a duplicated literal, so the two can never drift apart silently.
- The `< 1.5:1` contrast ceiling in `Tests/WidgetBackgroundTests.swift` became an equality assertion (`greyOpaque == greyIncreasedContrast`) plus a `> 4.5:1` floor — the guardrail's shape flipped from "must stay dim" to "must stay legible," which is the honest way to record that the rule itself changed rather than just the number it was checking.
- `RenderTests/RenderBaselineTests.swift`'s `flatTones` literal (`[43, 255]` → `[141, 255]`) and `RenderTests/WidgetRenderDiffTests.swift`'s grey band (`40...46` → `138...144`) both had to move by hand, on purpose — both are written as literals specifically so a palette change cannot silently agree with itself, and both caught real, working assertions that would otherwise have gone on checking for a colour nothing draws any more.
- `isUnlit(_:beside:)` in `WidgetRenderDiffTests.swift` needed its own fix, not just a number: `value * 4 < lit` was calibrated for a grey near 43 against a lit level near 255 — comfortable margin at a 5.9:1 ratio. At 141 the ratio closes to 1.8:1, and `* 4` stopped holding for any real value (`141 * 4 = 564`, never less than a lit pixel). It is `value * 1.5 < lit` now, recomputed for the ratio that actually exists rather than carried over as a constant that quietly assumed the old one. This is the one place in the whole change where a bigger jump (98 levels, against #194's 13 and #240's 7) broke a mechanism outright rather than just moving a number inside it — worth remembering the next time a value this deep in the app moves by more than a nudge.
- The committed render baseline (`RenderTests/Baselines/render-signatures.json`) moved and was approved, per `Tools/validate-test-result.py`'s own printed instruction — every family's picture genuinely looks different now, which is the point.

**Tested at 509/509 after both fixes, not before either.** The first full run caught `flatTonesAreReal` failing on a stale literal test-writing hadn't yet reached; the second caught the render baseline needing re-approval against the corrected run rather than the one still carrying that bug. Both are recorded here rather than smoothed over, because a change this deep in the palette touching four files' worth of literals is exactly the shape of change where "it built" and "it is right" are different claims.

## The pager reaches twelve weeks whether or not the record does

**2026-08-24.** #186 settled that the reach is the record's and nothing else: a week before anything existed holds nothing to correct, so a fresh install could page nowhere. #259 widens that, and the entry above stays as the record of why the narrower rule existed.

**The rule was right about the data and wrong about the control.** A back chevron that is present and does nothing reads as broken — it is the same complaint #242 fixed for a different cause, arrived at from the other direction. "There is nothing back there" is a thing the app can say by showing an empty week, and saying it that way is better than refusing to move.

**It only became honest to say with #265.** Before that, a week earlier than a habit drew a ✕ on every column, so paging into one would have answered "nothing was logged here" with a wall of accusations. #265 makes such a week draw unlit dots, which is what an empty week should look like — so the two changes are one idea and #265 had to land first.

**Twelve weeks is not a new number.** It is the cap #186 removed, turned around: it used to be the furthest the pager could reach and is now the least it always reaches. A quarter was argued then as about as much as a person still holds in mind, and that argument serves a floor as well as it served a ceiling. Reusing it also keeps the count of invented constants in this file where it was.

`WeekReach.from` takes `min(recorded, floor)`, so the record still extends the reach and can never shorten it. A record starting in the future — a clock that went backwards, a sync from a device whose did — cannot pull the pager forward past the floor either, which the same `min` says without a second clause.

**What moved in the tests, and it is most of the reviewable surface.** `noRecordNoReach` and `freshInstallHasNoReach` asserted the old rule directly and now assert the floor. `reachFollowsTheRecord` ran 0...11 and every one of those is now floored, so it is `shortRecordsAreFloored` and says so. `theDemoIsReachableEndToEnd` went from `==` to `>=`, which is the honest form of what it was always about: the demo must be reachable, not exactly reachable. `steppingBackStopsAtTheFloor` and `clampingBothEnds` had records shorter than the floor and now use longer ones, so the floor under test is still the record's own.

The two Havana tests needed restating rather than renumbering. They are #242's property — that `earliest` is a normalized week start, so a comparison against a week start cannot disagree by an hour — and they asserted it by checking `earliest == thisWeek`, which was only true because the record was short. They now assert the property itself: that `earliest` normalizes to itself, sits on a midnight, contains the current week, and does not move when stepped back from. That is what those tests were for, and it no longer depends on where the floor happens to be.

## The app pops too, reversing #103's silence

**2026-08-24.** #103 settled that the app says nothing when a completion is logged inside it. The reasoning was sound and is unchanged: the Island does not render a Live Activity while its own app is in the foreground — measured, `Activity.request` succeeds and `chronod` subscribes a renderer with the right metrics, and the Island stays a plain pill until the app is backgrounded — so firing one from a tap in the app spent two seconds on nothing. #103's answer was to stop firing it and let the app's own acknowledgement stand: the ring closes, the label dims, the row goes quiet.

**In use that reads as the app saying less the moment you are actually looking at it.** The pop is wanted every time, foreground included. So the app draws its own rather than asking the Island for one it will not show.

`InAppPop` is the Live Activity's Lock Screen presentation, not a new design: the same mark, the same glowing line, the same habit name in grey, at the same `WidgetMetrics`. And `GoalPop.registers` — the rule that a routine log says one thing and the tap that meets the goal says two, in that order — moved out of `GoalPopCentre` so both surfaces read it. Two surfaces saying one thing the same way, and unable to drift on *what* is said.

**It is an overlay, not a row in the stack, and that was the second attempt.** The first put the pill in the `VStack` above the grid, which pushed every row down for its two seconds — so the row that had just been tapped moved out from under the finger. Checking several habits off in a flurry is exactly what #272 says has to stay fast, and a layout shift per tap fights it. As an overlay nothing else on the screen moves at all.

The cost is that the pill overlaps the weekday letters for its two seconds. That is the deliberate trade: the covered thing is a static header rather than the marks, and it comes back.

**Not `privacySensitive`, unlike the Island and Lock Screen presentations** (#141). Those are readable by anyone holding the phone; this one is inside the app, already past the lock, and redacting a name shown in full on the row above would be theatre.

One task, cancelled and replaced, for the same reason `PopWindow` guards the Island's: without it the first tap's dismissal fires two seconds after *its* tap and takes the second tap's pill with it.

## The week widget drops its small family

**2026-08-24.** `WidgetKind.week` offered small, medium and large. Small is gone (PR #277).

Small was the only family that dropped the habit labels — `WeekWidgetView.showsLabels` was `family != .systemSmall` and nothing else ever hid them. So it drew the week's marks without saying what any row was: readable only by somebody who already knows their own habit order, and unreadable the moment the order changes. It said how much of the week was done without saying what of.

#237 had already found the other half of the same problem from a different direction: Week-Small has no per-habit axis to vary a second gallery preview over, so the Widgets tab could only ever show one card of it, and that card was the medium's content at a smaller size.

**Removing a family is not removing a kind** (#209). `GlowWidget` still serves `"GlowWidget"`, so a placed medium or large is untouched; a placed *small* stops being served. `WidgetCatalog` already drops a family a kind does not support — `unsupportedFamilyIsIgnored` — so the Widgets tab says nothing about one rather than showing a row it cannot explain.

`showsLabels` is now `true` and stays a computed property rather than being inlined, so the two metrics beside it still read as a pair and restoring a label-less family is one line.

Six tests encoded the three-family week and now encode two: the catalog's shape, the per-family independence pair, the page's order and titles, the querier seam, the per-size card count, and the placement-not-preview rule. The render suite lost its `week small` frame and the committed baseline lost that entry with it; `GlowRenderTests` still reports 13, because the frames are data inside the tests rather than tests of their own, so no floor in `Tools/test-inventory.json` moved.

## Two issue numbers were invented, and both were wrong

**2026-08-24.** Two pieces of work landed today with no issue behind them: the app drawing its own pop, and the week widget dropping its small family. Both were asked for directly rather than filed, and both were written up citing `#273` and `#274` — numbers picked by counting forward from the last one that existed.

**Neither number was free by the time the work merged.** Issues filed while the work was in progress took both: `#273` is "The Widgets tab previews the Default background only, never Tinted or Clear glass" and `#274` is "Two Small widget previews should sit side by side". So every cross-reference in the code, `SPEC.md` and the two entries above pointed at unrelated requests.

**And #274 was closed by it.** The Week-Small pull request said "Closes #274", which GitHub honoured — an open request of Georg's was closed by a change that has nothing to do with it. Reopened, with a note saying why it went.

The references now point at the pull requests that actually did the work, `PR #275` and `PR #277`. That is the honest target: a merged PR is a permanent record of the change, and it cannot collide with a number somebody else is about to use.

**The rule this produces: never cite an issue number that does not exist yet.** If work has no issue, either file one first and use the number it is given, or cite the change itself. Counting forward from the highest number seen is guessing at a value another process is allocating, and it fails silently — the reference reads perfectly and points at the wrong thing.

## The Widgets tab shows two appearances, and Tinted and Clear are one of them

**2026-08-25.** #273 asked for the previews to carry the Tinted/Clear glass
treatment rather than only the Default opaque background, and left two
questions open: whether to match the device's actual appearance, and whether
to draw one card per appearance or three.

**The device's appearance cannot be read.** No trait, environment value or
WidgetKit call reports it — checked against the iOS 26.5 SDK's
`SwiftUICore.swiftinterface` and `WidgetKit.swiftinterface`, not remembered.
`widgetRenderingMode` is the nearest thing and WidgetKit only populates it for
a widget WidgetKit is rendering; inside the app it reads `.fullColor` whatever
the Home Screen is doing. So the first question answers itself: the page
cannot match the device, and the appearance is a choice the person makes.

**One picker for the page, not a card per appearance.** The page already
carries a card per family and, since #237, a card per habit. Multiplying that
by appearance would have doubled the month section. Appearance is a property of
the Home Screen rather than of any one widget, so it is asked once and every
preview answers together.

**Tinted and Clear are one segment, and that was measured.** Both put a widget
into `.accented` rendering, so the *content* of the two is identical by
construction. The panel behind is the system's, composited from a wallpaper the
app cannot see. Rendered with SwiftUI's `Glass.regular` against `Glass.clear`
over the page's stand-in plate, the two came out pixel-identical inside a
preview card — 0.0% of pixels differing by more than 6/255, maximum difference
1. Two segments drawing the same picture would be the page claiming a
distinction it cannot make.

**The honest half and the approximated half are different halves.** The content
is not an approximation: the preview injects `widgetRenderingMode`, and
`GlowPalette.grey` is a `ShapeStyle` that resolves against exactly that value,
so the marks take the alpha-stored grey by the same line of code that runs on a
Home Screen. `GlowWidget.swift` records that the *real* widget cannot
approximate the glass, and that finding stands — it is about a widget the
system composites, which has no say over what replaces its background. This
page draws its own background by hand, as it already draws its own corner and
its own border, so an approximation is available here.

**The plate under the glass has to be opaque, and that was found by looking.**
Rendered translucent, `glassEffect` sampled what was behind it — which on this
page is the page, not a wallpaper — and the caption above each preview appeared
ghosted inside the widget. Screenshotted at 2x through a hosted window, not
reasoned about.

**`ImageRenderer` cannot render this page.** It returns SwiftUI's yellow
unsupported-view placeholder for a hierarchy with `NavigationStack` and
`ScrollView` in it, and returns it *identically* for every input — so three
appearances rendered byte-identical PNGs and briefly looked like proof the
appearance was not reaching the previews. `UIHostingController` in a real
`UIWindow`, snapshotted with `drawHierarchy`, is what renders it, and is what
`EmptyStateAccessibilityTests` already uses for its own reasons.

## Small previews sit two to a line

**2026-08-25.** Every card on the Widgets tab was a line of its own, whatever
its family (#274). Two Small widgets occupy one Medium's footprint on a real
Home Screen, so a column of Smalls was a picture of an arrangement nobody has.

How many fit is derived rather than written down: `WidgetMetrics.perRow`
divides `largeWidth` by the family's own width, so two falls out of 158 fitting
twice into 338 and moves if either number does. The gutter is the same
subtraction. `WidgetCardGroup.rows` does the split, pure and tested.

A trailing odd card is a line of its own at one widget's size, in the place the
next one would go — not stretched, not centred. With #237's up-to-three month
cards that is the case this actually renders, and it was looked at.

Medium and Large fill the width and have no neighbour on a Home Screen either,
so this is a no-op for them.

## A widget's rows are its own, and the app's line narrows (#188)

The week widget mirrored the app's habit order and had no way not to. #172
measured what that costs: the app's own clustering (#123) puts a blank row
where a medium widget's cut falls, so medium shows four habits instead of five,
and the only way to ask for a different five was to reorder the whole app. #172
decided against moving the seed clustering — the app's order is the app's
order — and for letting a widget deviate from it. This is that.

**The decision is `WidgetRows.rows(from:chosen:)`**, in `Glow/Logic/`, and it is
eleven lines. Everything interesting about it is what happens when a choice
outlives the store it was made against: an id that no longer exists is dropped
rather than held as a gap, because a deleted habit is not a blank row; a
repeated id appears once, because the view's `ForEach` is keyed by id and the
rest cut is a range of indices into the same list; and the order is the
configuration's, with the app's list consulted only for what a row *is*. A
widget whose every chosen row has been deleted draws the empty state rather
than silently becoming somebody else's first rows, which is the rule the month
widget already follows for its one deleted habit.

**No `mediumRowCapacity`, no `smallRowCapacity`.** #188 expected to need them
and it does not. The premise was that medium and small "truncate by SwiftUI
running out of frame", so a person-chosen list would need an explicit count to
slice by — but `WeekWidgetView` has always measured `proxy.size` inside its
`GeometryReader` and applied `WidgetMetrics.rowCapacity` to it, then done an
explicit `prefix`. The cut is deliberate code, not clipping. Storing the two
numbers would have been worse than not: a widget's point size differs by phone,
so a constant derived from the 6.1" the design is authored for is right there
and wrong everywhere else, while the measured frame is right everywhere.
`largeRowCapacity` stays, for the one job it has always had — the *app* needs a
number to draw its boundary at, and cannot measure a widget it is not in.

What is asserted instead is the formula's answer per family, which is what the
tests can honestly claim: eleven large, five medium, six small. And that a
configured medium is **a choice among five, not a dial** — five rows need
127.28pt of a 128pt content box, and the 0.72pt left over does not buy a sixth
from anywhere. Both candidate donors are spoken for: `padVertical` already gave
its point to buy the fifth (#57), and `rowGap` is set by how far a halo spills
out of a row, so closing it would put each row's light into its neighbour.

**The app's hairline means something narrower now.** `WeeklyGridView` reads
`largeRowCapacity` twice — for the boundary line and for the rest cut's end —
on the assumption that there is one widget row count the app can know. Per-widget
configuration ends that assumption, and the answer is to narrow the claim rather
than to draw more lines: the hairline marks where an *unconfigured* large widget
stops. Every widget starts unconfigured and most stay that way, and somebody who
has opened the sheet already knows what their widget shows. Several boundaries,
one per placed widget, would be the app explaining the home screen back to
itself in a list that scrolls.

**What the system's sheet actually offers is not what this was built for, and
that is recorded rather than resolved.** #188 named the unknown — whether
WidgetKit presents an array-of-entity parameter as a reorderable list — and said
to say which path this needs before writing the provider. Measured in the
simulator: the sheet is an unordered multi-select checklist in the query's own
suggested order, with no reordering affordance, and the stored choice arrived at
the timeline as an **empty array** on every render while
`WeekRowQuery.entities(for:)` was never called in the extension at all. The
trace is in #191, with what to check on a device and what the fallback costs.
This still ships, and the reason is the fallback rule rather than optimism:
empty and nil both mean the app's own order, so a widget that cannot receive its
configuration draws exactly what it drew before this change. The failure mode is
invisible, which is the property that makes an open question safe to merge past.

## An array-of-entity widget parameter arrives, and it is ordered — and the order is dropped

**2026-08-25.** #191 asked two things about `@Parameter var rows: [WeekRowEntity]?`: whether it reaches the timeline provider at all, and whether it carries an order. A simulator said no to the first and could not answer the second. A phone says yes to both.

iPhone 14 Pro, iOS 26.5.2, three rows selected through the system's own Edit Widget sheet:

```
week query resolve 3 id(s) -> 334920AF-…,1E23A402-…,465AF651-…
week timeline: rows=3
```

**It arrives.** `rows=3`, non-empty, and `WeekRowQuery.entities(for:)` ran inside the extension — which it never once did across four reloads in the simulator. The simulator's empty array was the stale-configuration artifact this file already records for chronod, not a platform limit. That is the second time a per-widget configuration question has been unanswerable in a simulator and settled in one gesture on hardware; `MonthWidgetConfig` records the first.

**And it is ordered by the sequence the rows were tapped.** `entities(for:)` traces the identifiers as asked, and the row tapped first came back first — putting the app's own first habit second in the resolved array. An unordered multi-select would have handed back the suggested order.

**The order is nonetheless dropped, and that is the decision.** `WidgetRows.rows(from:chosen:)` walks the app's list and filters it, rather than walking the choice; `entities(for:)` does the same so the sheet's summary reads the way the widget draws.

The reason is that the control cannot express an order. The picker draws **checkmarks, not positions** — confirmed on hardware as well as in the simulator, no handles, no numbers, no edit mode. So an order carried out of it is gesture history: invisible while it is being made, unexplained afterwards, and unfixable without clearing every row and re-tapping in sequence. A widget that quietly reorders itself according to which checkbox somebody hit first is worse than one that matches the app, and #172's actual complaint — the app's clustering putting a blank row on the medium widget's cut — is answered by *which* rows alone.

**So #188 ships as half of what it asked for, on purpose.** The other half is not blocked by the platform; it is waiting for a surface that can show an order while it is being chosen, which is the in-app screen #188 already names as its fallback. `WidgetRows.rows` takes `[UUID]?` and does not care which surface supplies it.

**The baseline gained one frame and moved nothing.** `week medium configured` is the only committed render with a blank row in it, and it now also pins this decision: the fixture chooses four rows in an order that is not the app's, and the frame draws Workout, blank, Study, Touch Grass — the app's. `month small`, `week large` and `week medium` are bit-identical to `main`'s.

## The burst window is two numbers, not one

**2026-08-25.** `WidgetBurst.duration` was both how long the tap cross-fade
runs and how long the note the intent leaves stays valid. Reload latency came
out of the same 0.3s, so most taps spent most of the animation before the
provider was asked for it (#267).

**The phone settled how bad it is.** iPhone 14 Pro, iOS 26.5.2, on `main` at
`a03fea9`, taps made by hand on a placed week widget: 431ms and 3.17s from the
tap to the week provider running. Both bursts were recorded correctly and
**neither animated**. The simulator's 133–180ms was the best case, not the
typical one.

A second pull the same morning widened the picture. The week provider runs
**45, 112, 138, 241, 325, 347, 378 and 427ms** after the taps it answers
promptly, and **1.2s, 2.2s and 3.2s** after the ones it does not. Across both
pulls, four of fourteen provider runs with a note pending animated anything.

So the two questions are two constants. `duration` stays 0.3s and still means
what #40 decided it means — a handful of stills, not a sampled curve.
`maximumLag` is 0.6s and means *how late a reload may arrive and still be worth
animating*. The frames are dated from the moment the provider ran rather than
from the tap, so latency delays the fade instead of being subtracted from it.

**0.6s is bracketed by measurement from both sides, and the upper bound is the
one worth having.** From below, 427ms: the slowest reload that still arrived
promptly, under which animations the system delivered on time are thrown away.
From above, **798ms**: the tightest gap measured between one reload wave and
the next. Under a flurry the week widget's provider runs again in waves, so a
note still valid when the second wave arrives animates one tap twice — the same
completion cross-fading in again a second later, which reads as a glitch. 0.6s
is the geometric midpoint, 584ms rounded.

That upper bound is the reason this is a decision rather than a widening. The
obvious move — make the note live long enough to catch everything — has a
measured price, and past 798ms the failure mode stops being "the fade was
missed" and becomes "the fade played again". The multi-second delays stay
unanimated on purpose: they are #121's to explain.

**What `WidgetBurstTests.burstExpires` protects is unchanged.** That guard
exists so a midnight rollover or an edit in the app cannot replay somebody's
tap hours later, and two seconds is as unable to do that as 0.3 was. The test
now expires against `maximumLag` rather than against `duration`, and a second
test holds `maximumLag` at or under three seconds so the number cannot drift
until it stops mattering.

**One thing the longer note made necessary.** At 0.3s an undo could not land
inside the window. At 2s it can, and a note that outlives the state it
describes is a widget animating a lie — a ring cross-fading into a dot for a
slot the store has just reopened. `ToggleHabitIntent` clears the note whenever
the toggle is not a completion, scoped to that habit so undoing one does not
swallow the fade another is owed.

**Not decided here:** whether a repeat tap on the same habit inside a short
window should be a no-op rather than a toggle (#272). That is a change to the
only path that writes history and wants its own decision.

## A mark from a widget sets a state; it does not flip one

**2026-08-25.** `ToggleHabitIntent` flipped whatever the store held. It is now
`MarkHabitIntent`, it carries the state the tapped mark was asking for, and
`HabitStore.setCompletion` writes only when the day is not already in it
(#272, #292).

**Two failures, one complaint.** #272 reported "checking off several habits
quickly un-does them", and a device trace found two separate mechanisms that a
toggle turns into the same bug.

*Delivered twice.* On an iPhone 14 Pro a single tap performed the intent twice,
**13ms apart** — far too fast to be two thumbs. Under a toggle the second
performance undid the first, so four taps in one flurry netted no change to the
record at all.

*Stale.* A later flurry on the same phone showed every provider answering in
42–320ms while the person reported the widgets "did not respond quickly at
all" — so the lag is between the timeline being handed back and the pixels
appearing, which nothing in this app controls. During that window the widget
draws an open ring for a day the store already holds as done. A toggle reads
the tap as "flip it" and **removes a completion somebody was trying to make**.
Four of the taps in that flurry came back `undone`.

**The asymmetry is the argument.** The worst a set can do is nothing; the worst
a toggle can do is silently retract a record of something that happened. #272
proposed a narrower fix — treat a repeat tap inside a short window as a no-op —
and it was declined: the window is a guess about human timing, too small to
catch the stale case and too large to allow a genuine correction. Idempotence
needs no window and has no tuning.

**`toggleCompletion` stays, and the app keeps it.** The grid redraws in-process
from the store it just wrote, so it is never the stale caller. A toggle is now
the degenerate case of a set — read the day, ask for its opposite — so the
guards live once and the two paths cannot drift on what a rest day means.

**A fourth outcome.** `ToggleOutcome.unchanged` is the idempotent no-op, and it
is worth naming rather than folding into `.refused`: a caller that animates on
`.completed` now animates once per real change rather than once per delivery,
and the widget trace says `already done` where it used to say `done` a second
time. `WeeklyGridView` handles it beside the refusal and says why it cannot
arrive there.

**Not done here:** the optimistic-rendering half of #292 — a widget control
that draws the state it just requested while `perform()` runs. That is what
would fix the *perceived* latency, and it is a separate change to the view
rather than to the write path.

## Every copy keeps the platform's defaults, and that is the policy (#284)

**2026-08-25.** Glow sets no backup-exclusion and no file-protection
attribute on anything it writes, and after the audit #284 asked for, that is
now the decided policy rather than the unexamined default. The inventory —
every copy, what the OS does with it, and what only a device can measure — is
`docs/data-inventory.md`; `BackupPolicyTests` holds the code to it.

**No recovery promise, and no prevented recovery either.** History is
phone-only: losing the phone loses it, and nothing in the app claims
otherwise. The tempting next step — `isExcludedFromBackup` on the store, so
the claim becomes airtight — was considered and declined, because it converts
"Glow does not promise recovery" into "Glow guarantees loss". The OS backup
carries whatever the person's own backup choice covers, under keys the person
controls: an unencrypted or password-encrypted local backup, iCloud Backup
under standard data protection, or under Advanced Data Protection. None of
that is Glow-managed sync, and Glow neither advertises it nor opts out of it.

**The protection class was never a choice.** The widget reads the store while
the phone is locked; the only class that permits that is
`completeUntilFirstUserAuthentication`, which is what the OS grants when no
`default-data-protection` entitlement is declared — and none is.
"Hardening" the store past it would present as a privacy improvement and
ship as a widget that goes blank at the lock screen. The test asserts the
entitlement's absence for exactly that reason.

**What the audit found**, at current `main`: nine copies, one of them outside
the backup set — the temporary export, excluded by living in `tmp/` rather
than by any attribute, which is the right shape for a plaintext file whose
lifetime is one share sheet. The quarantine copies — potentially the sole
survivors of some history — sit inside the backup set, which is exactly where
a copy kept *because deleting it was refused* belongs. Nothing needed
changing.

**What is honestly unmeasured.** The simulator does not implement per-file
Data Protection, so no CI test can read the class a phone would enforce, and
no backup→wipe→restore protocol has been run. The tests assert what is real —
the absence of the attribute APIs in source, the absence of the entitlement,
and a meaningful resource-value read on an export — and the inventory names
the device-only gaps instead of faking them.

**Not decided here:** whether the export grows into a restorable backup.
That is #285, and it has its own entry.

## The export is a history export, and a backup is declined (#285)

**2026-08-25.** #285 laid out what a restorable backup would take — a
versioned `.glowbackup` envelope, an import with validation, preview and
crash-safe replace — and the decision is to not build it. The CSV and JSON
stay what they are: human-readable projections of the history, made to be
read in a spreadsheet or parsed, and lossy by construction. CSV has no row
for a habit never logged; JSON drops IDs, order, spacers, provenance and
settings. Neither can reconstruct the app, and neither claims to.

**The premise the issue names is accepted, and answered the other way.** A
person can export, lose the phone, and find the file does not restore what
they had — which is why the file must never be *called* a backup. History is
phone-only; there is no recovery promise; losing the phone loses it. The OS
backup remains whatever the person's own choice covers (see the #284 entry
above), and Glow neither brands that as recovery nor removes it.

**What the sweep found.** App UI copy, SPEC.md, the docs and the sources were
searched for "backup", "back up", "restore", "recover" and every
lose-your-phone phrasing. The product copy was already clean — the feature is
"Export History", the Settings footer says "Every habit and every day you
logged it, as a file", and SPEC §"There is one" describes a file handed to a
share sheet, nothing more. The single offender in the repository was a test
comment in `HistoryExportTests` that said "a diff of two backups"; it now
says exports, and says why.

**Declined, not deferred by accident:** the `.glowbackup` format, the import
path, and any merge semantics. If phone-loss recovery ever becomes part of
the product it is #285's design — a separate format with its own version,
limits and crash-safe replace — and reopening this entry is that decision,
not a rediscovery.

## A release is bound to a reviewed commit, and the workflows are the contract they read as

**2026-08-26.** #287 named three provenance gaps and this closes the two that
need no repository admin: the workflow files' own trustworthiness, and the
source a TestFlight build ships from. The third — branch protection on `main`,
an Actions policy requiring SHA pins — is a GitHub settings change and is
written up as a checklist on the issue rather than half-done from a token that
cannot do it.

**Every `uses:` is now a full commit SHA, resolved and verified against the
actions repositories, with the release it came from named beside it:**
`actions/checkout@3d3c42e…` is v7.0.1, `actions/cache@0057852…` is v4.3.0,
`actions/upload-artifact@ea165f8…` is v4.6.2 — each tag's SHA read via the
GitHub API and each SHA confirmed to be a real commit before it went in the
file. A tag is a pointer its owner can move without a commit here, which for a
repository that pins its own *project generator* by archive digest was the one
mutable execution reference left. `permissions: contents: read` is declared at
the workflow level for the same reason: the read-only default is a repository
setting, and a setting is not a diff.

**The policy has its own checker because a gate nobody checks weakens
silently.** `Tools/check-workflows.py` parses the tracked workflows
line-by-line — stdlib only, no YAML dependency on the gate runner — and fails
on a tag or branch ref, an abbreviated SHA, a missing or non-version pin
comment, a missing `permissions:` block, a wholesale `read-all`, or any
permission outside its allowlist. Thirteen mutation fixtures prove each rule
fires, in the style of the two validators beside it, and the gate job runs the
self-test before the check on every push. Widening the permissions allowlist
is deliberately a change to this checker, in the same diff as the job that
demonstrates the need.

**`Tools/ship-testflight.sh` now asks "which reviewed commit is this?" before
it asks anything else.** The existing validators answer whether a bundle is
internally consistent and correctly signed; a cleanly signed build of a dirty,
stale or unreviewed tree passes both. The preflight runs before credentials
are read and requires: a clean tree (`git status --porcelain` empty — tracked
and untracked non-ignored files alike), `HEAD` exactly equal to freshly
fetched `origin/main` or to an annotated tag the remote holds at the same
object, and a CI verdict for that SHA in which every check run completed
without failing and at least one succeeded — phrased over all check runs
rather than by job name, so a new lane tightens the gate instead of dodging
it. What it establishes goes into `private/provenance/<time>-<sha>.json`:
source SHA, ref, CI verdict, Xcode build, marketing version, build number,
whether the suite ran, and — written back after `altool` returns — that the
upload happened. `private/` because the trail should survive `rm -rf build`
and never become a commit.

**The overrides are the decision.** A dirty tree has none, a wrong ref has
none: a release that cannot be reproduced from a commit is not a flag away, it
is a different product promise. The CI verdict has exactly one, the named
`--allow-unverified-ci`, for the machine that genuinely cannot consult GitHub
— it prints what it is skipping and the provenance record says `overridden`
with the reason the verdict was unavailable. There is no `--force`, on
purpose. `--skip-tests` keeps meaning what it meant — the local suite — and
has no effect on any preflight check. `--preflight-only` runs the whole
question and stops before anything costs a minute or reads a credential.

**Measured, not assumed:** the dirty-tree and wrong-ref rejections were each
watched firing; on a fresh clone of `origin/main` the preflight correctly
refused a merge whose `Build and test` run was still pending — the honest
answer minutes after a merge — and passed with `--allow-unverified-ci`
recording exactly that. The pending case is the reason the failure message
names `gh run list --commit <sha>`: "wait" is the usual fix.

**Not decided here:** whether one human approval is required on `main` —
that is repository governance, listed on #287 for Georg with the exact ruleset
settings, since required CI and blocked force-pushes should not wait on it.

## Local-only stops being a lucky alignment and becomes an invariant

**2026-08-26.** #281's audit found no network client, no third-party
dependency, no CloudKit entitlement and no direct network linkage — a verified
strength resting on nothing. The app was local-only because several
independent facts happened to agree, and not one of them would have failed a
build when it stopped being true. This change makes each of them a gate.

**The store API said `.automatic` by omission, and now says `.none` by hand.**
`ModelConfiguration`'s `cloudKitDatabase:` parameter defaults to `.automatic`
— managed CloudKit, if an entitlement lets SwiftData find a container. All
three production call sites (the writable store, the widget's read-only store,
the migration inventory) now pass `.none` explicitly, and the migration helper
mattered as much as the stores: a helper opening historical files must not be
the one call site that inherits the default. `TestSupport`'s file-backed
stores say it too, so a test store is configured the way the store it stands
in for is. `LocalOnlyContractTests.storesSayNone` walks every production
source, balances the parentheses of every `ModelConfiguration(` call, and
fails the one that stops saying it — with a floor of three call sites so the
scan cannot rot into vacuous passing.

**The entitlement is held closed from both ends, because the two ends have
already been seen to disagree.** The six iCloud/ubiquity keys are rejected by
name — plus anything outside an allowlist — in what the generated project
*requests* (`Tools/check-project.py`, which gained `--self-test`, 11 fixtures,
run on the Linux gate) and in what the signature actually *grants*
(`Tools/check-release-build.py --require-signing`, 8 new fixtures, 24 total).
The release checker's allowlist admits what distribution signing injects
(`application-identifier`, team id, `get-task-allow`, `beta-reports-active`,
`keychain-access-groups`) and a fixture holds that a realistic distribution
signature keeps passing — the gate that fails every real `.ipa` on the
machine that ships is a gate that gets deleted, not obeyed. The two checkers
carry the denylist as two copies on purpose: each runs alone on machines the
other never sees, and each proves its own copy fires.

**The source scan starts with #281's exact spellings** — `import CloudKit`,
`CKContainer`, `URLSession`, `import Network`, `WKWebView` and the rest — over
`Glow/` and `GlowWidget/`, comment lines excluded, `Tests/` exempt by
construction. A match is a *reviewed rejection*: the allowlist is an array of
(file, spelling, reason) in the test, empty today, and widening it is the
reviewable event. This is the `TestIsolationTests` pattern — the property is
the absence of a call, and no runtime assertion can observe an absence.

**What this deliberately does not claim.** The privacy-manifest tests' comment
used to say the assertion stopped a future dependency changing the product
statement; it could not — it reads what the manifests *declare*, and code can
change without touching a manifest. The comment now says which gate does
which. None of this proves Apple's frameworks never communicate internally;
it proves that changing *Glow's* surface — a call site, an entitlement, an
API name — fails a review gate instead of passing silently.

**Not done, on purpose:** the CloudKit-shaped schema comments in
`Habit.swift` and `Completion.swift` stand. #281 explicitly does not authorize
a schema rewrite — removing optionality or adding uniqueness constraints is a
versioned-migration decision, not a lint fix. The dependency-manifest and
Mach-O linkage scans from the issue's fuller programme are also not here; the
zero-third-party baseline currently has nothing to scan, and a `Package.swift`
arriving would be its own loud review.

## The declared minimum iOS gets a lane, and the suite says where it ran

**2026-08-26.** #286 found the contradiction plainly: `project.yml` declares
iOS 18.0, `Tools/test.sh` deliberately picks the newest installed runtime, and
the audited green run executed on iOS 26.5 — so the support promise was
compiled against, never run against. The decision, made rather than
relitigated here: **keep the 18.0 deployment target and gate it**, accepting
the CI-time cost of a second macOS lane. Raising the target is the fallback
if the lane cannot be kept green, and it is a product decision with a user
cost, not a CI convenience.

**`Tools/test.sh` keeps its default and gains a contract.** "Newest installed"
stays right for a developer machine — portability was the point (#221 queues,
#245 accessibility, all of it unchanged). What was missing is the way to say
"this run must be iOS 18": `GLOW_EXPECTED_RUNTIME_MAJOR` restricts the
selection to that major and then *asserts* the chosen device matches,
including a device pinned by `GLOW_SIMULATOR_UDID` — filtered at selection and
checked after it, because the failure #286 names is precisely a lane that
quietly runs on the wrong runtime and reports green. Both rejection paths
were watched firing on a machine with only iOS 26.5 installed: no matching
device (names the installed runtimes), and a pinned device on the wrong
runtime (names the device and both versions). Where a run happened is now
evidence, not inference: runtime and device go to the console, to
`<run>/simulator.txt` beside the log — so a crashed run still says which
phone it died on — and onto the end of `summary.md`, which CI publishes.

**The minimum lane installs its own runtime.** The `macos-26` image ships no
iOS 18 simulator; the lane downloads the newest iOS 18.x runtime with
`xcodebuild -downloadPlatform iOS -buildVersion` to an export path, caches the
dmg (`actions/cache`, keyed by the pinned version — the same argument as the
XcodeGen cache), installs it with `simctl runtime add`, and creates an iPhone
SE (3rd generation) on it — the smallest phone the minimum supports, created
explicitly because the whole lane is about not inheriting what the image
happens to have. The suite then runs with `GLOW_EXPECTED_RUNTIME_MAJOR=18`
and its own erase, artifact and verdict, as a separate job so a
compatibility failure reads as one.

**The lane's first full run settled two things by measurement.** First,
`xcodebuild -downloadPlatform iOS -exportPath` *installs* the runtime as well
as exporting the dmg — an unconditional `simctl runtime add` on the file it
had just written failed with `SimDiskImageErrorDomain` code 6 and left an
Unusable duplicate image, so the add now runs only when no usable iOS 18
runtime is present, which is the cache-hit path. Second, and the real
finding: **all 551 unit tests pass on iOS 18.5 unchanged** — logic, store,
migration, accessibility, the lot — and what fails is exactly the render
baseline, because a baseline is a picture of one renderer's output and the
renderer is the OS's. The same commit that moves no cell between two
simulator *models* moves cells past the tolerance and the ground share by up
to 7.4 points between iOS 26.5 and iOS 18.5 (`week medium configured`: 84.0%
pure black against 76.6%). So the baseline is per OS major where a major is
gated: `render-signatures-ios18.json` sits beside the unsuffixed current
file, `committedBaseline()` picks by `operatingSystemVersion`, and the iOS 18
file's contents are the lane's own attached `render-signatures-actual.json` —
approved from the artifact of the run that measured it, which is the same
approval flow the current runtime has always used. `Tools/test.sh`'s approval
hint names the per-major destination when one exists.

**Not done here, and said on the issue:** the UI/integration smoke target
#286 proposes (launch, historical store, widget configuration metadata,
smallest-device accessibility envelope) is real and separate work; the lane
runs the full existing suite, which is what exists to run. A device fact
worth recording beside the lane: an iPhone 12 Pro Max on iOS 18.6.2 ran a
Debug build of `main` on 2026-08-25 — extension registered, widgets placed,
intents performed, store loaded in 4–10ms. That is a run-there proof, not a
correctness proof; the lane is what gates the claim from now on.

## The widget's mark is a Toggle, and it draws the state it asked for

**2026-08-26.** The tappable marks in both widgets were `Button(intent:)`, and
a button's pixels are the entry's: however fast `MarkHabitIntent` wrote, the
mark held its old shape until WidgetKit scheduled the provider and composited
the result — 431ms and 3.17s measured on a phone (#121), which is the gap
people filled by tapping again (#272). They are now `Toggle(isOn:intent:)`
behind one control, `SlotToggle`, whose style renders `configuration.isOn`:
the one mechanism WidgetKit offers for pixels that change at the tap. This is
the second half of #292; #295's idempotent set was the first.

**Believed, on Apple's word:** an AppIntent-backed widget `Toggle` updates its
appearance optimistically while `perform()` runs, *provided* the style draws
`configuration.isOn` rather than anything captured from the snapshot. That
proviso is the entire design of `SlotMarkToggleStyle` — both faces are built
from the entry, but which one shows is the system's bit, so the system can
flip it before the intent has run.

**Measured, in a simulator (iPhone 17 Pro, iOS 26.5):** all three call sites —
week slot, week span, month cell — perform through the placed widget, and the
ordering is visible in `WidgetTrace`. On an undo tap, a screenshot taken
immediately afterwards showed the mark already mid-flip while the entry-driven
label still said done; the tap line landed in the trace after that frame, and
the provider ran 4.2s after the tap. Changed pixels before the provider ran
can only be the toggle. What a simulator cannot say is how it *feels* on a
phone — whether the flip lands inside the finger's dwell — and nobody has
looked yet.

**Decided along the way:**

- **The faces are per call site, the control is not.** A slot's completed face
  carries the burst cross-fade; a span's faces carry its width and rest
  window; the month's are plain marks. `SlotToggle` owns the toggle, the
  style, and the spoken strings; the call sites own what a face looks like,
  which is exactly the split `SlotMarkView` already draws along.
- **A span's optimistic frame is its own two states at its own geometry.** Tap
  an open span and the ask goes quiet — `.openToday` to the same unlit
  structure a filled span draws (#47). The lit dot on today and the
  re-division of the row are the store's answers, and they arrive with the
  reload; the toggle owns its own pixels and nothing beside them.
- **VoiceOver follows `isOn`.** Label and hint are computed inside the style
  from the same bit the pixels are drawn from, so the announcement agrees with
  the optimistic state; the system adds the toggle's on/off value from that
  bit too. Reduce Motion is untouched: the flip is a state change, not
  motion, so acknowledgement survives it, and the burst stays the thing
  Reduce Motion skips.
- **Which marks are interactive did not move.** Tappability is still
  `Slot.isTappable`, `SlotSpan.isTappable` and `MonthCell.isTappable`; a mark
  that takes no tap is a plain `SlotMarkView` with no control trait, exactly
  as before. `WidgetPlacementTests` now scans `GlowWidget/` for
  `Button(intent` so the migration cannot quietly regress one call site.

**Not decided here:** the burst's first frame draws the ring at full opacity,
which is now the second time the dot has been on screen — optimistic dot,
ring, cross-fade back to dot. Whether the cross-fade still earns its place
when the acknowledgement it was standing in for happens at the tap is #267's
question and stays open; nothing about `WidgetBurst`, its window, or the
intent's write path moved with this change.

## Emailing the history is the composer presented, and nothing more (#289)

**2026-08-25.** Settings gains **Email My History** beside Export History:
the same CSV/JSON chooser, the same file written by `HistoryExport` into
`ExportStore` at the moment of the tap, handed to Apple's
`MFMailComposeViewController` instead of the share sheet. The decision #289
asked for — a dedicated "send it to myself" path without an account, a
backend, or an inferred address — ships exactly at that boundary: Glow
prepares the message and stops.

**The privacy line is drawn in constants, not conventions.** The recipient
list is `MailExport.recipients`, an empty array set explicitly on the
controller, so "no address is discovered, inferred or prefilled" is a line of
code a test pins rather than an absence a reviewer has to notice. The subject
is neutral and dated — "Glow Up history — 2026-08-25", spelled through
`DayID` so subject and filename name the same civil day — and the body is two
sentences: what the attachment is, and that pressing Send moves it through
the person's own provider, whose copies are its own. Nothing the flow says
suggests safekeeping, and `MailExportTests` holds the #285 sweep over the one
new user-facing string: this is an export, not a backup, and no recovery
promise attaches to it.

**Both routes exist on every device, so both are code, not circumstance.**
`canSendMail()` is read at one call site and routed through
`MailExport.route(canSendMail:)`; a device Mail cannot send from gets a brief
explanation and the existing share sheet with the same file — the honest
fallback, not an error. Without the seam, one of the two arms would exist
only on phones with a configured Mail account, which no CI simulator is.

**Four ways out, one lifetime rule.** Sent, saved, cancelled and failed all
release Glow's temporary file — a sent message or a saved draft is Mail's
copy — and the release rides on the sheet's single dismissal, the same event
the share sheet already uses, so a composer swiped away without the delegate
ever firing releases the file too. Only `.failed` shows an error;
cancellation is a decision, and dressing it as a failure would teach people
that backing out breaks something. MessageUI's error object is deliberately
neither surfaced nor logged — it can carry account details, and the reaction
to failure is the same whatever the reason. An `@unknown` future result maps
to `.failed`, erring toward saying something went wrong over silence.

**One serializer, one temp-file owner.** The email path calls the same
`writeExport` the share path does; a second serializer or a second cleanup
would be a second thing to drift, and #142's sweep already covers the app
being killed while either sheet is up. The mail row is a plain `Label` like
its neighbour — the root tint is pure white and has eaten three styled
prominent controls already.

**Not decided here:** attaching both formats to one message (#289 named it
and it stays declined — the chooser stands unless research shows both are
wanted), and any `mailto:` path, which cannot carry an attachment and was
ruled out in the issue. What only hardware can answer — the composer
presenting over Settings on a phone with a real Mail account — is noted in
the PR rather than claimed.

## The agent documentation gets an authority order, and a gate to hold it

**2026-08-25.** #288 audited the instruction graph and found high-salience
statements contradicting the shipped app: `CLAUDE.md` opened with "a one-screen
iPhone habit tracker" and told agents the code is the backlog wherever
`docs/vision.md` disagrees; `SPEC.md` said `firstWeekday` is forced to Monday;
`docs/ARCHITECTURE.md` listed the tabs in the wrong order, gave the week widget
three families, and said the app is one screen and three sheets; store comments
called the widget a second writer *process*; and both `CLAUDE.md` and the PR
template carried literal test counts as the expected form — every numeric
example ever written into either had gone stale.

**What was believed.** That each document could be written as equally
authoritative and kept current by the "update the docs in the same session"
rule. The audit showed the failure mode: the same fact lives in six places,
five get updated, and the sixth still reads as an instruction — the Widgets tab
was nearly filed for removal on exactly that reading (#235).

**What was verified.** Every contradiction the audit named was re-checked
against current `main` rather than the audit's baseline `a03fea9`, eight merges
stale by tonight. Two had already been fixed on the way here — `SPEC.md` §9
documents Week-Small's removal (PR #277) and carries `MarkHabitIntent`'s
set-not-toggle rule (#272, #292) — and the rest still stood. The process claim
was verified against the type itself: `MarkHabitIntent` is a
`LiveActivityIntent` and runs in the app's process (#58), on a per-tap
container of its own, so the second *writer* is a context, not a process; the
widget extension renders in its own process but writes nothing.

**What was decided.** `CLAUDE.md` now opens with an explicit authority order —
founder invariants, then current code with SPEC/ARCHITECTURE, then the dated
vision, then this file (latest superseding entry wins), then closed issues,
then open issues and PRs as unverified backlog. The confirmed contradictions
are corrected in place, the numeric `L1 n/n` examples are gone everywhere in
favour of pasting the script's own output, and `Tools/check-docs.py` — with a
`--self-test` that mutates fixtures the way the other two gates do — fails CI's
Linux gate job when a known contradiction is reintroduced into a normative
document. This file is structurally exempt from that gate: a history is allowed
to say what used to be true, which is also why the per-habit-accent entry above
gained a visible superseded marker rather than an edit.

**What was deliberately not decided.** No incident material moved out of
`CLAUDE.md` into runbooks — each retained entry is the rationale an agent needs
to apply the rule beside it, and relocation is its own change with its own
anchor breakage. `docs/vision.md` keeps its own "this document is the target"
framing, because #235 already litigated how that sentence handles exceptions;
what changed is that `CLAUDE.md` no longer repeats it without the caveat. And
the gate stays narrow on purpose: four reintroductions it can name exactly, no
broad word blacklist, so honest historical discussion stays writable.

## A failed read is not an empty store, and a failed tap is not a silent one (#282)

**2026-08-25.** Several read paths encoded three different facts — the
container did not open, the fetch failed, the store holds nothing — as one
empty value, and the widgets drew all three as "No habits yet". On the write
side every mutation threw correctly, rolled back correctly, and then told
only the OS log. Both were the same missing thing: state modeling at the
persistence/UI boundary. #282 confirmed the mapping statically; nothing here
required inducing a store fault.

**Reads now travel typed.** `StoreRead` (Glow/Logic) is `loaded`, `empty`,
`unavailable`, produced at the store boundary — `WeekWidgetStore.rows`,
`MonthStore.month` — and carried into `WeekEntry`/`MonthEntry`, so no view
can collapse the three again. The widgets draw `unavailable` as a distinct
"Data unavailable — Open Glow" surface (`WidgetUnavailableView`, the same
glyph as `StoreUnavailableView` because the deep link lands there), and the
configuration pickers throw on a failed read — the system sheet shows its own
retry — rather than offering an empty list. The boundary functions take an
injectable `container:` so tests hand them the failure the simulator cannot
produce on demand; `nil` is exactly what `makeReadOnlyContainer()` returns
when the real open fails.

**Why empty is a case and not a derived condition:** the view switching on
the enum has to handle it *somewhere*, and a `.loaded([])` that renders the
empty state is one `if` away from a `.unavailable` that does too. Three cases
make the false-empty bug unrepresentable at the view.

**The export is all or nothing.** `Habit.fetchedSnapshots` keeps the fetch
failure the non-throwing helpers flatten (they stay, for grids mid-render,
where a frame missing marks beats no frame), and `ExportStore.writeHistory`
orders the steps — read everything, render everything, only then let a file
exist — so a throw anywhere means no file, no share sheet, and a visible
error with a safe retry. The previous export, possibly still under a share
sheet, is untouched by a later failure: the sweep lives inside `write`, which
a failed read never reaches.

**Failed mutations are told to the person.** `OperationNotices` is the one
mechanism: a fixed catalogue of sentences (never the error's text, a name, a
UUID or a path — the log keeps the diagnostics, as before), presented as an
alert by `operationNoticeAlert()` on `RootTabView` and on the editor sheet,
because an alert attached under an active sheet cannot present. Retry travels
with the notice only where the operation is safe to repeat, and the type
drops it for destructive operations — `delete` and `reset` go back through
their own confirmed gestures or not at all. That asymmetry is the same one
that settled #272: the worst a declined retry costs is a repeated gesture;
the worst an automatic destructive retry could do is destroy something under
a confirmation that has expired.

**Not done here:** feedback for a failed `MarkHabitIntent` in the widget
process — WidgetKit offers no alert surface, so the trace and the refused
write remain the whole story there; and any redesign of the app's own
history surfaces, whose `@Query` reads do not surface failures to catch. Both
are #282's remainder if they are wanted at all.

## The schema is versioned from today, and history is not invented (#283)

**2026-08-25.** Production opened a plain `Schema([Habit.self,
Completion.self])` and left compatibility to lightweight inference. It now
opens through `GlowSchemaV1` — an immutable snapshot of the shape shipping
today — and `GlowMigrationPlan`, via the one open both processes share,
`GlowStore.container(at:readOnly:)`. Behaviour is identical by construction:
V1 lists the same two model types, the plan has one version and no stages,
and `SchemaContractTests.plannedOpenReadsAPrePlanStore` proves a store
written the old way reads back unchanged through the new open, writable and
read-only both.

**The upgrade floor is TestFlight builds, and the issue's offer of
reconstructed history is declined.** #283 suggested rebuilding materially
different shipped shapes from tagged commits and checking in historical store
fixtures. No public release exists; every store in the world was written by a
TestFlight build whose stored shape is exactly what V1 froze — the earlier
stored-shape changes were additive-with-default, so those builds' stores
*are* V1-shaped, with the row backfills owning the contents. Versions
invented for shapes no surviving store can hold would be history nobody can
test honestly, so the floor is documented instead: pre-floor stores are
unsupported, fail to open, and land on `StoreUnavailableView` in the app and
on the widget's *unavailable* state (#282) — refused, not improvised over,
and never overwritten.

**What the gate is.** `SchemaContractTests` freezes the metadata as literals
— entity names, every attribute with its value type, both relationships with
their delete rules, the version 1.0.0, the plan's contents. A model edit that
changes stored metadata fails the suite, and the fix is a decision: a
`GlowSchemaV2` plus a `MigrationStage` in the same change, or an explicit
finding that the store is unchanged. The literals are the point — an
expectation derived from the model would move with every edit and gate
nothing.

**The order of the three migration layers is now written down** (in
`GlowMigrationPlan`'s comment): file location first (`StoreMigration.run`,
whole DB/WAL/SHM sets, schema-blind), shape second (this plan, at container
open), row contents last (`stampDayIdentities`, `DailyHabitMigration`, each
defined by what is still undone). None marks another complete.

**Not decided here:** what V2 is. The dead columns (`timesPerDay`,
`accentRaw`) and the CloudKit-shaped optionality stay exactly as they are —
dropping them is the first real stage's decision, taken when there is a
reason, against a floor that now exists to upgrade from.
