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
- `WeekReach` is how far back the week view may be paged: two week starts,
  derived from where the record begins and capped at twelve weeks. Separate
  from `SlotEditing` on purpose — one says which weeks there are to visit, the
  other says what a tap may do on the week you are on, and neither needs to
  know the other's answer.
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
- `SlotVoice` and `HistoryVoice` are what the marks say out loud. A day-pinned
  column names its own date, because the header that carries the dates on
  screen is a table when it is read aloud and stays hidden; a month or a year
  of columns is counted into one sentence instead. Both are pure, so the app
  and the widget cannot disagree about a word and the strings are asserted
  without a renderer.
- `YearHistory.fill(for:habits:today:)` is how a day of the long view went —
  full, partial, empty or still to come. It is the year grid's own rule, out of
  the view so that the sentence `HistoryVoice` speaks counts what the grid
  draws rather than counting it a second way.
- `MotionPolicy` decides whether a change moves. One completion is drawn four
  ways — a ring closing, a bar closing, a label dimming, a line sweeping — and
  Reduce Motion has to reach all four; a predicate left in a view is one no
  test can reach.
- `DayRing.arcs(target:done:gap:)` is the Today ring: one arc per repetition
  as trim fractions of a circle, the first `done` of them quiet. The ring
  starts full and glowing and closes clockwise from the top — the inverse of
  the fitness rings it resembles, because here the glow is what is still open.
  `DayRing.countAfterTap(count:target:)` is the ring's one interaction: a tap
  is one more, and a full ring resets to zero, which is also the undo.

Every function takes its `Calendar` and its `today` as parameters. Nothing here
reads the clock, which is what lets the tests assert against a fixed Tuesday in
August rather than against whenever they happen to run.

