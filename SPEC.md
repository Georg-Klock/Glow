# Glow Up Habit Tracker, product spec (v1)

Product truth. Where this and the code disagree, one of them is a bug; say
which in the same session you find it.

## 1. Concept

A habit tracker whose weekly overview is the whole app: a grid of habits by
day, filled when done.

Today's column physically glows on HDR-capable screens: it is drawn from an
image encoded in a colour space with real headroom above SDR white, which is
what makes HDR photos look brighter than white in Photos.

**Light means something happened.** Every completion glows, whatever day of the
week it fell on, and so does today's open slot. What does not glow is anything
merely absent: a missed day and a day still to come are both flat. So a good
week is a row of lights and a bad one is nearly dark, which is the whole product
in one sentence.

**A span is structure, not a mark, and structure is never lit.** A habit due N
times a week is drawn as N shapes dividing the week; those shapes say how the
week was *divided*, which is not something that happened. They are unlit
whether their share has been achieved or not, and the lit dots sitting on them
say which days it happened on. Without this the sentence above has an exception
in it — an achieved span was lit while saying nothing about when — and one
sentence with an exception is two sentences.

## 2. Goals

- One weekly-grid screen is enough to see every habit's status for the current
  week. No drilling into detail screens for the core loop.
- Logging a habit is one tap from the weekly grid.
- The glow renders on EDR-capable devices and degrades to plain colour where it
  cannot, with no broken state either way.
- Two kinds of habit, never mixed: counted across a week (daily, or
  N-times-per-week with no day pinning), or counted within a day (N times
  today, resetting with the day). See docs/vision.md.

## 3. Non-goals (v1)

- **No sync.** Local SwiftData only. Sync stays a clean follow-up as long as
  the model is normalized now, which is why it is.
- **No fixed-weekday schedules.** "Every Mon/Wed/Fri" is out of scope.
  Frequency habits are pure count-based; any day counts.
- ~~**No multiple completions per day.** A habit is done or not done for a
  day.~~ **A per-day habit holds several.** The vision added a second kind of
  habit — done several times within one day — and each repetition is its own
  `Completion` row. For weekly-cadence habits the old sentence still holds,
  enforced by `toggleCompletion`.
- **No notifications or reminders.**
- ~~**No export.**~~ **There is one.** Settings → Data → Export History writes
  a CSV or a JSON file and hands it to the share sheet. No account, no
  destination the app chooses, and **nothing leaves the device unless a person
  sends it** — the file is written at the moment of the tap, into the app's own
  temporary directory, and never otherwise. That is a privacy claim true by
  construction rather than by policy. `HistoryExport` is pure and its bytes are
  asserted.
- ~~**The home screen widget does not glow.**~~ **It does.** This was written as
  a non-goal on the reasoning that WidgetKit renders in a separate process and
  archives the result, so HDR could not survive. That was never measured, and it
  is wrong: running the real Rec. 2100 PQ tile in the widget glows on an
  iPhone 14 Pro. The widget now uses the same renderer as the app.
