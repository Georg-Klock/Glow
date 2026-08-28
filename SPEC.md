# Glow Up Habit Tracker, product spec (v1)

Product truth. Where this and the code disagree, one of them is a bug; say
which in the same session you find it.

## 1. Concept

A habit tracker built around one weekly overview: a grid of habits by day,
filled when done. Two more tabs stand beside it — Widgets, which is how the
main product gets onto a Home Screen, and Settings — see `docs/vision.md`'s
three-screen section; the grid is where the work happens and where every
launch lands.

Today's column physically glows on HDR-capable screens: it is drawn from an
image encoded in a colour space with real headroom above SDR white, which is
what makes HDR photos look brighter than white in Photos.

**Light means something happened.** Every completion is lit, whatever day of the
week it fell on, and so is today's open slot. What stays dark is anything merely
absent: a missed day and a day still to come are both flat. So a good week is a
row of lights and a bad one is nearly dark, which is the whole product in one
sentence.

**Light has two tiers** (#334). The HDR emission — the physical glow of the
opening paragraph — is reserved for what is still actionable: today's weekday
letter while any habit is still open, the icon and name of a habit open today,
and the open mark. A completion is lit but does not emit; it reads as an object
catching light rather than as a source of it. The sentence above is unchanged by
this — every completion is still lit, and absence is still dark — what the
second tier adds is a *ceiling* a completion does not reach.

That is not #75 reversing. #75 refused to paint a completion grey and still
does; a completion is bright on every surface. #75's reasoning was written when
there was one tier, so it is re-read rather than cited.

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
- **A fresh install chooses its starting point** (#228). An empty grid offers
  two buttons: **Add Your First Habit**, which opens the ordinary editor, and
  **Start with a Pre-Selected Set**, which installs `DefaultHabits.all` — the
  eight curated habits in three clusters, with no completions — immediately, no
  confirmation step. The list used to go in by itself on first launch; it is
  offered now. Every habit it puts in is an ordinary one afterwards: rename,
  retarget, reorder, delete, exactly like anything typed by hand.

  **The screen is those two buttons and nothing else** (#243). No icon, no
  title, no description: an empty grid, centred on the choice it is asking for.
  The sentence that used to say the curated set is editable went with them —
  what it answered is still true and is stated here, but it is not on the
  screen. What a screen reader reaches is the same two buttons, for the same
  reason: the icon carried no label, so the title and the description were the
  whole of the spoken difference and they left both at once.

  **An empty store means one thing.** Nothing seeds automatically, so a store
  nobody has added to and a store emptied by deleting every habit are the same
  state and get the same offer. The flag that used to tell them apart —
  `didSeedDefaultHabits` — is gone with the seeder that wrote it.
- The glow renders on EDR-capable devices and degrades to plain colour where it
  cannot, with no broken state either way.
- ~~Two kinds of habit, never mixed: counted across a week (daily, or
  N-times-per-week with no day pinning), or counted within a day (N times
  today, resetting with the day).~~ **One kind: counted across a week**
  (#209). The per-day kind shipped, and it is 2.0 scope rather than MVP — it
  is preserved whole on `feature/daily-habits-2.0`, along with the Today
  screen and the two Today widget families it was drawn on. It was built; it
  is not shipping yet. See docs/vision.md.

## 3. Non-goals (v1)

- **No sync.** Local SwiftData only. Sync stays a clean follow-up as long as
  the model is normalized now, which is why it is.
- **No fixed-weekday schedules.** "Every Mon/Wed/Fri" is out of scope.
  Frequency habits are pure count-based; any day counts.
- **No multiple completions per day.** A habit is done or not done for a
  day, enforced by `toggleCompletion`. This was struck through while the
  per-day kind shipped — each repetition was its own `Completion` row — and it
  stands again (#209). A row is still the storage shape, and a day can still
  be found holding two: a store written before day identities can carry a
  duplicate (#130), and `clearDay` is what puts one right.
- **No notifications or reminders.**
- ~~**No export.**~~ **There is one.** Settings → Data → Export History writes
  a CSV or a JSON file and hands it to the share sheet. No account, no
  destination the app chooses, and **nothing leaves the device unless a person
  sends it** — the file is written at the moment of the tap, into the app's own
  temporary directory, and never otherwise. That is a privacy claim true by
  construction rather than by policy. `HistoryExport` is pure and its bytes are
  asserted. **And it is all or nothing** (#282): the snapshot read throws, so a
  fetch failure stops the export before a file exists — no share sheet ever
  opens over a partial read, no partial file is left behind,
  and the failure is said out loud with a safe retry (an export is a read;
  retrying doubles nothing).

  There was briefly a second way out of the same writer — **Email My History**
  handed the same file to Apple's mail composer (#289) — and it was removed
  the day after it landed (#317): the share sheet already lists Mail among its
  destinations, so the row was a second flow to the same place. The file
  remains an export, not a backup — no recovery promise attaches to it (see
  the 2026-08-25 entries in docs/decisions.md).
- **No undo — and one action that therefore has to ask twice.** Settings → Data
  → **Reset to Default Habits** deletes every habit and every completion and
  installs `DefaultHabits.all` fresh, which is the way back to the shipped list
  once a store holds something — the empty state's own offer of that list is
  gone as soon as there is a habit on screen. Because nothing here is
  recoverable, the confirmation is **typed rather than tapped**: the destructive
  button stays disabled until the word `RESET` is in the field —
  `ResetConfirmation` is the rule, and it forgives case and surrounding
  whitespace and nothing else. The reset is one transaction — either the
  defaults are in or the store is untouched. The empty state's second button
  makes the same call without a confirmation, because a store with nothing in it
  has nothing to lose.
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
  about the surfaces that *record state*: the grid and the widgets, both of
  which say one thing in one register. The pop is outside all of them, it is
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

  **A correction says nothing.** Un-logging a day fires no pop. An acknowledgement for taking something
  back is the app congratulating somebody for an undo.

  **One pop at a time, whose words change** (#102). Two goals met inside the
  two seconds is not an edge case — the medium Today widget put three rings
  side by side so they could be tapped in a flurry, and the week widget puts a
  column of slots there now. A second goal updates the
  running activity rather than requesting another; the ending belongs to the
  most recent one, so nothing is cut short.

**A mark from a widget sets a state; it does not flip one** (#272, #292).
`MarkHabitIntent` carries the state the tapped mark was *asking for* — a ring
means "make this done", a dot means "make it not done" — and
`HabitStore.setCompletion` writes only if the day is not already in it. Asking
twice logs once.

The reason is that a widget is the wrong surface for a relative operation, and
both of its failure modes turn a toggle into the same bug. **It can be
delivered twice**: a single tap has been measured performing the intent twice,
13ms apart, on an iPhone 14 Pro. **And it can be stale**: WidgetKit's pixels
lag the store by seconds, so a tap lands on a ring for a day the store already
holds as done, and a toggle reads that as "flip" and removes the completion the
person was making. Both produced the same complaint — checking habits off
quickly un-does them.

The asymmetry settles it: the worst a set can do is nothing, and the worst a
toggle can do is silently retract a record of something that happened. **The
app's own surfaces keep the toggle**, because they redraw in-process from the
store they just wrote and are never the stale caller this is about.

**And the mark draws the state it asked for, without waiting** (#292). The
tappable mark is an AppIntent-backed `Toggle` whose style renders
`configuration.isOn` — the one mechanism WidgetKit gives an app for pixels
that change at the tap rather than after the provider has been scheduled,
which #121 measured at seconds. The tap flips the mark in place, the intent
writes, and the guaranteed reload reconciles to the store — which is also how
a refusal takes an optimistic flip back. `SlotToggle` owns the control; the
week's slots and spans and the month's cell are its three call sites, and a
mark that is not tappable is not a `Toggle`, exactly as it was never a
`Button`. VoiceOver's label, value and hint follow the same `isOn` the pixels
do, so the announcement cannot lag the mark.

  **It fires from the home screen only** (#103). The Island does not render a
  Live Activity while its own app is in the foreground, so a goal met inside
  the app would spend its two seconds on nobody. `GoalPopCentre` is called from
  `MarkHabitIntent` and from nowhere else — it was two intents until #209
  took the ring's away; the app's
  acknowledgement is the one it already had, which is the ring closing and the
  row going quiet.

  The alternative was to rewrite §1 so that light may also mean *well done*.
  That was declined: it would put a second meaning on the one signal the app
  has. See docs/decisions.md.

## 4. Data model

```swift
enum Frequency { case daily, timesPerWeek(Int) }
// timesPerWeek: 1...6 selectable, 7 collapses to .daily
// timesPerDay(Int) was a third case; see feature/daily-habits-2.0 (#209)

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

**Week boundary.** A week starts on the weekday Settings says it does:
`WeekPreferences.firstWeekday`, defaulting to Monday and never to the locale's
answer — locale would say Sunday in the US and silently shift every column,
and the week start is not a formatting detail here, because it decides which
seven days a "week" of habits is and so which completions count toward a
weekly goal. All "this week" queries filter into `[startOfWeek, +7 days)`
using the user's calendar with that `firstWeekday` applied, and the weekday
header rotates to match (`WeekCalendar.weekdayInitials`).

## 5. Invariants

A build that violates one of these is broken regardless of what else works.

- **R1.** At most one slot per habit is open at a time, and only ever for the
  current day.
- **R2.** A slot responds to taps only where its surface allows it. The week
  view edits any day of the week it shows; the widget, its intents and the month
  grid edit today and nothing else. A rest day is never editable on any surface.
  The days *ahead* are editable only with demo history in — outside it you can
  correct the past, not claim the future. **The week it shows need not be this
  one** (#117): the view pages back as far as the record reaches — all of it,
  with no cap since #186 — and a week entirely in the past is editable end to
  end. Forward stops at the current week.
- **R3.** A day holds zero or one completion. Never two. The per-day kind was
  the exception — one row per repetition, up to the habit's target — and it is
  gone (#209).
- **R4.** A completion names one civil day and keeps naming it. Changing time
  zone, crossing a DST transition or relaunching does not move it, and a
  completion the app can see is a completion the app can un-log.
- **R5.** A daily row draws exactly 7 slots; an N-times row draws exactly N
  spans — met, behind or finished, however late in the week it is — plus one lit
  dot per completion, on the weekday it happened.
- **R6.** Every row spans the same track width, whatever its slot count.
- **R7.** Weeks reset clean. A frequency habit's unmet goal does not carry over.
- **R8.** The glow is encoded in a colour space with headroom above SDR white.
  Without EDR the app renders flat colour, never a broken or blank slot.
- **R9.** Empty means read-and-found-nothing, never read-failed (#282). A
  surface may show "No habits yet" only after a successful read of a store
  that holds no habits; a failed container or fetch renders a distinct
  unavailable state that points at the app. And a failed user action is told
  to the person who acted — a fixed sentence through `OperationNotices`, with
  a retry only where retrying is safe and never on a destructive operation —
  not only to the log. Error surfaces never carry habit names, identifiers,
  paths, or framework error text.

**"Today" is whatever `WeekCalendar.today()` answers**, not what the clock says
(#204). R1 and R2 are stated against that rather than against the clock, so the
debug override below moves them without weakening them: exactly one slot is
open, on exactly the day the app believes it is on, and the write path refuses
anything after it.

R1, R2, R5 and R7 are asserted in `Tests/WeekGridTests.swift`, including an
exhaustive pass over all 128 possible completion histories of a week — run under
each surface's rule, so R2 is asserted as the difference between them rather
than as one answer, and run again over an earlier week, which is the branch with
no today in it. `Tests/SlotEditingTests.swift` covers the rule itself and the
geometry that resolves a touch on a span into a weekday.
`Tests/WeekReachTests.swift` covers how far back the pager goes, and asserts the
pager's one invariant — an enabled back chevron always lands on a *different
week* — over nine time zones, three week starts and a year of days (#242), and
again over a six-year record walked week by week to its first week (#186). R3 is asserted
in `Tests/PersistenceTests.swift`, which also asserts the store's own refusal of
a day still to come, and R4 in `Tests/DayIdentityTests.swift` — Los Angeles to
Berlin and back, both DST directions, and a zone whose clocks move at midnight.
R6 is in `Tests/SlotLayoutTests.swift`, and R8 in
`Tests/GlowRendererTests.swift`, which asserts the encoded colour space rather
than trusting it.

## 6. Layout

Each habit is one row: icon and name on the left, a fixed-width status track on
the right.

- **Daily:** 7 equal slots, one per weekday in the calendar's own week order,
  day-pinned.
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
across it, with the open one always containing today.

> **A mark spans from the end of the previous mark through its own anchor day**
> (#339).

That sentence is the whole layout, and it is also the forgiveness mechanism: a
day that goes by unused has no mark of its own, so it is swallowed by whatever
mark comes next rather than left as a hole. A completion anchors on the day it
was logged, a rep that ran out of days on the day it ran out (#341), and the
open mark on today. Marks with no anchor — reps still to come — divide what the
anchored ones leave, **as evenly as whole days allow with the remainder to the
right** (#340), so the near days are single columns and the slack collects at
the end of the week. The last mark always ends on the final column, because
there is nothing after it to divide.

**A met goal keeps every completion on its day** (#342). It used to collapse to
one shape across all seven columns, which forgot every day it had just
recorded; now the last mark runs to the end and the earlier ones stay where the
reps happened. Completions past the target get no mark of their own and fall
inside the last one, so a 3x row logged four times looks exactly like a 3x row
logged three times — the record keeps the fourth, the row has nothing left to
say about it.

The rule used to be **inferred from the design rather than specified**; it is
specified now, in `docs/week-marks.md` §4.

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

**A month is counted, not listed.** The month widget hangs one sentence on the
habit's name — "12 days logged this month, 3 days missed, due today and 9 days
still to come" — because thirty-one stops is a wall when each must be swiped
through one at a time. It is counted off the marks the grid actually draws, so
what is spoken and what is drawn cannot disagree. (The year grid was the other
counted surface, one sentence per week column, until #316 removed it.)

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
now reach and correct. **A ✕ lands on the day the week broke on** (#341): the blank past day after
which the goal became unreachable, derived from the record rather than logged,
so a backfill recomputes it away. It used to be parked immediately left of the
open span, which surfaced a missed Monday on a Thursday. **A lost rep never
occupies the rest day's column alone**, which matters because `RestWindow`
subtracts that column from whatever shape crosses it and a span exactly its
width would be drawn and invisible (#100). That now holds by construction: a
rep never dies on the rest day — nothing is expected there — so a ✕ is never
anchored on it, and a mark reaching back from a later anchor is wider than one
column. The reps still reachable keep glowing beside it, because a partially
lost week is not a finished one. This used to produce *fewer* than N shapes,
and it did so exactly when the goal was running out of room. The rest day
enters only through which days count as actionable, which brings the squeeze
forward by one.

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

**"Today" can be simulated, deliberately and visibly** (#204). Settings → Data
→ **Debug: Override Today** picks another day of the current week and the whole
app treats it as today: the open slot moves to it, the edit rules move with it,
the widgets follow from their own process, and **a tap logs a real completion
dated to that day**. It is a simulation, not a preview — which is why it is
scoped to the real current week, cleared whenever the app relaunches, and
announced by a persistent banner on every screen that reads it, with one tap on
the banner to turn it off. It ships in every build, TestFlight included, for the
reason demo history does: the phone is where this app is tested.

**A rest day stops the week.** One optional weekday, set in Settings
(`WeekPreferences.restDay`) and handed to the grids as a parameter rather than
looked up by them (#181), is true rest: its slot is never open, never
missed, and never writable. Nothing can be logged on it and nothing un-logged
— `HabitStore.setCompletion` refuses the write, which holds for the widget's
taps too, because its surface renders in another process and can still offer a
stale button (the tap itself arrives through `MarkHabitIntent`, in the app's
process since #58's `LiveActivityIntent` conformance) — and the week is
not made up around it: an unreachable weekly goal on a rest week is stopped,
not excused. Frequency rows stop with it: on the rest day nothing is open, so
nothing glows.

**The rest day's column is empty.** Not dim — empty. No socket, no ✕, no
completion, on daily rows in the app and in the widget both. A socket says one
is coming, and on a rest day none is; drawing one was the grid contradicting
what the write path already enforced. A completion already on record **still
counts** — `completedDays` is untouched, weekly totals are untouched — and is
simply not drawn here. That reverses one clause of the
original rest-day decision; see docs/decisions.md. The month widget inherits it
without a second edit, because `MonthGrid` asks `WeekGrid`, so the rest
weekday's column empties there too. VoiceOver still finds the slot, and it
announces "rest day" with no button trait, because otherwise the hole in the
row would have nothing explaining it.

**A span never shows in it either.** A habit due a number of times a week is
drawn as shapes stretching across the week, and a met goal's last mark runs to
the end of it — so without this a met week drew a lit bar straight through the
day nothing can happen in. The *arithmetic* is unchanged: `WeekSpans` keeps
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
This reverses "resting is permission, not a prohibition" — see
docs/decisions.md. The exception it carried, that Today's rings stayed tappable
on a rest day because water and a walk are not what the rest is from, went with
the rings (#209).

**How the cut is drawn.** One line at the span bar's own weight — 2pt, absolute,
`GlowShape.barThickness` — so it reads as part of the grid rather than as a
heavier ✕. It is not a proportion of the slot: it took the missed cross's stroke
until #71, which drew it at roughly 1.2pt on the phone against 2pt bars beside
it. It runs from the **top of the first habit** to the **bottom of the last one
the surface shows**, and no further: never into the header's air, never past the
last row. `RestCut.rows` decides which rows carry it, taking the surface's
capacity — the widget's `rowCapacity`, the app's `largeRowCapacity`, so the app's
line ends on the same hairline that marks where an unconfigured large widget
ends. On a configured widget the cut runs over the rows that widget draws, in
the order it draws them, because `RestCut.rows` has an opinion about a list and
none about where the list came from. A blank row
*between* two habits is inside the cut and draws its segment; a blank row at
either end is outside it. All three week widget families draw it, on the same
`RestCut` numbers the app uses.

**The Today ring is not in this build** (#209). A per-day habit had no slots
and no week row: it was drawn on Today as a ring, one segment per repetition,
consumed clockwise from the top — open a lit outlined band, logged a lit line,
consecutive logged ones merging into one unbroken run that closed into a full
circle at the goal. A tap was one more, and a tap on a full ring reset the day
to zero. All of it is on `feature/daily-habits-2.0`, and the paragraphs that
described it here are in this file's history at that branch's tip rather than
summarised badly above. What it settled that outlives it is in
docs/decisions.md: light marks the habit at every shape, and #75's reversal of
the ring's grey is what closed the last surface where a completion went dark.

**Reduce Motion snaps every drawing of a completion.** One completion is drawn
three ways — the ring closing in a slot, the bar closing across a span, the
row's label dimming beside them — and the setting switches off all three, along
with the press that grows a mark under a fingertip. It was four while the Today
ring's sweep shipped. What the setting produces is the final state with nothing
scheduled in between: a shorter animation is still an animation. `MotionPolicy`
holds the rule; the widget's own completion carries it too, recorded at the tap
and spent on a timeline of one still entry.

**This Week creates and edits its habits through one editor.** It carries one
trailing control: an ellipsis menu holding **New Habit**, **Blank Row** and
**Edit** (#320) — the Edit item itself reads **Done** while editing, so leaving
edit mode is the same two-tap menu action as entering it, and there is one
control on screen at all times. The menu belongs to the current week only
(#207): paged back, the trailing slot holds **Today** instead, because
reordering, deleting and adding are properties of the list and mean nothing
more three weeks ago than they mean now. The editor opened on the adding
screen's *kind* while there were two of them (#209); there is one, so it opens
on the count and nothing else.

**A blank row is grouping somebody put there** (#143, narrowed by #257).
Blank rows exist so habits can be clustered, and they are made deliberately —
"Add Blank Row" — never as a side effect. Deleting a habit removes its row and
everything below moves up; adding a habit appends past every blank row rather
than consuming one. Both of those were the other way around until 2026-08-24,
as one pair: a row's existence was stable and only its contents changed. A
delete that leaves a row behind reads as a delete that did not work, and then
has to be done twice; an add that eats a blank row takes away a separator. See
`docs/decisions.md`.

**A deleted habit does not keep its identity** (#129). Widget configurations
and widget intents both resolve habits by `id`, so a deleted habit's `id` must
stop resolving to anything — otherwise a configured widget could start showing
an unrelated habit, and a tap made from a widget snapshot rendered *before* the
delete could land as history on whatever came next. Deleting the row outright
is what provides that now; it used to be provided by retiring the `id` of the
blank row left behind. The store also refuses every day-shaped write to a blank
row or to a habit of the wrong cadence, on the same reasoning as the rest day's
refusal: the widget's surface renders in a second process and can outlive what
it draws, so the rule lives on the one write path every surface's tap reaches.

**"Daily" meant two different things, and one of them is gone** (#209). The
editor had a `Daily` segment meaning *counted within a day* — a ring on Today,
N repetitions resetting at midnight — beside a `Weekly` one. That segment, and
the picker holding it, came out with the kind. `Frequency.daily` is the sense
that remains and always was the weekly one: a seven-times-a-week cadence, which
is why "7x per week" is the wording for the everyday case rather than a
separate mode.

**Every slot in the week view is a plain button** (#116). No edit mode, no long
press, no confirmation: a tap on Monday marks or un-marks Monday, exactly as a
tap on today does for today. Today still glows and still reads as the live one;
the other six are tap targets that happen not to be lit, which is §1 doing its
job — light says what happened, and shape says what is still open. The cost is
accepted: a stray tap changes a day, and nothing distinguishes a correction from
an original. That is what editing the past means.

**The week view pages back through earlier weeks** (#117, #190, #207). Two
toolbar buttons, and **the pair is asymmetric**: on the current week only `<`,
disabled when there is no record to page into; off it, `<` and `>` together. A
forward chevron on the newest week there is would be a control that can never do
anything. Off the current week the trailing slot holds **Today**, which jumps
straight home rather than stepping — a way out of a place you paged into is not
one tap per week you came back through, and with no cap that walk is as long as
the record. There is no gesture: #190's header swipe is out (#207), and the
rows keep their own swipe actions for edit and delete. An earlier week is edited
exactly as this one is: the surface has not changed, and all seven of its
columns are past, so all seven are tap targets. Nothing is open in it, because
nothing is open anywhere but today (R1).

**How far back: as far as the record reaches, and no further** (#186). The
record starts at the first completion on record or the first habit's creation,
whichever is earlier — the demo invents completions ten weeks before the habits
that carry them, so neither alone is the answer. A week before anything existed
holds nothing to correct, so a fresh install pages nowhere and the reach grows
with the app's own history. **There is no cap.** There was one, of twelve
weeks, and both of its reasons are gone: how much rope a person gets was
decided the other way, and the value that made an uncapped reach unbounded is
refused where it is read rather than clipped where it is used —
`Habit.createdAt` defaults to `.distantPast` for rows written before the column
existed, which means *unknown*, and a habit whose only signal is that default
starts no record at all. Forward stops at the current week. The pager is the
only long view now: the Settings History screen — a year of days that did not
respond to touch on purpose — went with #316, so the week view's reach is where
the record is read.

**The title names the week you are looking at: how long ago, then which days**
(#190, #207). "This Week", "Last Week", "Two Weeks Ago" — and past the third
rung a relative phrase stops being an answer, so the title becomes the days the
week covers. "17 – 23 Aug" inside one month, "31 Aug – 6 Sep" across a month
end; the year appears only when it is not today's, and a year both ends share is
said once: "29 Dec 2025 – 4 Jan", "20 Oct – 26 Oct 2025". Under the title, the
half it leaves out — the dates while the title is a phrase, "5 weeks ago" once
the title is the dates. On the current week the title stands alone. The dates
under the weekday letters say the rest, and on a week with no today in it no
column is lit.

**Edit mode ends when you leave this week** (#207). The menu that holds its
entry and exit is on the current week only, so paging back while editing would
leave the list fanned open with no Done on screen. The mode goes with the week
rather than the exit going missing.

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

**Every name reads plain white while editing** (#206). Outside edit mode a name
is grey until its habit is due today and lit while it is — §1's rule carried
through to type. Editing is the one moment that reading stops being the useful
one: nobody reordering a list is asking what they are due for, and half the
names sitting at the unlit grey is half the list hard to read at exactly the
wrong time. So the crossfade steps aside for a flat `GlowPalette.color` — the
header's own white, not the halo, because the halo is the same claim an open
ring makes and wearing it on every row would say every habit is due at once. The
due/not-due state itself is untouched: leaving edit mode returns each name to
where the crossfade already was.

## 8. Acceptance criteria

- [x] A daily habit shows exactly 7 circles for the current week, in the
      calendar's own week order.
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
- [x] A fresh install shows both starting points; the primary opens the habit
      editor, the secondary installs the eight curated habits with nothing
      logged. Deleting every habit returns to the same two buttons, and a
      relaunch leaves the store empty rather than refilling it.

Each was verified in the simulator and is held by a test.

The glow itself is confirmed on an iPhone 14 Pro: with it on screen the system's
granted EDR headroom rises from 1.2 to 6.0, matching the 6x the renderer asked
for when it was measured. The ask is a Settings slider now, 2x by default — see
docs/glow.md — and the mechanism the measurement confirms is unchanged. The
halo has its own switch beside the slider: **No halo**, off by default, removes
the light a lit mark spreads onto the ground while the mark's own HDR fill
stays (#313). Both are stored in the App Group, so the widgets obey them too.
What no test and no measurement can answer is whether it *reads* as lit in a
given room, which stays a matter of looking at it.

## 9. The widgets

One widget, reading the store through an App Group: kind `"GlowWidget"`,
three sizes, one content type per size (#322). Medium and large draw the week;
small draws one habit's month. They were two kinds — "This Week" and "This
Month" — until #322 collapsed them, and three until #209.

**`GlowMonthSmall` is removed rather than renamed**, so a placed Month widget
keeps its slot, freezes, and never updates again — Apple provides no way to
move a placement from one kind to another. That is what #209's removals cost
too, and there the loss was the point: the feature was being pulled. Here a
working widget quietly dies in a reorganisation, and **what makes that
acceptable is arithmetic, not design: the app has one user, and he is the one
asking.** A kind change is not free, and the next one proposed should not read
this entry as precedent that it is — it was the population that made this
cheap, not the mechanism.

**Small's history**: the week's own small family was dropped by PR #277 — it
drew the week's rows with the labels off, legible only to somebody who knew
their own row order. #322 brings the family back with the month's content,
which names its habit, so #277's objection does not transfer. A pre-#277 small
week placement that was still frozen on a Home Screen starts being served
again by this change, now drawing a month (#321 closes with it).

**The week, at medium and large.** Today's slot is an `AppIntent`-backed toggle
(`SlotToggle`, #292), so a habit can be logged from the home screen without
launching the app and the mark flips at the tap rather than at the next
provider run. Past days are not tappable here even though the app's own grid
now edits them: a widget is a glance and a single confirmed action, and it has
no touch location to resolve a span's column with. `SlotEditing.todayOnly` is
how the surface says so, and `HabitStore` refuses a day ahead whatever the
surface offers.
Rows are as many as fit, then a hard cut — no "+N more" row, per
docs/vision.md: a row spent saying how much is missing is a row not showing a
habit. The app's own grid marks the boundary, where there is room to say it.

**Which rows is a per-widget choice; the order is always the app's.** Both
wide families offer it; the same sheet also holds the small size's habit
choice, because one kind carries one intent and the system's sheet cannot vary
its fields by family. The intent type is unchanged (`SelectWeekLayoutIntent`
gained a `habit` parameter), which is what lets an already-placed week widget
keep its stored rows through #322 — changing a kind's intent type is what
resets its configuration. The picker lists every week-shaped row in the app's order —
including the blank rows, labelled "Blank Row", which the month widget's
picker excludes — and the widget draws the chosen ones **in the app's order**,
whatever order they were chosen in. A widget nobody has configured keeps the
whole of the app's list, which is what every widget already placed does after
this ships. A chosen row that has since been deleted is dropped rather than
held as a gap; a widget whose every chosen row is gone shows the empty state
rather than silently becoming someone else's first rows. `WidgetRows` decides
all of that and is where the rules are tested.

**The order is dropped deliberately, not for want of one.** #188 asked for
"which habits and in what order", and the ordering half turned out to be
available: measured on an iPhone 14 Pro, WidgetKit hands an array-of-entity
parameter to the provider **in the sequence the rows were tapped** (#191). It
is not used, because the system's picker draws checkmarks — no handles, no
numbers, no edit mode, on hardware as in the simulator — so an order carried
out of it is a side effect of the sequence somebody happened to tap in:
invisible while choosing, unexplained afterwards, and unfixable without
clearing every row and re-tapping. #172's actual complaint, a blank row landing
on the medium widget's cut, is answered by *which* rows alone. A real ordering
surface would be the in-app screen #188 names as its fallback, where the order
would be visible while being chosen.

The hard cut is unchanged and is not configurable: a medium widget shows five
rows and a person configuring six gets the first five. There is no per-family
row count stored anywhere — `WeekWidgetView` measures its own frame and
applies `WidgetMetrics.rowCapacity` to it, because a widget's point size
differs by phone. `largeRowCapacity` exists for the app's own use and is now
a narrower claim: it is where an *unconfigured* large widget stops, which is
what the grid's boundary hairline marks and where its rest-day cut ends. No
line in a scrolling list can stand for several differently-configured widgets
at once, and the app does not try.

**The Today widget is not in this build** (#209). It was small and medium —
one configurable habit's ring, and the first three per-day habits — and it went
with the kind it drew. Its kind strings, `GlowTodaySmall` and `GlowTodayMedium`,
are removed rather than renamed, so a placed Today widget leaves the Home Screen
with the extension that drew it. That is what pulling a feature costs, and it is
intended.

**The month, at small**: one weekly-cadence habit's calendar month
as marks on weekday columns — the same marks the week draws, decided by
`MonthGrid` asking `WeekGrid`, so the two surfaces cannot disagree about a
day. The 1st sits under the weekday it really falls on, so the first and last
rows are ragged. The habit is chosen per widget — the intent's `habit`
parameter, falling back to the first offered habit when unset, exactly as the
month kind's unconfigured widget always did. Today's dot is the same
`SlotToggle` through `MarkHabitIntent` — no other day is tappable, which is R2
in a third grid — and everything else opens This Week. Two readings held deliberately small
until decided otherwise (#41): an N×/week habit's empty days are sockets,
never crosses — the week grid's own rule, not a per-week verdict — and rest
days get no month-specific treatment beyond what `WeekGrid` already says
about them.

**The Widgets tab is where they are found from inside the app** (#210). It
shows every widget this app ships — the one kind at all three families —
drawn by `WeekWidgetView` and `MonthWidgetView` themselves rather
than illustrated, at the point size each family really gets, over the user's
own habits.

**The page is three named cards and the widgets themselves** (#237,
restructured by #312): **"Large Week Widget"**, **"Medium Week Widget"**,
**"Monthly View per Habit"**, in that order, largest first. No card carries an
explaining sentence under its heading — the gallery does, because there a
widget is an unfamiliar tile in a list, but here the widget itself is drawn
directly below over the person's own habits and says the same thing without
being read. The heading carries the size, so there is no caption beside a
preview, and the month's heading names the group — its previews are several
habits one widget could be showing. The one paragraph left is the long-press
instructions, the only thing on the page no preview can demonstrate. The
"This Week" / "This Month" section titles, the per-size captions and the
"Added" checkmarks all went with #312 — and with the checkmarks went the
page's `WidgetCenter` query, since nothing displayed its answer any more.

**The month is previewed against several habits, up to three.** It is the
widget that asks *which habit* as it is placed, so one example answers a
question the page is trying to show being asked; three of the person's own
habits, in their own order, show the choice instead. Three because the third
card is what makes it read as "one of yours" rather than as an arbitrary pair,
and because each preview is a full-size month render — a fresh install's eight
seeded habits would make that one section longer than the rest of the page. The
week is one preview per size at every size: it already shows every habit at
once, so "which one is this" is not a question it asks. Zero weekly habits is
still one card, drawing the widget's own empty state — what adding it today
would actually get you. The clause that kept Week-Small to a single card — it
had no per-habit axis to vary a second one over until #188 gave it one — went
with the family itself (PR #277).

**The Small previews sit two to a line, the way a Home Screen sits them**
(#274). Two Small widgets occupy the footprint of one Medium, so a column of
them was a picture of an arrangement nobody has; the gutter between them is
what is left of a Medium's width once two Smalls are in it. A trailing odd
card is a line of its own, at one widget's size, in the place the next one
would go. Medium and Large fill the width and are unaffected.

**Every preview sits on glass over black** (#312). Under Tinted or Clear the
system drops a widget's declared background, substitutes glass composited from
the wallpaper behind it, and renders the widget *accented*, where colour is
thrown away and only alpha survives. The previews show exactly that pairing:
the rendering mode is injected, so the marks take the same alpha-stored grey
by the same line of code they take on a Home Screen — the content is the real
thing, not a drawing of it. The panel behind is not: the wallpaper and the
system's compositing are unreachable from app code, so the page draws SwiftUI's
own glass over black — the Home Screen the app's aesthetic assumes. #273 put
an appearance picker over these previews and #312 removed it; the measurements
that shaped it are kept in decisions.md, because no API reports the device's
Home Screen appearance and the two glass appearances render identically here.

The previews are of *unconfigured* widgets, which is the same narrowing the
grid's boundary hairline took (#188). They draw the app's own list because
that is what a widget nobody has configured draws, and per-widget rows mean the
page cannot know what any particular placed widget shows — `WidgetCenter`
reports a kind and a family, never a configuration. A preview per placed widget
would be four previews of one widget, and a wrong one is worse than a generic
one.

**Nothing on that page places a widget, because no API can.** No public call
opens the widget gallery or adds anything to a Home Screen; `WidgetCenter`
invalidates, reloads and reports, and `promptsForUserConfiguration()` — the one
capability that reads like it might be it — is a modifier on a widget's own
configuration that asks for its *settings* after somebody has already added it
by hand. So the page states the long-press once, above the previews, and the
person performs it.

**The widget chooses the screen.** A widget's surface divides in two: the
marks act in place through their intents and open nothing, and everything
else opens the app on that widget's own screen — `glow://week`, mapped by
`DeepLink` in `Logic/`. `glow://today` was the other one and went with the
Today screen (#209); it now means nothing rather than landing somebody on
This Week uninvited. Every launch opens This Week, which is what a cold
launch already did.

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

**A widget that cannot read the store says so; it never says "No habits yet"**
(#282). Empty and unavailable are different facts and each widget draws them
apart: a store that was read and holds nothing gets the empty state's words,
and a container or fetch that failed gets a distinct "Data unavailable — Open
Glow" surface (`WidgetUnavailableView`), because a database failure drawn as
the deletion of every habit is a false claim about the record. The whole
widget already deep-links into the app, and a launch that hits the same
failure lands on the store-unavailable screen, which is the recovery surface.
The three outcomes travel typed (`StoreRead`) from the store boundary into
`WeekEntry`/`MonthEntry`, so no view can collapse them again; the widgets'
configuration pickers throw on a failed read rather than offering an empty
list, so the system shows its own retry. What the unavailable surface never
shows is why — no framework error text, no paths, no names.

## 10. Resolved questions

The spec's open questions and their answers are in
[docs/decisions.md](docs/decisions.md).
