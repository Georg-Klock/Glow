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
  degenerate one. A habit is counted across a week or within a day, never
  both; `slotCount` is nil for the per-day kind, so anything week-shaped has
  to say what it means when there is no week.
- `DeepLink` is the widget-to-screen mapping: each widget's inert surface
  carries one URL, and the app lands on that widget's own screen. Unknown
  URLs map to nil and change nothing.
- `MonthGrid.cells(for:today:)` is the month widget's grid: a weekly-cadence
  habit's calendar month as marks on weekday columns. It does not re-decide
  anything — a daily habit's weeks are handed to `WeekGrid.slots` and read
  off day by day, and whether today is open or undoable is the week row's
  own verdict, asked rather than derived — so a change to the week's rules
  reaches the month without a second edit.
- `DayRing.arcs(target:done:gap:)` is the Today ring: one arc per repetition
  as trim fractions of a circle, the first `done` of them quiet. The ring
  starts full and glowing and closes clockwise from the top — the inverse of
  the fitness rings it resembles, because here the glow is what is still open.
  `DayRing.countAfterTap(count:target:)` is the ring's one interaction: a tap
  is one more, and a full ring resets to zero, which is also the undo.

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
It returns a `ToggleOutcome` rather than a Bool, because a third thing can
happen: a write landing on the rest day is `.refused` — nothing logged, nothing
removed. The refusal lives here, on the one write path the app and the widget's
intent share, rather than in trust that no surface offered a button; the grid
withholding the rest-day tap is the same rule at the surface.

`recordTap(for:on:)` is the per-day counterpart: it asks `DayRing.countAfterTap`
what the tap means and translates the answer into rows — one more `Completion`,
or a cleared day when a full ring resets. The rule lives in `Logic/` and the
rows live here, so the app's ring and the widget's tap the same behaviour.

### Models

SwiftData, shaped for a CloudKit future even though v1 is local-only: every
property has a default, there are no unique constraints, and the relationship
is optional. CloudKit requires all three, and retrofitting them later means a
migration rather than a configuration change.

`Frequency` is stored as `isDaily` plus `timesPerWeek` rather than as an encoded
enum, so the column stays queryable and a schema change does not hinge on an
enum's `Codable` representation. The per-day kind adds `timesPerDay`, with zero
meaning "counted across a week" — a sentinel no real per-day habit can store,
because the initializer clamps into 1...12. `Habit.countedPerWeek` and
`Habit.countedPerDay` are the two fetch predicates, one definition each, so the
week surfaces and Today cannot drift in how they split the kinds.

### Views

Mostly layout. The one piece of real behaviour is `SlotView`'s completion
transition, which is documented in place and in [glow.md](glow.md).

`TodayView` shows the per-day habits as rings — the small and medium widget at
app size, per docs/vision.md — and nothing week-shaped. `DayRingView` draws the
arcs `DayRing` lays out, with the open arcs glowing as one layer: one HDR tile
and one halo pass, rather than a dozen separately composited lights. The tile is
shape-free and cached per intensity, so an arc is a mask like any other and
costs the cache nothing.

Width flows down rather than being measured per row: `WeeklyGridView` reads the
screen width once, builds a `RowGeometry`, and hands the same value to the
header and every row. Measuring per row would need a `GeometryReader` inside
each one, and since slot *height* is derived from track *width*, that is
circular. Passing one value down also guarantees the header and the rows divide
the screen identically, which is the one thing the whole screen is for.

`RowGeometry` is also where This Week becomes the widget: every measurement is
a `WidgetMetrics` number times one factor, the screen's width over the
widget's 338pt, so the screen is the large widget scaled up rather than a
second layout kept in step with it by hand. The deliberate departures are on
the type.

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