- **No streaks, badges, or celebratory flourishes** beyond the completion
  transition itself. These were explored as candidate glow moments and cut, to
  keep the interaction model at one rule rather than three.

  **One exception, and it is bounded** (#58). Something logged from the home
  screen makes the Dynamic Island say so for two seconds. The non-goal above is
  about the surfaces that *record state*: the grid, the rings, the widgets, all
  of which say one thing in one register. The pop is outside all of them, it is
  transient, and nothing it says persists. No streak is counted, no badge is
  kept, and the grid is identical whether it fired or not.

  **How often it speaks is the person's choice** (#119), and Settings has three
  positions rather than a switch: **Never**, **Goals**, **Everything**. Goals is
  the default and is what "on" always meant, so a stored setting keeps exactly
  what it had. This clause used to read "when a goal is met", and the reasoning
  for that restriction — that firing on every completion would put twenty of
  these a day on a screen whose whole argument is that it says one thing — is
  kept in `GoalMet`'s own comment, marked superseded. What it got wrong is the
  screen: a pop is not on that one.

  **Two vocabularies, so the rare thing still reads as rarer.** A repetition
  gets a flat acknowledgement — "logged", "counted" — and a goal met gets the
  celebratory one. The tap that meets the goal says both, sequentially inside
  the same two seconds, because a compact Island state has room for one short
  phrase and not two.

  **A correction says nothing.** Un-logging a day, and the tap that resets a
  full ring to zero, both fire no pop. An acknowledgement for taking something
  back is the app congratulating somebody for an undo.

  **One pop at a time, whose words change** (#102). Two goals met inside the
  two seconds is not an edge case — the medium Today widget puts three rings
  side by side so they can be tapped in a flurry. A second goal updates the
  running activity rather than requesting another; the ending belongs to the
  most recent one, so nothing is cut short.

  **It fires from the home screen only** (#103). The Island does not render a
  Live Activity while its own app is in the foreground, so a goal met inside
  the app would spend its two seconds on nobody. `GoalPopCentre` is called from
  `TapHabitIntent` and `ToggleHabitIntent` and from nowhere else; the app's
  acknowledgement is the one it already had, which is the ring closing and the
  row going quiet.

  The alternative was to rewrite §1 so that light may also mean *well done*.
  That was declined: it would put a second meaning on the one signal the app
  has. See docs/decisions.md.

## 4. Data model

```swift
enum Frequency { case daily, timesPerWeek(Int), timesPerDay(Int) }
// timesPerWeek: 1...6 selectable, 7 collapses to .daily
// timesPerDay: 1...12, one ring arc per repetition

struct Habit    { id, name, icon, frequency, accent, createdAt, sortOrder }
struct Completion { id, habitId, dayKey, day }     // dayKey is the identity
```

**A completion belongs to a civil day.** `dayKey` is that day as `yyyy-MM-dd`,
and it is what grouping, uniqueness and lookup all use. `DayID` is the value
type; nothing in it is an instant, so nothing in it moves when the device's zone
does.

`day` is the local midnight the row was normalized to when it was written. It is
kept and never rewritten — it is the only evidence of where a pre-`dayKey` row
came from, and the backfill that gave those rows a key had to infer one from
exactly it. Storing only that instant was #130: local midnight is a different
moment in every zone, so 19 August compared unequal to itself after a flight,
left the grid, and let the next tap write a second row for a day that already
had one.

**Week boundary.** Weeks start Monday, matching the M T W T F S S header. All
"this week" queries filter into `[startOfWeek(Monday), +7 days)` using the
user's calendar, with `firstWeekday` forced to Monday. Locale would otherwise
decide, and in the US that means Sunday, silently shifting every column.

## 5. Invariants

A build that violates one of these is broken regardless of what else works.

- **R1.** At most one slot per habit is open at a time, and only ever for the
  current day.
- **R2.** A slot responds to taps only where its surface allows it. The week
  view edits any day of the week it shows; the widget, its intents and the month
  grid edit today and nothing else. A rest day is never editable on any surface.
  The days *ahead* are editable only with demo history in — outside it you can
  correct the past, not claim the future. **The week it shows need not be this
  one** (#117): the view pages back as far as the record reaches, capped at
  twelve weeks, and a week entirely in the past is editable end to end. Forward
  stops at the current week.
- **R3.** For a weekly-cadence habit, a day holds zero or one completion.
  Never two. A per-day habit stores one completion row per repetition, so a
  day holds up to its target.
- **R4.** A completion names one civil day and keeps naming it. Changing time
  zone, crossing a DST transition or relaunching does not move it, and a
  completion the app can see is a completion the app can un-log.
- **R5.** A daily row draws exactly 7 slots; an N-times row draws exactly N
  spans — plus one lit dot per completion, on the weekday it happened.
- **R6.** Every row spans the same track width, whatever its slot count.
- **R7.** Weeks reset clean. A frequency habit's unmet goal does not carry over.
- **R8.** The glow is encoded in a colour space with headroom above SDR white.
  Without EDR the app renders flat colour, never a broken or blank slot.

R1, R2, R5 and R7 are asserted in `Tests/WeekGridTests.swift`, including an
exhaustive pass over all 128 possible completion histories of a week — run under
each surface's rule, so R2 is asserted as the difference between them rather
than as one answer, and run again over an earlier week, which is the branch with
no today in it. `Tests/SlotEditingTests.swift` covers the rule itself and the
geometry that resolves a touch on a span into a weekday.
`Tests/WeekReachTests.swift` covers how far back the pager goes. R3 is asserted
in `Tests/PersistenceTests.swift`, which also asserts the store's own refusal of
a day still to come, and R4 in `Tests/DayIdentityTests.swift` — Los Angeles to
Berlin and back, both DST directions, and a zone whose clocks move at midnight.
R6 is in `Tests/SlotLayoutTests.swift`, and R8 in
`Tests/GlowRendererTests.swift`, which asserts the encoded colour space rather
than trusting it.

## 6. Layout

Each habit is one row: icon and name on the left, a fixed-width status track on
the right.

- **Daily:** 7 equal slots, Monday to Sunday, day-pinned.
- **N per week:** N equal slots, the same height as a daily one, filling the
  same total track width.

Given track width `W` and inter-item margin `G`:

```
dailySlotWidth = (W - 6 * G) / 7
slotWidth(N)   = (W - (N - 1) * G) / N
```

**Spans are not pinned to weekdays; the dots on them are.** A span fills left to
right in the order the week is divided, independent of which weekday anything
fell on — it is the *how much*. A lit dot sits on each weekday a completion
actually landed on, at the same column centre a daily row uses — it is the
*when*. The two jobs used to be one mark doing neither well: the row said how
much was left and nothing about when (#47).

## 7. Slot states

Every slot is in exactly one of five states.

1. **Inactive.** A day still to come.
2. **Missed.** A day, or a rep, that can no longer happen. For a daily habit
   that is a past day that went unlogged. For a habit due a number of times a
   week it is a rep with no day left to land on: an empty Monday is still not a
   failure on Tuesday, and it becomes one once no day remains that could have
   carried it. **Never a warning** — the test is strict, `repsLeft >
   actionableLeft`, so on Saturday with two reps owed and Sunday still live the
   row stays clean and the ✕ arrives on Sunday.
3. **Open.** Today's slot, not yet completed. The only glowing state.
4. **Filled.** Completed.
5. **Rest.** The rest day: a day nothing can happen on, which is not the same
   as a day that has not happened yet. It draws nothing at all. Rest wins over
   every other state, a stored completion included.

The states map to *marks* via `Slot.mark`, which is where the rendering
distinctions live and where they are tested.

**A state is what is true, not what can be tapped** (#116). The week view edits
any day it shows, so a missed day is now something you can correct: tapping it
stores a completion, the day becomes filled, and it draws `donePast` — lit,
because §1 says every completion is, and not `doneToday`, because it is not
today. `Slot.isToday` is a real comparison against today for exactly this
reason; it used to be an alias for "carries an action", which was true only
while today was the one day that did. Nothing about *open* moved: at most one
slot is open, on today, on every surface (R1).

For a habit due a number of times a week the same tap changes the arithmetic
rather than one column. A completion on a past day is one fewer rep still owed,
so the week re-divides: the completed block grows, a ✕ that was there because
the reps had run out of days may no longer be owed, and the lit dot appears on
the weekday it was logged. `WeekSpans` decides all of that from the record, as
it always did — the record is simply now something the app can correct.

A habit due a number of times a week is not day-pinned, so it is not drawn as
seven columns at all: `WeekSpans` divides the week into N shapes that stretch
across it, with the open one always containing today. **That rule is inferred
from the design rather than specified** — see the note on the type.

**An achieved span draws the same unlit line as one still to come**, because
they are the same thing: a share of the week with no ask left in it. What tells
them apart is the lit dot on the day it happened, which `WeekDots` places. Two
spans keep their light and their shape: the open one, which is the one thing
outstanding, and the ✕, which is a rep that can no longer happen. A completion
past the goal still lights its day — it has no span, and the row is a record of
what happened rather than of what was owed.

**The dots are spoken as one fact.** `WeekDots.spokenDays` names the weekdays
that are lit — "Workout, logged Tuesday and Friday" — as a single element with
no button trait, in the app and the widget both. One stop rather than up to
six, because a list of days is one answer to one question, and the spans beside
it already say how much is left. What is not drawn is not spoken: a completion
on the rest day counts everywhere it counted and is absent from this sentence,
exactly as it is absent from the row. Weekday names and the way they are joined
both come from the calendar's locale.

**Every day-pinned column speaks its own date.** A slot is a circle in a
column, and which column it is in is the whole answer to *which day* — read on
screen off a header of seven letters over seven numbers, which is a table when
it is read aloud, so the header stays hidden and the date rides on the mark:
"Read, Tuesday 18 August, missed". All seven, not only the one that can be
tapped, and in the widget as well as the app, because a widget row and an app
row are the same row. A span is not given a date it does not have: it is a
share of the week, the dots say when, and the one date it carries is the day a
tap would act on. Dates come from the calendar's own locale and time zone,
like the dots' weekday names.

**A month and a year are counted, not listed.** The month widget hangs one
sentence on the habit's name — "12 days logged this month, 3 days missed, due
today and 9 days still to come" — and the year makes each week column one stop:
"Week of 17 August, 4 days complete, 2 days partly done and 1 day with nothing
logged". Fifty-two sentences is a year somebody can swipe through; 365 stops
reading "complete" is a wall. Both are counted off the marks the grid actually
draws, so what is spoken and what is drawn cannot disagree.

**A weekly row draws exactly N shapes, however late in the week it is.** Each is
at least one column wide and together they cover all seven with no gaps. A rep
with no day left to land on still gets a column — it stops being the open one
and draws a ✕ instead: never a warning, never a prediction, and it does not take
the row down with it. On the widget and in the month it is permanent, because
nothing there can change the past. **In the week view it is not** (#116): the
column under it is a day, and logging that day means the rep happened, late, so
the arithmetic re-runs and the ✕ goes. The mark never changes on its own — only
the record can move it. **A finished week is where this is sharpest** (#117):
every rep it still owed has run out of days, so the row is a completed block and
a ✕ for each of the rest, and every one of those columns is a day the pager can
now reach and correct. **A lost rep never
occupies the rest day's column alone**: `RestWindow` subtracts that column from
whatever shape crosses it, so a span exactly its width would be removed
entirely, and the ✕ would be drawn and invisible. Such a span takes the next
column with it and the mark sits in what is left. The reps still reachable
keep glowing beside it, because a partially lost week is not a finished one.
This used to produce *fewer* than N shapes, and it did so exactly when the goal
was running out of room. The rest day enters only through which days count as
actionable, which brings the squeeze forward by one.

**A lost week shows in the month too.** `MonthGrid` asks `WeekSpans` how many
reps a week lost and crosses that week's unlogged past days — the week row
compresses a loss to one column, the month says which days it cost. Strictly
past: today and the days after it can still be acted on, and a ✕ there would be
a prediction.

**What any of this looks like is deliberately not written down.** The visual
design is being worked on directly and prose here would only go stale between
one experiment and the next; the code is the truth. What is fixed is the
hierarchy in §1, and only because it is the product rather than a style.

**Which slot is open, for a frequency habit.** Count this week's completions.
If `count < N` and today is not already logged, pill index `count` is open.
Otherwise no slot is open: everything filled stays filled, unfilled pills stay
inactive.

**A rest day stops the week.** One optional weekday, set in Settings
(`WeekPreferences.restDay`) and handed to the grids as a parameter rather than
looked up by them (#181), is true rest: its slot is never open, never
missed, and never writable. Nothing can be logged on it and nothing un-logged
— `HabitStore.toggleCompletion` refuses the write, which holds in the widget's
process too, where a stale surface can still offer a button — and the week is
not made up around it: an unreachable weekly goal on a rest week is stopped,
not excused. Frequency rows stop with it: on the rest day nothing is open, so
nothing glows.

**The rest day's column is empty.** Not dim — empty. No socket, no ✕, no
completion, on daily rows in the app and in the widget both. A socket says one
is coming, and on a rest day none is; drawing one was the grid contradicting
what the write path already enforced. A completion already on record **still
counts** — `completedDays` is untouched, weekly totals are untouched, History
still shows it — and is simply not drawn here. That reverses one clause of the
original rest-day decision; see docs/decisions.md. The month widget inherits it
without a second edit, because `MonthGrid` asks `WeekGrid`, so the rest
weekday's column empties there too. VoiceOver still finds the slot, and it
announces "rest day" with no button trait, because otherwise the hole in the
row would have nothing explaining it.

**A span never shows in it either.** A habit due a number of times a week is
drawn as shapes stretching across the week, and a met goal is one shape across
all seven — so without this a met week drew a single lit bar straight through
the day nothing can happen in. The *arithmetic* is unchanged: `WeekSpans` keeps
its seven-column division, its span count and its packing rule, and the shape
is drawn with the rest column subtracted from it (`RestWindow`). The window is
that column's slot plus the gap on each side, so its edges land on the
neighbouring columns' slot edges and a bar ends flush with them rather than
leaving a stub in the air. A bar the window falls inside becomes two pieces; at
either end it simply stops short. An open span keeps its raw, unclosed ends
rather than closing into two rings — a straddling span is one span. A span
falling entirely inside the window draws nothing. The subtraction is applied to
the *shape*, before the glow is generated from it, so the halo wraps the new
ends instead of being sliced flat at them.

The grid draws the cut as one vertical line down the rest day's column, in the
missed cross's grey — absence, which does not glow.
Per-day habits are untouched: Today's rings stay tappable, because water and a
walk are not the thing the rest is from. This reverses "resting is permission,
not a prohibition" — see docs/decisions.md.

**How the cut is drawn.** One line at the span bar's own weight — 2pt, absolute,
`GlowShape.barThickness` — so it reads as part of the grid rather than as a
heavier ✕. It is not a proportion of the slot: it took the missed cross's stroke
until #71, which drew it at roughly 1.2pt on the phone against 2pt bars beside
it. It runs from the **top of the first habit** to the **bottom of the last one
the surface shows**, and no further: never into the header's air, never past the
last row. `RestCut.rows` decides which rows carry it, taking the surface's
capacity — the widget's `rowCapacity`, the app's `largeRowCapacity`, so the app's
line ends on the same hairline that marks where the widget ends. A blank row
*between* two habits is inside the cut and draws its segment; a blank row at
either end is outside it. All three week widget families draw it, on the same
`RestCut` numbers the app uses.

**A per-day habit has no slots and no week row.** It is drawn on Today as a
ring, one segment per repetition, consumed clockwise from the top — see
`DayRing` and docs/vision.md.

**Open is a band, done is a line, and both are lit.** A repetition still open is
an outlined pill: the annulus between the ring's two radii, bounded by its two
angles, corners rounded, its interior left clear and its perimeter a glowing
hairline. A logged repetition is a thin glowing line on the band's centreline,
and consecutive logged ones **merge into one unbroken run** — the line crosses
the gaps between them, and the divisions only survive between repetitions still
open. That is the week grid's rule at a different shape: a run of days there is
one bar, not a row of dots.

**At the goal the line closes into a full circle**, with no break at twelve
o'clock where the first gap was: when nothing is left there is nothing to
divide. A target of 1 is an outlined pill too — two concentric circles with a
black band between them — closing to that same single circle, so "finished" is
one silhouette at every count.

Everything scales from the diameter (`DayRingGeometry`), so the app's 92pt ring
and the two widget rings are one drawing at three sizes. This ring used to paint
a logged repetition grey, which made it the one surface in the app where a
completion went dark, against §1 (#75).

**A tap sweeps.** The line grows clockwise out of the run already logged and
the pill retreats ahead of its head — one number driving both, which is the
grammar `SlotView` and `SpanView` already use, expressed as an angle instead of
a diameter. It starts at the end of the existing run rather than at the new
segment, so it crosses the gap between them on its way; that crossing *is* the
merge. The last repetition runs a full turn and closes the circle. 0.35s,
`.easeOut` — a sweep has nothing past its end to overshoot into, so the closing
spring does not transfer.

This is the completion transition §3 allows, not idle motion: nothing on any
surface moves on its own, and a lit mark still holds still.

**Reduce Motion snaps every drawing of it**, not only this one. One completion
is drawn four ways — the ring closing in a slot, the bar closing across a span,
the row's label dimming beside them, the line sweeping round this ring — and
the setting switches off all four, along with the press that grows a mark under
a fingertip. What it produces is the final state with nothing scheduled in
between: a shorter animation is still an animation. `MotionPolicy` holds the
rule; the widget's own completion already carried it, recorded at the tap and
spent on a timeline of one still entry. **Everything other
than a repetition being logged snaps.** The reset is instant, because animating
a correction dresses a mistake up as an achievement. Any jump other than +1 is
instant — a tap arriving from the widget, a day rolling over, an edit — because
none of those is a gesture made on this ring. Reduce Motion snaps. The widget
does not run it at all: a tap there goes through `TapHabitIntent` and WidgetKit
renders the next entry, and all that is asked is that it lands on the settled
drawing.

**A tap on the ring is one more.** Once the ring is full, the next tap resets
the day to zero — the reset is the whole undo, and the day's completion rows
are genuinely deleted, not marked over. The rule is `DayRing.countAfterTap`,
applied by `HabitStore.recordTap`, so the app and the widget cannot disagree
about what a tap means. From the home screen the same tap goes through
`TapHabitIntent` without opening the app; the Today widget that will use it
arrives with #19.

**Both screens create and edit their own habits, through one editor.** Today
and This Week carry the same trailing pair — Edit, then add — so the two tabs
wear one piece of chrome rather than two that resemble each other. Adding from
a screen opens the editor on that screen's kind, so what you make appears
where you made it: Today opens on **Daily**, This Week on **Weekly**. Today's
add is a plain button rather than This Week's menu, because a blank row holds
a position in the week grid and there is no grid here to hold one in.

**A blank row belongs to This Week, and only weekly habits touch it** (#143).
Adding a Today habit never fills one, and deleting a Today habit never leaves
one — otherwise a screen with no blank-row layout would be silently rearranging
a screen that has. A weekly habit still leaves its position behind when it goes
and the next weekly habit still takes it, which is the rule that makes the grid
something you can arrange.

**A deleted habit does not keep its identity** (#129). The row survives; the
`id` does not. Widget configurations and widget intents both resolve habits by
`id`, so a row that kept it would hand the next habit the last one's widget
selection, and would let a tap made from a widget snapshot rendered *before* the
delete land as history on whatever fills the row next. The store also refuses
every day-shaped write to a blank row or to a habit of the wrong cadence, on the
same reasoning as the rest day's refusal: the widget runs in a second process
and its surface can outlive what it draws, so the rule lives on the write path
both processes share.

**"Daily" means two different things, and only one of them is on screen.** The
editor's `Daily` segment means *counted within a day* — a ring on Today, N
repetitions that reset at midnight. The model's `Frequency.daily` means a
seven-times-a-week cadence, which is a *weekly* habit and sits under `Weekly`;
it is why "7x per week" is the wording for the everyday case rather than a
separate mode. The label is what the person reads; the enum keeps its name
because `Habit.countedPerDay` and `countedPerWeek` are built on it.

**Every slot in the week view is a plain button** (#116). No edit mode, no long
press, no confirmation: a tap on Monday marks or un-marks Monday, exactly as a
tap on today does for today. Today still glows and still reads as the live one;
the other six are tap targets that happen not to be lit, which is §1 doing its
job — light says what happened, and shape says what is still open. The cost is
accepted: a stray tap changes a day, and nothing distinguishes a correction from
an original. That is what editing the past means.

**The week view pages back through earlier weeks** (#117). Two chevrons in the
toolbar, opposite Edit and Add — buttons rather than a swipe, because every row
already carries swipe actions for edit and delete. An earlier week is edited
exactly as this one is: the surface has not changed, and all seven of its
columns are past, so all seven are tap targets. Nothing is open in it, because
nothing is open anywhere but today (R1).

**How far back: as far as the record reaches, capped at twelve weeks.** The
record starts at the first completion on record or the first habit's creation,
whichever is earlier — the demo invents completions ten weeks before the habits
that carry them, so neither alone is the answer. A week before anything existed
holds nothing to correct, so a fresh install pages nowhere and the reach grows
with the app's own history. The cap keeps the pager finite and makes the one
unusable value harmless: `Habit.createdAt` defaults to `.distantPast` for rows
written before the column existed. Forward stops at the current week; further
back than a quarter, the surface is History, which is a year of days and does
not respond to touch on purpose.

**The title names the week you are looking at.** The month of today when today
is in the visible week, and of the week's first day otherwise — so a week
straddling a month end still reads as the month you are in. The year appears
only when it is not this one. The dates under the weekday letters say the rest,
and on a week with no today in it no column is lit.

A span row resolves the tap to **the column under the finger** rather than to
the span's nominal day, so a habit due N times a week records the weekday it
really happened on — the same day the month grid and the row's own dots already
draw it on. Touching the rest day's column inside a span does nothing: the
column is drawn as a hole, and pressing a hole is pressing nothing.

**Edit mode gives the week's width back** (#164). `List` draws a delete circle
at the leading edge of every row and a reorder handle at the trailing one, and
while it does, everything weekday-shaped leaves: each row's track, the rest-day
cut positioned from the same geometry, and the header's letters, all on one
0.15s fade. The icon and name recentre between the system's two controls — not
in the vacated track, which would leave them a third of the way across. A blank
row has nothing to fade and nothing to centre; it shows the two controls and the
gap it stands for. Reduce Motion snaps the change rather than shortening it.

**Edit changes what a ring's tap means** rather than adding a second control
beside it: out of edit mode a tap counts, in edit mode it opens that habit in
the editor, where renaming, re-targeting and deleting already live. Today is a
grid of rings, not a `List`, so there is nothing for edit mode to reorder.

## 8. Acceptance criteria

- [x] A daily habit shows exactly 7 circles for the current Monday-Sunday week.
- [x] An N-times habit shows exactly N pills, per the width formula, with the
      same margins as a daily row.
- [x] Tapping today's open slot marks it complete, persists a `Completion`, and
      runs the fill transition.
- [x] Tapping today's filled slot un-marks it, reverting to open with the glow
      resumed.
- [x] Tapping any other day of the week in the app marks or un-marks *that*
      day; the widget offers today and nothing else.
- [x] Days still to come are tappable only with demo history in.
- [x] At most one slot per habit is open at a time.
- [x] Without EDR the glow renders as flat colour, no crash, no artifact.
- [x] Restarting preserves all habits and completions.

Each was verified in the simulator and is held by a test.

The glow itself is confirmed on an iPhone 14 Pro: with it on screen the system's
granted EDR headroom rises from 1.2 to 6.0, matching what the renderer asks for.
What no test and no measurement can answer is whether it *reads* as lit in a
given room, which stays a matter of looking at it.

## 9. The widgets

Two widgets, reading the same store through an App Group.

**The week widget**: three families. Today's slot is a button backed by an
`AppIntent`, so a habit can be logged from the home screen without launching
the app. Past days are not buttons here even though the app's own grid now
edits them: a widget is a glance and a single confirmed action, and it has no
touch location to resolve a span's column with. `SlotEditing.todayOnly` is how
the surface says so, and `HabitStore` refuses a day ahead whatever the surface
offers.
Rows are as many as fit, then a hard cut — no "+N more" row, per
docs/vision.md: a row spent saying how much is missing is a row not showing a
habit. The app's own grid marks the boundary, where there is room to say it.

**The Today widget**: small and medium, and deliberately no large — three
rings already say everything it could. Small is one habit's ring, and the
person picks which habit per widget, so several small widgets can sit on one
home screen showing different habits. Medium is the first three per-day
habits in the user's own order, all the same size, with nothing to configure.

**The month widget**: small only, one weekly-cadence habit's calendar month
as marks on weekday columns — the same marks the week draws, decided by
`MonthGrid` asking `WeekGrid`, so the two surfaces cannot disagree about a
day. The 1st sits under the weekday it really falls on, so the first and last
rows are ragged. The habit is chosen per widget; per-day habits are not
selectable, because their day is a count, not a yes. Today's dot is a button
through `ToggleHabitIntent` — no other day is, which is R2 in a third grid —
and everything else opens This Week. Two readings held deliberately small
until decided otherwise (#41): an N×/week habit's empty days are sockets,
never crosses — the week grid's own rule, not a per-week verdict — and rest
days get no month-specific treatment beyond what `WeekGrid` already says
about them.
Each ring is a button backed by `TapHabitIntent`: one more repetition, or the
reset from a full ring, without leaving the home screen.

**The widget chooses the screen.** A widget's surface divides in two: the
marks act in place through their intents and open nothing, and everything
else opens the app on that widget's own screen — `glow://today` from the
rings, `glow://week` from the grid, mapped by `DeepLink` in `Logic/`. There
is no fixed landing tab; a cold launch opens This Week, since the app icon
has no widget to ask.

Nothing breathes, anywhere. The widget's pulse was built, measured working
(WidgetKit renders sub-minute entries, contrary to its reputation), and removed:
it costs the day's entire refresh allowance, and a stale widget is worse than a
still one. The app's own breath followed, for a different reason — brightness is
the one signal, and movement said it twice. A lit mark is lit and holds still.
See docs/glow.md.

The store therefore lives in the App Group container rather than the app's
private one, and a pre-widget store is migrated into it on first launch — staged
in full, opened to prove it is a whole store, and only then promoted, with the
old one left where it is. A migration that cannot be completed stops the launch
on a screen that says so rather than starting with an empty list. Without the
App Group entitlement the app falls back to its own container and keeps working;
only the widget goes blank, which is a better failure than refusing to launch.

## 10. Resolved questions

The spec's open questions and their answers are in
[docs/decisions.md](docs/decisions.md).
