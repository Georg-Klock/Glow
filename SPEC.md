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
- ~~**The home screen widget does not glow.**~~ **It does.** This was written as
  a non-goal on the reasoning that WidgetKit renders in a separate process and
  archives the result, so HDR could not survive. That was never measured, and it
  is wrong: running the real Rec. 2100 PQ tile in the widget glows on an
  iPhone 14 Pro. The widget now uses the same renderer as the app.
- **No streaks, badges, or celebratory flourishes** beyond the completion
  transition itself. These were explored as candidate glow moments and cut, to
  keep the interaction model at one rule rather than three.

## 4. Data model

```swift
enum Frequency { case daily, timesPerWeek(Int), timesPerDay(Int) }
// timesPerWeek: 1...6 selectable, 7 collapses to .daily
// timesPerDay: 1...12, one ring arc per repetition

struct Habit    { id, name, icon, frequency, accent, createdAt, sortOrder }
struct Completion { id, habitId, day }             // day, not a timestamp
```

`Completion.day` is normalized to midnight in the user's calendar. Storing an
instant instead would make two completions on the same day compare unequal,
which is the bug the normalization exists to prevent.

**Week boundary.** Weeks start Monday, matching the M T W T F S S header. All
"this week" queries filter into `[startOfWeek(Monday), +7 days)` using the
user's calendar, with `firstWeekday` forced to Monday. Locale would otherwise
decide, and in the US that means Sunday, silently shifting every column.

## 5. Invariants

A build that violates one of these is broken regardless of what else works.

- **R1.** At most one slot per habit is open at a time, and only ever for the
  current day.
- **R2.** Only today's slot responds to taps. Past days are never editable.
- **R3.** For a weekly-cadence habit, a day holds zero or one completion.
  Never two. A per-day habit stores one completion row per repetition, so a
  day holds up to its target.
- **R4.** `Completion.day` is always midnight in the user's calendar.
- **R5.** A daily row draws exactly 7 slots; an N-times row draws exactly N.
- **R6.** Every row spans the same track width, whatever its slot count.
- **R7.** Weeks reset clean. A frequency habit's unmet goal does not carry over.
- **R8.** The glow is encoded in a colour space with headroom above SDR white.
  Without EDR the app renders flat colour, never a broken or blank slot.

R1, R2, R5 and R7 are asserted in `Tests/WeekGridTests.swift`, including an
exhaustive pass over all 128 possible completion histories of a week. R3 and R4
are asserted in `Tests/PersistenceTests.swift`, R6 in `Tests/SlotLayoutTests.swift`,
and R8 in `Tests/GlowRendererTests.swift`, which asserts the encoded colour
space rather than trusting it.

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

Pills are not pinned to weekdays. They fill left to right in the order
completions are logged, independent of which weekday each fell on.

## 7. Slot states

Every slot is in exactly one of five states.

1. **Inactive.** A day still to come.
2. **Missed.** A past day that went unlogged. Daily habits only — for a habit
   due a number of times a week, an empty Monday is not a failure on Tuesday,
   because the week is still winnable.
3. **Open.** Today's slot, not yet completed. The only glowing state.
4. **Filled.** Completed.
5. **Rest.** The rest day: a day nothing can happen on, which is not the same
   as a day that has not happened yet. It draws nothing at all. Rest wins over
   every other state, a stored completion included.

The states map to *marks* via `Slot.mark`, which is where the rendering
distinctions live and where they are tested.

A habit due a number of times a week is not day-pinned, so it is not drawn as
seven columns at all: `WeekSpans` divides the week into N shapes that stretch
across it, with the open one always containing today. **That rule is inferred
from the design rather than specified** — see the note on the type.

**What any of this looks like is deliberately not written down.** The visual
design is being worked on directly and prose here would only go stale between
one experiment and the next; the code is the truth. What is fixed is the
hierarchy in §1, and only because it is the product rather than a style.

**Which slot is open, for a frequency habit.** Count this week's completions.
If `count < N` and today is not already logged, pill index `count` is open.
Otherwise no slot is open: everything filled stays filled, unfilled pills stay
inactive.

**A rest day stops the week.** One optional weekday, set in Settings
(`WeekPreferences.restDay`), is true rest: its slot is never open, never
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
ring of arcs, one per repetition — see `DayRing` and docs/vision.md. The ring
starts full and glowing and each completion quiets one arc, clockwise from the
top, so the glow is always exactly what is left to do. At a target of 1 the
ring is a single unbroken circle. At the goal the ring is quiet but present,
in the same grey as a habit already handled.

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

**"Daily" means two different things, and only one of them is on screen.** The
editor's `Daily` segment means *counted within a day* — a ring on Today, N
repetitions that reset at midnight. The model's `Frequency.daily` means a
seven-times-a-week cadence, which is a *weekly* habit and sits under `Weekly`;
it is why "7x per week" is the wording for the everyday case rather than a
separate mode. The label is what the person reads; the enum keeps its name
because `Habit.countedPerDay` and `countedPerWeek` are built on it.

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
- [x] Past days are never tappable.
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
the app. Past days are not buttons, which is R2 holding in a second process.
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
private one, and `StoreLocation` migrates a pre-widget store into it on first
launch. Without the App Group entitlement the app falls back to its own
container and keeps working; only the widget goes blank, which is a better
failure than refusing to launch.

## 10. Resolved questions

The spec's open questions and their answers are in
[docs/decisions.md](docs/decisions.md).