`GlowRenderTests` is a second test target: it renders the real `WeekWidgetView`
at the design frame's own 338 × 354 and, once a design export is committed
(`RenderTests/DesignReference/`), diffs the two and reports where they disagree
(#6). Its own target because `GlowTests` reaches the app module and the
widget's view is not in it — so it compiles the widget's sources directly, the
same sharing the widget target itself uses, hosted by the app so `Bundle.main`
carries the symbol catalogue. `Tools/test.sh` sums the counts across both
targets; taking the last summary line would silently shrink the number to
whichever target finished last.

CI runs the same script on pull requests and on merges to `main`.

## The App Group

The widget runs in its own process and cannot see the app's private container,
so the store lives in `group.com.georgklock.glow` and both open it there.
`StoreLocation` owns that decision and the one-time move of a pre-widget store,
copying the write-ahead log alongside the store because a copy without it loses
every write still sitting in the log.

If the group container is unavailable the app falls back to its own container
and keeps working; only the widget goes blank. That is deliberate: a missing
entitlement should not stop the app launching.

Getting this working took four separate fixes, each of which failed silently.
Recorded here because every one of them presents as "the widget shows no
habits".

**1. The entitlements file was empty.** xcodegen *generates* the file named by
`entitlements.path`, so declaring a path without `properties` overwrites a
hand-written file with an empty dict. An empty entitlements file requests
nothing, signs cleanly against any profile, and produces no warning anywhere.
The group is therefore declared in `project.yml` under
`entitlements.properties`, and both generated files are gitignored.

**2. Nothing had registered the App Group with Apple.** The group and two
explicit App IDs (`com.georgklock.glow`, `com.georgklock.glow.widget`) now exist
on the developer portal with App Groups enabled and the group assigned.

**3. Automatic signing could not mint profiles.** Xcode has no Apple ID in its
Accounts, so `-allowProvisioningUpdates` cannot talk to the portal. It never
said so: with a wildcard profile cached on disk it silently used that instead.
The error `No Accounts: Add a new account in Accounts settings` only appears
once no matching profile exists at all.

**4. Automatic signing preferred the wildcard.** Even with correct profiles
installed, it kept choosing the Xcode-managed `iOS Team Provisioning Profile: *`.
Both targets therefore use manual signing with an explicit
`PROVISIONING_PROFILE_SPECIFIER`.

The consequence: **device builds depend on two profiles existing on this
machine**, `Glow Up Development` and `Glow Up Widget Development`. If they are
lost, regenerate them on the developer portal (iOS App Development, the matching
App ID, the Apple Development certificate, both devices) and drop them into
`~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. Signing into Xcode
with the Apple ID would remove that dependency and let automatic signing work.

Verify the whole chain with `Tools/check-app-group.sh`, which reports which
profiles grant the group and whether the last device build actually carries it.

## TestFlight

`Tools/ship-testflight.sh` archives, signs for the App Store and uploads. It
does not use the manual development profiles above: distribution signing is
cloud-managed through an App Store Connect API key, which is what lets a build
ship without an Apple ID in Xcode. The key's `.p8` lives in
`~/.appstoreconnect/private_keys/`, and its identifiers in the gitignored
`Tools/local.env` (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `TEAM_ID`) — the script says
so and stops when either is missing.

The script regenerates the project before archiving, and that line is
load-bearing: everything it archives — the project, both entitlements files,
both Info.plists — is generated from `project.yml`, so archiving whatever is
on disk ships whatever state the disk was left in. One build went up with a
stale `Glow/Info.plist` and lost the compliance declaration that plist exists
to carry.

The build number is stamped from the UTC clock at upload (`YYYYMMDDHHmm`), so
every upload is unique without a commit per upload; `MARKETING_VERSION` stays
where `project.yml` puts it and stays Georg's call. The first upload verified
the App Groups entitlement survives distribution signing in both the app and
the widget — checked in the exported IPA, not assumed from the archive.

## The widgets

The week widget: small, medium and large, reading the same store through the
App Group, with today's slot as an `AppIntent` button. Past days are not
buttons, which is R2 holding in a second process.

It renders the same HDR tile as the app, via the same `GlowImageView`, with
`fillsWidth` set because the widget's slots are distributed by an HStack rather
than measured by `SlotLayout`.

The Today widget: small (one habit, chosen per widget through a configuration
intent) and medium (the first three per-day habits, static), drawing the same
`DayRingView` as the app, each ring a `TapHabitIntent` button. The
configuration intent, its entity and its query live in the shared sources
(`TodayWidgetConfig.swift`), not the widget target — the app exports AppIntents
metadata of its own, the system consolidates metadata under the app, and with
the intent defined only in the extension the stored habit choice never resolved
when the provider ran. The note on the type carries the symptom in full.

## What is deliberately absent

- No view models. The logic that would live in one is in `Logic/`, and the rest
  is `@Query`.
- No coordinator or router. There is one screen and three sheets.
- No dependency injection container. The two things needing injection, the
  calendar and the model context, are parameters with defaults.
- No networking. There is none.