**The rest day arrives the same way** (#181). `WeekPreferences` is where the
stored value lives; nothing else in here reads it. `WeekGrid`, `WeekSpans`,
`WeekDots`, `MonthGrid`, `SeededHistory`, `YearHistory` and `SlotEditing` all
take `restDay: Int?` — the weekday nothing is expected on, or nil for none — and
the boundaries read it once: a view through `@AppStorage`, so SwiftUI can see
the dependency; a widget once per render, because it has no live hierarchy to
observe with; `HabitStore` and `DemoHistory` at construction, beside their
calendar. `TestIsolationTests` scans this directory for the read, because the
property is the absence of a call and no runtime assertion can watch an absence.

### The snapshot boundary

`WeekGrid` operates on `HabitSnapshot`, a plain struct, not on the SwiftData
`Habit`. A view calls `habit.snapshot()` and passes the result down.

`snapshot(calendar:)` takes the calendar the days should be placed on, and
defaults to `WeekCalendar.calendar` — the same one `WeekCalendar.week` builds
from, which is what keeps the two comparable. A test that pins a calendar has to
pin it here too; passing one side a fixed calendar and letting the other read
the machine's is how a suite ends up asserting something about the runner.

This costs one small allocation per row per redraw and buys three things: the
logic is testable without a store, the logic is `Sendable`, and a view cannot
accidentally mutate a model while drawing it.

**A surface that draws a bounded stretch of time reads only that stretch**
(#135). `Habit.snapshots(of:within:calendar:)` takes the days the surface
actually draws — `week.dayIDs()`, `MonthGrid.dayRange(containing:)`, the year's
first and last column — and pushes the bound into SQLite on `Completion.dayKey`.
`habit.snapshot()` with no range still means the whole history and is what the
export calls.

The snapshot it hands back therefore holds only those days, which is the one
thing to know before passing one on. Everything week-shaped asks only about days
inside the week it was given, so a week's worth is all a week's row needs;
`Tests/HistoryProjectionTests.swift` asserts that against `WeekGrid`,
`WeekSpans`, `WeekDots`, `GoalMet`, `MonthGrid` and `YearHistory` rather than
against a reading of them.

### Slots carry their own action

`Slot.actionDay` is the day a tap would toggle, or `nil` if the slot is not
tappable. The view taps what it is handed.

This is deliberate. The alternative is for the view to work out which day a
given column represents, which means the day-pinning rules for daily rows and
the not-day-pinned rules for frequency rows both end up duplicated in the view
layer, where they cannot be tested. Instead, "is this tappable" and "what does
it do" are decided in one place, and R1 and R2 hold by construction.

**Which days a surface may write is a parameter, not a fork** (#116).
`SlotEditing` is `.todayOnly` or `.week(allowingFuture:)`, and `WeekGrid.slots`
and `WeekSpans.spans` both require one — no default, so a new call site has to
say which surface it is rather than inherit the permissive answer. The week view
passes `.week`, everything else passes `.todayOnly`, and `SlotEditing.day(atColumn:in:today:)`
is the single function that answers "may this column be written", asked by the
grid, by the span pass, and again by the view for the column under a finger.
`WeekSpans` runs the surface's answer as a pass over the finished row, so the
division of the week — which spans exist, how wide, which one is open — is
identical on both surfaces and only the actions differ.

**Widening from one week to several changed neither** (#117). `SlotEditing` is
about the surface, not about which week is on screen, so a week entirely in the
past asks the same question of each of its columns and gets seven yeses; the
week view holds the visible week's start as state and `WeekReach` bounds it.
Nothing was added to `HabitStore`: a day three weeks ago is behind *now* exactly
as Monday is, so the pager reaches no write the store did not already accept.
The store's refusals exist for a surface that outlives the setting it was drawn
under, which is a second process's problem, and the pager runs in one.

A span covers several columns, so the week view resolves a touch to a weekday
with `SlotLayout.column(atX:trackWidth:)`, the inverse of `columnCentre`. The
arithmetic lives beside the forward direction and is tested against it; the view
adds the span's own origin and asks `SlotEditing` what that column allows.

### Store

`HabitStore` wraps `ModelContext` and owns every write. Reads do not go through
it: the grid uses `@Query`, so SwiftData drives updates.

`toggleCompletion(for:on:allowingFuture:)` resolves the `DayID` itself, which is
what makes R3 and R4 hold no matter who calls it. It refuses a rest day, a blank
row, a habit of the wrong cadence, and — unless the caller asks otherwise — a day
that has not happened yet. `allowingFuture` defaults to false, so the widget's
intents get the strict answer without naming it and only the week view, with demo
history in, opts out. Tapping twice quickly cannot create a duplicate, because
the second call finds the first completion and removes it — and it finds it by
*fetching* the habit's rows for that day rather than reading the cached
relationship array, so a row the widget's process wrote is not missed and a row
it deleted is not touched. Every row on the day comes off, not the first one
found: a store written before #130 can hold two rows for one civil day, and
un-marking a day has to mean the day is not marked.
It returns a `ToggleOutcome` rather than a Bool, because a third thing can
happen: a write landing on the rest day is `.refused` — nothing logged, nothing
removed. The refusal lives here, on the one write path the app and the widget's
intent share, rather than in trust that no surface offered a button; the grid
withholding the rest-day tap is the same rule at the surface.

Which day that is arrives at `init`, beside the calendar, and defaults to
`WeekPreferences.restDay` (#181). The default is the point rather than a
convenience: the refusal exists because a surface can outlive the setting it was
rendered under, so a rest day supplied by that stale surface would make the
guard agree with it. Every caller builds a store per operation — the week view's
`store` is a computed property, and both intents construct one — so this is one
read per write.

`recordTap(for:on:)` is the per-day counterpart: it asks `DayRing.countAfterTap`
what the tap means and translates the answer into rows — one more `Completion`,
or a cleared day when a full ring resets. The rule lives in `Logic/` and the
rows live here, so the app's ring and the widget's tap the same behaviour.

Every write ends in a private `commit()`: save, and then invalidate the widget
timelines. A save that throws rolls back, so a failed write leaves the store as
it was rather than leaving its changes pending for the next unrelated save to
commit (#140). `addAll(_:now:)` is the batch door — a whole list inserted and
saved once, which is how the default seed arrives.

`HabitSeeder` inserts through it and writes `didSeedDefaultHabits` *after* the
save returns, so an interrupted first launch is retried rather than half-recorded
forever. `DemoHistory` writes its own transaction, and the demo's provenance is
a column on `Completion` rather than a list of ids beside the store: one write,
so "what did the demo add" cannot disagree with what is there. Both are in
decisions.md.

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

`Completion.dayKey` is the civil day as `yyyy-MM-dd`, and it is what the app
groups, counts and looks up on. `Completion.day` is still there and is still the
local midnight the row was written at, but it is evidence rather than identity
and nothing compares it. `Habit.completionDayCounts` is the single place rows
become history — `[DayID: Int]`, fetched through the context — and
`completionCounts(in:)` / `completedDays(in:)` project it onto whichever
calendar is drawing. Keeping the projection separate is deliberate: the identity
half depends on nothing but the store, and the calendar half must not be
remembered because the calendar can change under it.

That seam was described here as the one a cache belongs behind. **Nothing is
cached across renders and nothing should be** — the widget's intents write this
store from their own process and never tell the app, so a cache they cannot
invalidate is a wrong number that survives until something unrelated redraws.
What #135 did instead was bound the read; the measurement that settled it is in
decisions.md.

The backfill for stores written before that column lives in
`StoreMigration.stampDayIdentities`, and the migration record's `format` is now
2 with a `dayFormat` beside it. It is not on the critical path: `Completion.dayID`
infers a missing key with the same rule, so a store reads identically before,
during and after — which is what makes the riskiest migration in the app one
that can be abandoned at any point. See decisions.md.

`Completion.demoSessionID` is provenance: `nil` for a completion a person
logged, and the seeding's id for one the demo invented. It is what the demo
toggle reads and what its removal fetches on, so a demo is identifiable from the
store alone. Optional with a `nil` default, which makes it a lightweight
migration for a store written before it existed — verified against one.

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
`xcodebuild test`. It picks whichever iPhone simulator the machine actually
has, so it behaves the same locally and on a runner with a different Xcode; it
runs the suite once into a result bundle under `Artifacts/<run>/`, unique per
run and gitignored; and it then asks `Tools/validate-test-result.py` whether the
run was really a pass.

That last step is the point (#138). `xcodebuild` exiting 0 answers one question
— did anything that ran report a failure — and a lost test bundle, a suite that
shrank by three hundred tests, a skipped test and a compiler warning all exit 0.
The validator reads the `.xcresult` through `xcresulttool` and fails when:

* a test bundle named in `Tools/test-inventory.json` did not run, or ran fewer
  tests than its reviewed floor;
* a bundle ran that the inventory does not declare;
* any test is anything other than `Passed`;
* the build carries a warning that is not in the inventory's fingerprinted
  allowlist;
* the run left no render-baseline manifest, or failed a visual test without
  attaching the images.

The floors are minima. Adding a test never touches the inventory; lowering a
floor is the reviewable event, because it means tests were deleted. The
validator's own mutations run under `--self-test`, on every push, on a Linux
runner — a checker nobody checks can weaken silently.

Tests exercise the real app types via `@testable import Glow`. Never
re-implement app logic in a test file: a mirror copy passes forever while the
app regresses.

`WeekGridTests` includes an exhaustive pass: for each cadence, all 128 possible
completion histories of a week, asserting R1 and R2 hold for every one — R2 under
each `SlotEditing` case, since it is now a difference between surfaces rather
than one answer, and the same sweep again over a week already over, which is the
branch with no today in it. That is
cheap here because the logic is pure, and it is the reason those invariants can
be stated as facts rather than as intentions.

Those sweeps name the rest day they mean, in the call (#181). They used to be
correct only because nothing else was setting one at the same time — a claim
about the scheme's ordering, restated in `project.yml` — and they are now
correct by construction.

`GlowRenderTests` is a second test target: it renders the real `WeekWidgetView`
at the design frame's own 338 × 354 and, once a design export is committed
(`RenderTests/DesignReference/`), diffs the two and reports where they disagree
(#6). Its own target because `GlowTests` reaches the app module and the
widget's view is not in it — so it compiles the widget's sources directly, the
same sharing the widget target itself uses, hosted by the app so `Bundle.main`
carries the symbol catalogue. It also carries the **render baseline**: a
committed 16 × 16 grid of mean brightness per widget family, in
`RenderTests/Baselines/render-signatures.json`, rendered for a pinned date at a
pinned glow setting. Each cell averages roughly 450 pixels, so antialiasing
moves a cell by well under one level while a mark that moves a column moves
several cells by tens — measured as bit-identical across two simulator models,
with the tolerance at 3 for headroom. A change that is deliberate is approved by
copying the manifest the run attached over the committed file; `Tools/test.sh`
prints that command with the run's own path in it.

CI runs the same script on pull requests and on merges to `main`, plus an
unsigned Release build against the device SDK — the configuration and the SDK
that ship, which the simulator test lane never compiles. Every run uploads its
`Artifacts/` directory, passing or failing.

## The App Group

The widget runs in its own process and cannot see the app's private container,
so the store lives in `group.com.georgklock.glow` and both open it there.
`StoreLocation` owns that decision and names the two paths the store has ever
had; `StoreMigration` owns the one-time move between them.

If the group container is unavailable the app falls back to its own container
and keeps working; only the widget goes blank. That is deliberate: a missing
entitlement should not stop the app launching. The migration runs to wherever
the store now lives, shared or not, because the file name changes either way.

### Moving a store without adopting half of one

A SQLite store is three files — the database, the write-ahead log and the
shared-memory file — and the recent writes are the ones still in the log. So
nothing is copied into place:

1. a complete set is copied into `Migration-Staging/`, a directory beside the
   destination so that promoting it is a rename rather than a second copy;
2. the staged copy is opened as a real `ModelContainer` and its habit and
   completion identifiers are read back — opening it *is* the validation;
3. it is promoted sidecars first and database last, because the database file is
   what every later launch tests for. Interrupted before the last move there is
   no destination and the next launch starts over; interrupted after it every
   file is already there;
4. `Glow.store.migration.json` is written last: a durable record carrying a
   format version, a generation id, the source and the counts. Its presence is
   what makes later launches cheap.

A destination that exists *without* that record is not trusted. It is opened and
compared against the source by identifier: a superset is adopted and recorded,
an unopenable one or a strict subset — which is what a partial copy looks like —
is moved to `Quarantine/` and replaced, and two stores that each hold what the
other does not are both kept, with the record naming the one that was not merged
in.

The source is never deleted and nothing is ever overwritten in place. When the
migration cannot be completed, `GlowStore.makeContainer()` throws rather than
opening: an empty store created beside a person's real one is the failure that
cannot be undone. The app shows `StoreUnavailableView` instead of terminating.
See #131 and docs/decisions.md.

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
profiles grant the group and whether a named device build actually carries it.
It takes the app's path (defaulting to `build/device`'s Debug product) rather
than searching for one, and an app that is not there is a failure: a check that
reports success when it found nothing to check is worse than no check.

Two of those four fixes live in generated files, which nothing reviews. So
`Tools/check-project.py` runs at the end of every `Tools/generate.sh`, reads the
project back through `plutil` — as a property list, the way Xcode does — and
fails the generation unless both targets carry `SystemCapabilities` as a real
dictionary with App Groups enabled, and unless the entitlements file each target
names on disk actually contains `group.com.georgklock.glow`. The generator that
produced it is pinned by digest in `Tools/xcodegen.pin`.

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
where `project.yml` puts it and stays Georg's call. That stamp reaches both
bundles only since #133: the host target did not read `CURRENT_PROJECT_VERSION`
or `MARKETING_VERSION` at all, so xcodegen's own defaults shipped a `1.0` / `1`
app beside a `0.1` widget, and the override on the archive command moved the
widget's build number while the app kept the literal.

**Nothing is uploaded that has not been read back.**
`Tools/check-release-build.py` opens a built product — a `.app`, an
`.xcarchive` or an `.ipa` — and fails on a host and appex that disagree on
either version key (naming both values), on an appex that is missing or
undeclared, on a bundle identifier that is not the declared one or is not the
host's plus one component, on an unexpanded `$(BUILD_SETTING)` still sitting in
a shipped plist, and on a missing `PrivacyInfo.xcprivacy`. With
`--require-signing` it adds what only a signed bundle answers: that the App
Group survived codesign, read out of the signature rather than out of the
source file, and that the embedded profile has not expired.

What it checks is declared in `Tools/test-inventory.json`, beside the test
floors, and it runs from two places on purpose — CI's unsigned Release build
for the device SDK, and `Tools/ship-testflight.sh` on the archive before the
export and on the exported `.ipa` immediately before the upload. One file, two
callers: a gate and a release path that each carry their own idea of "matching"
will eventually disagree, and the release path is the one nobody watches. The
first upload verified the App Groups entitlement survives distribution signing
by hand; that is now the last thing that happens before `altool` runs.

The script also runs `Tools/test.sh` before archiving. `--skip-tests` skips it
and says so on the way past.

## The widgets

The week widget: small, medium and large, reading the same store through the
App Group, with today's slot as an `AppIntent` button. Past days are not
buttons: the widget passes `SlotEditing.todayOnly`, which is R2's asymmetry
holding in a second process.

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
