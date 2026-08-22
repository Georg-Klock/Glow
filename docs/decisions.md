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
  container is ever unavailable.

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
