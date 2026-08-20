# Glow Up Habit Tracker, product spec (v1)

Product truth. Where this and the code disagree, one of them is a bug; say
which in the same session you find it.

## 1. Concept

A habit tracker whose weekly overview is the whole app: a grid of habits by
day, filled when done.

Today's column physically glows on HDR-capable screens: it is drawn from an
image encoded in a colour space with real headroom above SDR white, which is
what makes HDR photos look brighter than white in Photos.

The glow marks **today**, and nothing else in the week has headroom. Within
today, an incomplete habit is louder than a completed one — the signal is
"still actionable", not a reward — but a completion made today stays lit until
the day ends, because it is still today's news. Everything outside today is
flat, whether it went well or not.

## 2. Goals

- One weekly-grid screen is enough to see every habit's status for the current
  week. No drilling into detail screens for the core loop.
- Logging a habit is one tap from the weekly grid.
- The glow renders on EDR-capable devices and degrades to plain colour where it
  cannot, with no broken state either way.
- Two cadences only: daily, and N-times-per-week with no day pinning.

## 3. Non-goals (v1)

- **No sync.** Local SwiftData only. Sync stays a clean follow-up as long as
  the model is normalized now, which is why it is.
- **No fixed-weekday schedules.** "Every Mon/Wed/Fri" is out of scope.
  Frequency habits are pure count-based; any day counts.
- **No multiple completions per day.** A habit is done or not done for a day.
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
enum Frequency { case daily, timesPerWeek(Int) }   // 2...6 selectable

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
- **R3.** A day holds zero or one completion per habit. Never two.
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

Every slot is in exactly one of four states.

1. **Inactive.** A day still to come.
2. **Missed.** A past day that went unlogged. Daily habits only — for a habit
   due a number of times a week, an empty Monday is not a failure on Tuesday,
   because the week is still winnable.
3. **Open.** Today's slot, not yet completed. The only glowing state.
4. **Filled.** Completed.

A completion made today and one made on Monday are the same state and are not
drawn the same way, so the states above map to five *marks*: today's completion
is distinguished from the rest of the week's. That mapping lives in
`Slot.mark` and is tested there.

**What any of this looks like is deliberately not written down.** The visual
design is being worked on directly and prose here would only go stale between
one experiment and the next; the file above is the truth. What is fixed is the
hierarchy, and only because it is the product rather than a style: today is the
only lit column, and emphasis tracks "needs you now" rather than "went well".

**Which slot is open, for a frequency habit.** Count this week's completions.
If `count < N` and today is not already logged, pill index `count` is open.
Otherwise no slot is open: everything filled stays filled, unfilled pills stay
inactive.

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

## 9. The widget

One widget, three families, reading the same store through an App Group.
Today's slot is a button backed by an `AppIntent`, so a habit can be logged from
the home screen without launching the app. Past days are not buttons, which is
R2 holding in a second process.

The widget glows but does not breathe. The pulse was built, measured working
(WidgetKit renders sub-minute entries, contrary to its reputation), and removed:
it costs the day's entire refresh allowance, and a stale widget is worse than a
still one. See docs/glow.md.

The store therefore lives in the App Group container rather than the app's
private one, and `StoreLocation` migrates a pre-widget store into it on first
launch. Without the App Group entitlement the app falls back to its own
container and keeps working; only the widget goes blank, which is a better
failure than refusing to launch.

## 10. Resolved questions

The spec's open questions and their answers are in
[docs/decisions.md](docs/decisions.md).
