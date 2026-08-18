# Glow, product spec (v1)

Product truth. Where this and the code disagree, one of them is a bug; say
which in the same session you find it.

## 1. Concept

A habit tracker whose weekly overview is the whole app: a grid of habits by
day, filled when done.

The slot for today, while still incomplete, physically glows on HDR-capable
screens, using the same gain-map technique that makes HDR photos look brighter
than white in Photos. The glow is an "unfinished, still actionable today"
signal, not a reward for completion. It disappears when you complete the habit
(after a beat) or when the day ends.

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
- **No home screen widget.** WidgetKit renders snapshots in a separate process
  and does not carry the gain-map pipeline the way the in-app view does, so the
  real glow only exists inside the app. A future widget would mirror the grid
  in flat colour rather than attempt the glow.
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
- **R8.** Without EDR headroom the app renders flat colour, never a broken or
  blank slot.

R1, R2, R5 and R7 are asserted in `Tests/WeekGridTests.swift`, including an
exhaustive pass over all 128 possible completion histories of a week. R3 and R4
are asserted in `Tests/PersistenceTests.swift`, R6 in `Tests/SlotLayoutTests.swift`,
and R8 is the SDR-fallback test in `Tests/GlowRendererTests.swift`.

## 6. Layout

Each habit is one row: icon and name on the left, a fixed-width status track on
the right.

- **Daily:** 7 equal circles, Monday to Sunday, day-pinned.
- **N per week:** N equal pills, the same height as a daily circle, filling the
  same total track width.

Given track width `W` and inter-item margin `G`:

```
dailyCircleWidth = (W - 6 * G) / 7
pillWidth(N)     = (W - (N - 1) * G) / N
```

Pills are not pinned to weekdays. They fill left to right in the order
completions are logged, independent of which weekday each fell on.

## 7. Slot states

Every slot is in exactly one of three states.

1. **Inactive.** Not completed and not actionable today. Flat grey, no glow.
   Also the resting look of unfilled pills.
2. **Open.** Today's slot, not yet completed. A dim outlined shape under a
   bright HDR glow. The only steadily glowing state.
3. **Filled.** Completed. Solid colour, no glow once the animation settles.

**Completion transition.** On tap the slot holds the glow for ~200ms, then the
solid filled colour rises over it across ~750ms, leaving a plain filled shape.

Implemented as two layers rather than an animated HDR encoding, but note the
direction: the solid SDR shape fades **in** over a glow that never changes,
rather than the glow fading out. Animating opacity on the HDR layer invites the
compositor to flatten it into an SDR buffer, and a glow that dies the instant
it is touched is the hardest possible bug to diagnose. The two look identical.

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

Each was verified in the simulator and is held by a test. The one thing no test
covers is whether the glow is *visibly* brighter on a real screen, which is
Phase 0's outstanding item.

## 9. Resolved questions

The spec's open questions and their answers are in
[docs/decisions.md](docs/decisions.md).
