# Architecture

Current technical truth. Where this and the code disagree, the code wins and
this file is a bug.

## The shape

```
Views ──────────► Logic ◄────────── Tests
  │                 ▲
  │                 │
  └──► Store ──► Models
```

`Logic/` is the centre and depends on nothing. `Views/` and `Store/` both point
at it. Tests reach it directly.

### Logic

Pure value types and free functions. No SwiftData, no SwiftUI, no `Date()`.

- `WeekCalendar` answers every date question. One definition of "what day is
  it" rather than five.
- `WeekGrid.slots(for:in:today:)` turns a habit plus a week into the row of
  slots to draw. This is the entire interaction model of the app, and it is one
  function.
- `SlotLayout` is the row geometry, as a single formula that a 7-circle row and
  an N-pill row both go through.
- `Frequency` normalizes cadence at construction, so no caller can build a
  degenerate one.

Every function takes its `Calendar` and its `today` as parameters. Nothing here
reads the clock, which is what lets the tests assert against a fixed Tuesday in
August rather than against whenever they happen to run.

### The snapshot boundary

`WeekGrid` operates on `HabitSnapshot`, a plain struct, not on the SwiftData
`Habit`. A view calls `habit.snapshot()` and passes the result down.

This costs one small allocation per row per redraw and buys three things: the
logic is testable without a store, the logic is `Sendable`, and a view cannot
accidentally mutate a model while drawing it.

### Slots carry their own action

`Slot.actionDay` is the day a tap would toggle, or `nil` if the slot is not
tappable. The view taps what it is handed.

This is deliberate. The alternative is for the view to work out which day a
given column represents, which means the day-pinning rules for daily rows and
the not-day-pinned rules for frequency rows both end up duplicated in the view
layer, where they cannot be tested. Instead, "is this tappable" and "what does
it do" are decided in one place, and R1 and R2 hold by construction.

### Store

`HabitStore` wraps `ModelContext` and owns every write. Reads do not go through
it: the grid uses `@Query`, so SwiftData drives updates.

`toggleCompletion(for:on:)` normalizes the day itself, which is what makes R3
and R4 hold no matter who calls it. Tapping twice quickly cannot create a
duplicate, because the second call finds the first completion and removes it.

### Models

SwiftData, shaped for a CloudKit future even though v1 is local-only: every
property has a default, there are no unique constraints, and the relationship
is optional. CloudKit requires all three, and retrofitting them later means a
migration rather than a configuration change.

`Frequency` is stored as `isDaily` plus `timesPerWeek` rather than as an encoded
enum, so the column stays queryable and a schema change does not hinge on an
enum's `Codable` representation.

### Views

Mostly layout. The one piece of real behaviour is `SlotView`'s completion
transition, which is documented in place and in [glow.md](glow.md).

Width flows down rather than being measured per row: `WeeklyGridView` reads the
screen width once, builds a `RowGeometry`, and hands the same value to the
header and every row. Measuring per row would need a `GeometryReader` inside
each one, and since slot *height* is derived from track *width*, that is
circular. Passing one value down also guarantees the header and the rows divide
the screen identically, which is the one thing the whole screen is for.

`RowGeometry` is where the label column's response to Dynamic Type lives. It
scales with the user's text size and is then clamped to 42% of the screen, so a
large accessibility size cannot shrink the track until a week stops looking like
one. The weekday header's own numerals stay fixed, because they sit inside
columns that are one slot wide and have nowhere to grow into.

## Day rollover

The open slot is defined as "today", so the screen has to notice when today
changes. Two paths, and both are needed:

- `NSCalendarDayChanged` covers the app being open across midnight.
- `scenePhase == .active` covers it being resumed the next morning without ever
  having been killed.

## Testing

`Tools/test.sh` is the test command. Use it rather than a hand-typed
`xcodebuild test`: it asserts a **non-zero** test count, so a scheme that builds
no test target fails instead of exiting 0 and looking like a pass. It also
picks whichever iPhone simulator the machine actually has, so it behaves the
same locally and on a runner with a different Xcode.

Tests exercise the real app types via `@testable import Glow`. Never
re-implement app logic in a test file: a mirror copy passes forever while the
app regresses.

`WeekGridTests` includes an exhaustive pass: for each cadence, all 128 possible
completion histories of a week, asserting R1 and R2 hold for every one. That is
cheap here because the logic is pure, and it is the reason those invariants can
be stated as facts rather than as intentions.

CI runs the same script on pull requests and on merges to `main`.

## What is deliberately absent

- No view models. The logic that would live in one is in `Logic/`, and the rest
  is `@Query`.
- No coordinator or router. There is one screen and three sheets.
- No dependency injection container. The two things needing injection, the
  calendar and the model context, are parameters with defaults.
- No networking. There is none.
