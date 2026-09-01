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
letter while any habit is still open, the name of a habit open today, its SF
Symbol when it has one, and the open mark. Emoji remain their own full-colour
content while the name beside them emits (#457). A completion is lit but does
not emit; it reads as an object catching light rather than as a source of it.
The sentence above is unchanged by this — every completion is still lit, and
absence is still dark — what the second tier adds is a *ceiling* a completion
does not reach.

That is not #75 reversing. #75 refused to paint a completion grey and still
does; a completion is bright on every surface. #75's reasoning was written when
there was one tier, so it is re-read rather than cited.

**A completed mark is lit, on every surface** (#344). A habit due N times a week
is drawn as N shapes dividing the week, and a shape whose rep happened is lit
like any other completion — §1 above has no exception in it. This reverses #47,
which had those shapes draw the same unlit line whether their share was achieved
or not, with a lit dot on the real weekday carrying *when*. What made that
premise false is #339: a mark now ends on its own day, so its left edge carries
when, and an unlit track with a lit dot inside it leaves the swallowed day
visible as a gap — the thing the mark model exists to remove. The cost is that a
mark reaching back over a blank day no longer says which of its columns the rep
landed on; that was weighed and taken. See docs/decisions.md.

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

  **One pool of 173 phrases, and one line per tap** (#420). Every pop draws
  from the same list, whether the tap was the first repetition of the week or
  the one that finished it. Each line is lowercase and at most fourteen
  characters, which is what the compact Island region carries without being
  scaled to fit (#310).

  This replaced two vocabularies — a flat acknowledgement for a repetition, a
  celebratory one for a goal met — and the argument for them: that sharing a
  list would make the goal indistinguishable from the twelfth glass of water.
  The register was gating *frequency* and picking *words* at once, and only
  the frequency half was doing that job. **Goals** still makes the goal the
  only thing spoken, and the six-word routine list was paying for the same
  claim a second time, at a width a person logging twice a day exhausted
  inside a week.

  **A tap never says two things.** The tap that met the goal used to say the
  routine line and then replace it with the celebratory one part-way through
  the two seconds — the only place in the app where one tap produced two pops.
  It says one line now. `PopPreferences.allows(justMetGoal:at:)` returns one
  verdict rather than a sequence, so there is nothing to play in order.

  **A correction says nothing.** Un-logging a day fires no pop. An acknowledgement for taking something
  back is the app congratulating somebody for an undo.

  **One pop at a time, whose words change** (#102). Two goals met inside the
  two seconds is not an edge case — the medium Today widget put three rings
  side by side so they could be tapped in a flurry, and the week widget puts a
  column of slots there now. A second goal updates the
  running activity rather than requesting another; the ending belongs to the
  most recent one, so nothing is cut short.

  **The Island acknowledges the request, not the eventual save** (#464). An
  eligible completion pop is decided from the bounded pre-write week snapshot
  and launched before `HabitStore.setCompletion`, alongside the widget mark's
  optimistic transition. **Never** stays silent; **Everything** allows a new
  requested completion; **Goals** allows one whose hypothetical row would
  reach the target. Undo and a requested completion the snapshot already holds
  stay silent. A later refusal or save failure may take the mark back after the
  words appeared; that rare mismatch is the accepted cost of not delaying the
  acknowledgement behind persistence.

  Existing-activity replacements are latest-wins even when ActivityKit returns
  updates out of order. A new replacement starts immediately rather than
  waiting in a queue. Every older delivery checks the latest generation after
  its asynchronous update returns and reapplies the newest content before it
  exits if it became stale. The two-second ending still belongs to the latest
  tap, so both the words and their full visible duration restart there.

  The production control hosted inside Glow's Widgets tab calls the same mark
  operation through an app binding adapter, with Island presentation disabled:
  the app is foreground, where the Live Activity is not visible. Installed
  widgets reach it through `MarkHabitIntent` with Island presentation enabled.
  This keeps the Island a Home Screen acknowledgement and leaves the existing
  in-app pop as the foreground presentation.

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

  **The Island fires from the home screen only, and the app draws its own**
  (#103, reversed in part by PR #275). The Island does not render a Live
  Activity while its own app is in the foreground, so a completion logged in
  the app would spend its two seconds on nobody. `GoalPopCentre` is therefore
  called from `MarkHabitIntent` and from nowhere else — it was two intents
  until #209 took the ring's away. #103's answer was that the app then says
  nothing, and that read as the app saying *less* the moment a person is
  looking at it: the app draws `InAppPop` instead, the Live Activity's own
  Lock Screen presentation, from the same pool under the same setting. The two
  surfaces cannot both fire for one tap — they are reached from different entry
  points, and the widget's button is not a foreground tap.

  The alternative was to rewrite §1 so that light may also mean *well done*.
  That was declined: it would put a second meaning on the one signal the app
  has. See docs/decisions.md.

## 4. Data model

```swift
enum Frequency { case daily, timesPerWeek(Int) }
// timesPerWeek: 1...6 selectable, 7 collapses to .daily
// timesPerDay(Int) was a third case; see feature/daily-habits-2.0 (#209)

struct Habit    { id, name, icon, frequency, accent, createdAt, targetAtCreation, sortOrder }
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
  spans — met, behind or finished, however late in the week it is — and a span
  whose rep happened is lit (#344).
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

**A span's own edge carries the when now, not a separate dot** (#344). A mark
anchors on the day it happened — reaching back over any blank day since the
previous mark, rather than filling the track left to right blind to the
calendar — so where a mark's boundary falls *is* the record of when. The two
jobs used to be one mark doing neither well: the row said how much was left and
nothing about when (#47); #344 folded when back into the mark itself instead of
drawing a second layer for it. See `docs/week-marks.md` §1 for the exact rule.

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
   every other state, a stored completion included. **Unreachable since #390** —
   nothing in the app sets a rest day; see "A rest day stops the week" below.

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

**A habit made part-way into the week is granted credit** (#343). It has not
failed the Monday it did not exist for, so it is given **the minimum number of
reps that avoids a ✕, and not one more**: `credit = max(0, target − capacity)`,
where capacity is the days from the creation day to the end of the week **plus
the days before it that already carry a completion** (#415). The minimum matters
— granting every pre-creation day would collapse the reps still owed into one
wide pill, which reads as slack the habit does not have. Credit marks are unlit:
they are arithmetic, not a claim that anything was done.

A day before creation that was logged is a day a rep landed on, not a day that
was forgiven, so it counts toward the target like a remaining day does — and
counting it is what keeps the row fitting. Over-granting puts an extra mark into
the columns the grant has already claimed, and since a mark's end clamps up as
well as down, the open mark was pushed off today: six a week made on Wednesday
with Monday and Tuesday back-filled drew its ring on Thursday. `DemoHistory`
writes exactly that week.

**The grant is frozen at creation and can only shrink.** `Habit.targetAtCreation`
stores the target the habit was made with, so an *upward* edit gets no amnesty —
5x → 7x keeps the two reps it was granted rather than earning four — while a
downward edit shrinks it, because otherwise the row would meet its goal off
credit nobody earned. A row that never recorded a target is granted nothing: an
unknown grant cannot be reconstructed, and claiming one would be the app
inventing forgiveness it has no record of (the same rule `createdDay` follows).

**A met goal keeps every completion on its day** (#342). It used to collapse to
one shape across all seven columns, which forgot every day it had just
recorded; now the last mark runs to the end and the earlier ones stay where the
reps happened. Completions past the target get no mark of their own and fall
inside the last one, so a 3x row logged four times looks exactly like a 3x row
logged three times — the record keeps the fourth, the row has nothing left to
say about it.

The rule used to be **inferred from the design rather than specified**; it is
specified now, in `docs/week-marks.md` §4.

**An achieved span is lit** (#344), drawing `donePast` — lit but not emitting,
which is the two-tier rule of §1: the glow stays reserved for what is still
actionable, and the open mark is what has it. A completion past the goal has no
mark of its own and falls inside the last one, which is lit anyway.

**The days are spoken as one fact, and the speaking outlived the drawing**
(#344). The lit dots went when the marks lit — the same light in the same
places, drawn twice — and the string did not, because it is the only way
VoiceOver reaches which days a weekly row carried. Both surfaces keep the
element and draw nothing in it. `WeekDots.spokenDays` names the weekdays
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

**"The whole app" includes the Widgets tab's previews** (#439). It did not: that
page established today from the clock directly, so with an override set the
placed widget honoured the chosen day and the preview of that same widget drew
the real one — on the one page whose claim is that it cannot drift from the Home
Screen. This paragraph was right and the code was wrong; the page now reads the
override like every other surface, and carries the banner because it does.

**Nothing in the app sets a rest day any more** (#390). Settings' toggle and
day picker are gone for MVP scope, and `WeekPreferences.retireRestDay()` clears
one an older build stored, so on a real install `restDay` is nil and every
sentence in this section describes a state the app cannot reach. The arithmetic
is left in place rather than deleted, and it is still tested — see #391 and
#392, where the feature comes back with weekday-specific scheduling. What
follows is what it does when a rest day is supplied.

**A rest day stops the week.** One optional weekday
(`WeekPreferences.restDay`), handed to the grids as a parameter rather than
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
the *shape*, before the glow is generated from it, so the tile is masked to the
shortened shape rather than to the full one.

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

**This Week creates and edits its habits through one editor.** Outside edit
mode it carries one trailing control: an ellipsis menu holding **New Habit**,
**Blank Row** and **Edit** (#320). The menu belongs to the current week only
(#207): paged back, the trailing slot holds **Today** instead, because
reordering, deleting and adding are properties of the list and mean nothing
more three weeks ago than they mean now. The editor opened on the adding
screen's *kind* while there were two of them (#209); there is one, so it opens
on the count and nothing else.

**Editing has a toolbar of its own** (#399). While the list is fanned open the
week pager and the week readout both leave — neither answers a question editing
asks, and the pager is the only control that could change the week, so hiding
it is also what makes "edit mode ends when you leave this week" a rule nothing
on screen can reach. What appears in their place is a **Done** checkmark,
immediately left of the ellipsis, carrying the same `checkmark` symbol the menu
item used to. The menu keeps New Habit and Blank Row and drops Edit for as long
as editing lasts, so Done is said once rather than twice. **Entering is still
two taps and leaving is now one**: #320 put both ends in the menu for symmetry
and named the cost, and this is that cost being paid back on the end that
needed it — a mode whose exit is behind a menu reads as a mode you are stuck
in.

**A name that will not fit is shown not fitting in the field itself** (#405,
#456). The field has no character limit and imposes none — what is stored is
exactly what was typed. Truncation is a width, not a count, so how many letters
fit depends on which letters they are and no counter can state a number. The
field therefore uses the system's body-sized type and a width enlarged from the
compact row by the same factor, then tail-truncates while it is being edited.
The larger input remains an honest preview because its width-to-type ratio is
unchanged. Once the name overruns, a fixed-height amber line immediately above
it reads *Short titles work better. Long titles will be cut.* The line reserves
its height while empty, so the field and frequency control do not move when it
appears. **One field is honest about both surfaces**, because they are one row
at two sizes: `RowGeometry` is the large widget's geometry times a single
factor, applied to the text size as well as to the label column, so a name
breaks at the same character on This Week as it does in the widget.

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

**Edit mode ends when you leave this week** (#207). The controls that enter and
leave it are on the current week only, so paging back while editing would leave
the list fanned open with no Done on screen. The mode goes with the week rather
than the exit going missing. Since #399 the pager is hidden while editing, so
nothing on screen takes that path any more; the rule stays because it is what
makes the pager's absence a tidiness rather than the only thing standing
between edit mode and a dead end.

A span row resolves the tap to **the column under the finger** rather than to
the span's nominal day, so a habit due N times a week records the weekday it
really happened on — the same day the month grid and the row's own dots already
draw it on. Touching the rest day's column inside a span does nothing: the
column is drawn as a hole, and pressing a hole is pressing nothing.

**The grid sits on one panel, and the panel does not move** (#398). The grey
material is a single shape behind the whole list, as tall as the habits on it
and no taller than the screen, with all four corners rounded. It was N+1 row
backgrounds that abutted — one per row plus the header's — which read as a card
and behaved like N+1 rectangles: a swiped row took its own background away with
it and opened its Edit and Delete buttons on bare black. Now the row's content
is what slides and the buttons sit on the material. The consequence, stated
rather than left to be found: on a list longer than the screen the panel fills
the screen, so its bottom corner stops travelling with the last row.

**The weekday header scrolls out of view, where it used to pin** (#398). It was
a `Section` header, and a `Section` header in a `.plain` list is sticky: it sat
at the top of the list while the habits scrolled underneath it. It is an
ordinary row now, so it cannot pin and goes with everything else — which is
what the widget does, since a widget has nothing to scroll.

**A removed row collapses to nothing and the rows below close the gap**
(#398). `MotionPolicy` decides whether it happens, exactly as it decides
whether a completion closes: the second kind of motion the app has, and under
Reduce Motion the row is simply gone with no frame in between. Both routes to a
removal — the swipe's Delete and edit mode's minus — animate the same way,
because a rule that told them apart would be animating the gesture rather than
the change.

**Edit mode gives the week's width back** (#164). `List` draws a delete circle
at the leading edge of every row and a reorder handle at the trailing one, and
while it does, everything weekday-shaped leaves: each row's track, the rest-day
cut positioned from the same geometry, and the header's letters, all on one
0.15s fade. The icon and name recentre between the system's two controls — not
in the vacated track, which would leave them a third of the way across. A blank
row has nothing to fade and nothing to centre; it shows the two controls and the
gap it stands for. Reduce Motion snaps the change rather than shortening it.

**And the name is measured against the row it is now in** (#440). The width the
week gives back is only given back if the name is allowed to use it: the cap on
a name is the label column less the icon and the gap before the name, and edit
mode draws no label column, so a name went on being cut where the track would
have begun with half the row empty either side — "Touch Grass" as "Touch Gr…" beside eight
columns of nothing. While editing the cap is the row's own width instead, less
the gaps either side of the label, less the icon column, and less the part of
the row the system's two controls cover — they are laid out against the `List`'s
bounds, so they stand over the row rather than beside it, and a name granted the
whole width would end underneath them. On a 402pt screen that is 256.3pt of name
against 69.6pt outside edit mode. It is still a truncation and it is still at
the tail; what moved is where the row says it runs out.

**The edit controls stand off the panel's edge, and the panel does not move to
let them** (#400). The delete circle and the reorder handle are the system's,
laid out against the `List`'s own bounds — they ignore `listRowInsets`, so the
insets that place the grid on the panel never reached them. Measured on an
iPhone 17 Pro against a 402pt screen, both overhung the panel and were drawn
partly on the black outside it: the circle at 17.0-38.7pt against a panel
starting at 20.0, the handle at 363.0-384.0 against one ending at 381.7. The
room comes out of the `List` instead — it is narrowed by 10pt on each side and
the rows are inset by 10pt less, so every absolute position on the screen is
what it was and only the system's two controls move. They now stand 7.0pt and
7.3pt inside the panel's edges. Nothing about the panel changed: its shape, its
corners and its 20pt margin are untouched, which is the half of the ask that was
not negotiable.

**Every name reads plain white while editing** (#206). Outside edit mode a name
is grey until its habit is due today and lit while it is — §1's rule carried
through to type. Editing is the one moment that reading stops being the useful
one: nobody reordering a list is asking what they are due for, and half the
names sitting at the unlit grey is half the list hard to read at exactly the
wrong time. So the crossfade steps aside for a flat `GlowPalette.color` — the
header's own white, not the glow, because the glow is the same claim an open
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
docs/glow.md — and the mechanism the measurement confirms is unchanged. A lit
mark used to spread an SDR halo onto the ground around itself, with a **No
halo** switch beside the slider (#313); both the halo and the switch are gone
(#394), and a mark is now lit exactly as far as its own silhouette reaches. The
slider is stored in the App Group, so the widgets obey it too.
Settings places the live EDR grant and the display configuration's potential
ceiling beside that ask — `3.2× right now · 8.0× maximum`, for example — and
refreshes the live value while the screen is visible. The potential ceiling is
never labelled as the current grant.
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

The hard cut is unchanged and is not configurable: a medium widget shows four
rows and a person configuring five gets the first four. (Five until #331 took
the slot from 17.455 to 24; the sentence here said five until #410 read it
against the code.) There is no per-family row count stored anywhere —
`WeekWidgetView` measures its own frame and applies `WidgetMetrics.rowLayout`
to it, because a widget's point size differs by phone. `largeRowCapacity`
exists for the app's own use and is now a narrower claim: it is where an
*unconfigured* large widget stops, which is what the grid's boundary hairline
marks and where its rest-day cut ends. No line in a scrolling list can stand
for several differently-configured widgets at once, and the app does not try.

**The design specifies a row count; the phone supplies a frame** (#410). A slot
is a row's height as well as a daily mark's width, so until #410 a row block's
height grew with the frame's *width* while the room for it grew with the frame's
*height*. The large family's ten rows fill the design frame — 338 × 354 — with
zero slack, and every phone measured is proportionally wider than it: 344.67 ×
360 on an iPhone 15 Pro, 349.67 × 365 on a 17 Pro, 342 × 358 on a 17e, read out
of WidgetKit's own snapshot-cache archive path. So ten rows overran the height by
0.44 to 1.97 points out of ~320, the capacity's floor division took **nine**, and
one habit was silently missing from every large widget on every device.

The slot now takes the smaller of the track's answer and the largest slot at
which the design's rows still fill the height, so ten rows are drawn on any of
those frames and the bottom margin is the design's 14 exactly. What it costs is
the right margin: the marks stay round and bring their column rhythm down with
them, so 0.4 to 1.8 points of track are left unused at the trailing edge and the
right margin is no longer exactly 14. Of the three things that cannot all hold
on a frame whose aspect differs from the design's — round marks, a track filled
exactly, a height filled exactly — the one given up is the one the design file
does not specify.

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

**The month is shown once for every tracked habit** (#465). Spacer rows are not
habits and get no month; every habit `MonthStore.offered` returns gets one card,
in the person's current order, with duplicate ids collapsed. This is a control
surface rather than a demonstration sample, so there is no three-card cap. The
week is still one preview per wide size because it already shows the whole
list. Zero weekly habits is still one card, drawing the widget's own empty
state — what adding it today would actually get you.

**The production controls stay live inside the Widgets tab** (#465). Today's
actionable mark in either week card and every month card is the same
`SlotToggle` the Home Screen widget uses. WidgetKit supplies its AppIntent
adapter; the ordinary app host supplies a binding adapter whose local `isOn`
changes before persistence begins (#477). Both adapters ask one idempotent
`MarkHabitOperation` for an absolute done or undone state, then reconcile to
the shared store. Past and future marks remain display-only. The controls keep
their production VoiceOver labels and hints; the page does not hide a widget
view as one picture. A finished operation signals the live Widgets and This
Week tabs to re-read their bounded snapshots, while the usual widget
invalidation updates installed widgets.

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

**The system's own widget gallery draws a sample, and it is the one fixture in
the app** (#365). That gallery is not this page. Its picture is taken by
WidgetKit calling the provider once, with `context.isPreview` true, at the
moment the extension is installed — and then cached: re-opening the sheet
redraws the same bitmap without asking again. So the preview cannot be a store
read. The commonest moment for that one call is before the app has ever been
launched, when there is no container to open, and the read that came back
`unavailable` froze "Data unavailable — Open Glow" into all three pages for the
life of the install; a real week read later would freeze just as hard, and be
wrong on every day but the one it was taken on. `WidgetPreviewSample` is what
is drawn instead: `DefaultHabits.all`, the set the empty state offers, over
`SeededHistory`, the invented past the demo toggle uses — with today left open,
because that is the one thing the widget is for. A placed widget is unaffected
and still says what the store says.

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
