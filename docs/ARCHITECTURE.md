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
  it" rather than five — and one *instant* per week, whichever of that week's
  days asks. Day arithmetic keeps the wall clock, and where the clocks move at
  midnight a wall clock reading 00:00 is not the start of its day, so both
  `startOfWeek` and `week(containing:)` normalize again afterwards (#242).
- `WeekGrid.slots(for:in:today:)` turns a habit plus a week into the row of
  slots to draw. This is the entire interaction model of the app, and it is one
  function.
- `WeekReach` is how far back the week view may be paged: two week starts,
  derived from where the record begins and bounded by nothing else (#186 —
  there was a twelve-week cap). Separate
  from `SlotEditing` on purpose — one says which weeks there are to visit, the
  other says what a tap may do on the week you are on, and neither needs to
  know the other's answer. It trusts the date it is handed: the record's start
  comes from `HabitStore.earliestRecordedDay`, which is where a habit carrying
  the unknown-creation sentinel is refused, because an uncapped pager over the
  year 1 is a scroll with no end.
- `SlotLayout` is the row geometry, as a single formula that a 7-circle row and
  an N-pill row both go through.
- `Frequency` normalizes cadence at construction, so no caller can build a
  degenerate one. **One kind, counted across a week** — there was a second,
  counted within a day, and it is out of the shipped app and preserved on
  `feature/daily-habits-2.0` (#209). `slotCount` stays optional with no case
  answering nil: it was the per-day kind's, and flattening it now would rewrite
  every caller in the change that removed the feature and again in the one that
  restores it. `Frequency.daily` is not that kind and never was — it is a
  weekly cadence due all seven days.
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
  screen is a table when it is read aloud and stays hidden; a month of columns
  is counted into one sentence instead. Both are pure, so the app and the
  widget cannot disagree about a word and the strings are asserted without a
  renderer.
- `ResetConfirmation` is the gate in front of Reset to Default Habits: the word
  that has to be typed, and what counts as having typed it. Four lines, out of
  the view for the same reason `MotionPolicy` is — it stands in front of the
  one action that deletes everything at once, and a rule living inside a
  `.disabled(…)` is a rule nothing can assert.
- `MotionPolicy` decides whether a change moves. One completion is drawn three
  ways — a ring closing, a bar closing, a label dimming — and Reduce Motion has
  to reach all three; a predicate left in a view is one no test can reach. It
  was four while the Today ring's sweep shipped (#209).

Every function takes its `Calendar` and its `today` as parameters. Nothing here
reads the clock, which is what lets the tests assert against a fixed Tuesday in
August rather than against whenever they happen to run.

**`WeekCalendar.today()` is the one exception, and it is not in this directory**
(#204). It answers "what day is it" for every surface, and to answer it has to
read both the clock and the App Group — so it is declared in
`Glow/Store/DebugToday.swift`, at the boundary, and only the spelling lives on
`WeekCalendar`. `TestIsolationTests` scans `Glow/Logic/` for `Date()`,
`DebugToday` and `WeekCalendar.today`, because the extension is in the same
module and a call to it from in here would otherwise compile.

**The rest day arrives the same way** (#181) — though nothing supplies one any
more: #390 retired the Settings rows for MVP scope and `GlowApp.init` calls
`WeekPreferences.retireRestDay()` on every launch, so the parameter is nil on a
real install and the paragraph below describes plumbing that is inert but still
tested. `WeekPreferences` is where the
stored value lives; nothing else in here reads it. `WeekGrid`, `WeekSpans`,
`WeekDots`, `MonthGrid`, `SeededHistory` and `SlotEditing` all
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
actually draws — `week.dayIDs()`, `MonthGrid.dayRange(containing:)` — and
pushes the bound into SQLite on `Completion.dayKey`.
`habit.snapshot()` with no range still means the whole history and is what the
export calls.

**And so is the write path, since #318.** `HabitStore`'s day lookup — the one
`toggleCompletion` runs twice per tap — fetched every completion the habit had
and picked the day's out in memory, so the app's hottest path scaled with the
whole record while every *read* had been bounded since #135: 1.8ms per lookup
over ten weeks of history, 75ms over ten years. It now carries the same
predicate shape the reads do, the day's `dayKey` **or** an empty one, which is
what keeps a row whose day is inferred rather than recorded (#130). Like the
reads, it needs no way to ask whether a store has been through the backfill.

**And no writer reads the habit's own array at all.** `setCompletion` kept
`habit.completions` in step by hand on both arms of the write (#318), and the
demo's seed and removal, the reset, `addCompletion`, `clearDay` and
`clearHistory` did the same until 2026-09-02. That is a to-many relationship:
reaching it faults every completion the habit has ever had, and — the reason
that mattered more — it is the cached array #145 made every reader stop
trusting, so a writer iterating it after a peer container deleted one of its
rows was the same trap on a different tap. The lines are gone everywhere and
SwiftData maintains the inverse from `Completion.habit`, which the initializer
sets and `context.delete` clears — `PersistenceTests` and `StaleWriterTests`
assert that rather than assuming it, because it is a claim about the
framework. `clearHistory` fetches the habit's rows by predicate. Nothing reads
the cached array on a live store: `Habit.liveCompletions` fetches, and falls
back to the array only for a model object that was never inserted. See
decisions.md, 2026-09-02, for the one exposure that remains inside SwiftData's
own cascade.

The snapshot it hands back therefore holds only those days, which is the one
thing to know before passing one on. Everything week-shaped asks only about days
inside the week it was given, so a week's worth is all a week's row needs;
`Tests/HistoryProjectionTests.swift` asserts that against `WeekGrid`,
`WeekSpans`, `WeekDots`, `GoalMet` and `MonthGrid` rather than against a
reading of them.

**The widget's Island acknowledgement reads that bound before it writes**
(#464). `OptimisticPop.shouldPresent` takes the requested absolute state, the
pre-write week snapshot and the stored preference. It rejects undo, spacers and
a day already completed; for **Goals** it adds one hypothetical row to the value
snapshot and asks `GoalMet`, while **Everything** accepts any otherwise-new
completion. `MarkHabitIntent` calls `GoalPopCentre` with that answer before
`HabitStore.setCompletion`, so ActivityKit starts alongside the optimistic
widget control rather than behind the save.

`SlotToggle` also carries the presentation boundary into the shared
`MarkHabitOperation`. Installed widgets reach it through `MarkHabitIntent` with
the Island enabled. The in-app Widgets preview reaches it through a binding
adapter over the app's live `ModelContext`, with the Island disabled. Both use
the same absolute-state write and reconciliation path, but the foreground app
does not request a Live Activity the system will not display.

`LatestPopDelivery` owns replacement ordering for a running Live Activity. It
does not serialise updates: every new operation begins immediately. When an
operation returns, it compares its generation with the latest; a stale one
delivers the newest operation again and repeats that check before exiting.
Thus an older ActivityKit call that finishes last cannot leave its old habit
name and line on screen. `PopWindow` remains a separate generation guard for
the two-second end task, whose clock restarts at every eligible tap.

### Slots carry their own action

`Slot.actionDay` is the day a tap would toggle, or `nil` if the slot is not
tappable. The view taps what it is handed.

This is deliberate. The alternative is for the view to work out which day a
given column represents, which means the day-pinning rules for daily rows and
the claimable-window rules for frequency rows both end up duplicated in the
view layer, where they cannot be tested. Instead, "is this tappable" and "what does
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

**`WeekSpans` owns claimable rep windows** (#476). In the current week a
completion owns the window ending on its logged day, today's open rep reaches
back over unused days and ends on today while another rep follows, and future
reps divide only future columns with shorter windows nearest today. A final open
rep instead owns the remainder of the week, just as a final completion does
(#495). A lost rep is a one-day cross on the earliest blank day it could have
used. Completing today changes only the open window's state; tomorrow's date
change is what redistributes any remaining future windows.

Span geometry does not grant editing. An ordinary week surface still resolves a
widened final open span to today, and the widget remains `.todayOnly`. The
demo-seeded week explicitly uses `allowingFuture: true`; there, future columns
inside that final span remain real demo controls and the fallback action is its
last column. That is the existing demo-only permission applied to the new shape,
not a permission leaked into production (#495).

Once an unmet week is entirely past, `WeekSpans` stops forecasting reps and
returns seven day-sized diary spans: completed, missed, or inactive before the
habit existed. A met past week keeps its completed rep windows and no crosses.
Both forms still pass through the same surface-action layer above, so the app
can correct past days and an installed widget remains today-only. Stored legacy
rest-day rows intentionally stay on the pre-#476 divider; rest-day redesign is
separate feature scope.

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
relationship array, so a row the widget tap's own context wrote is not missed
and a row it deleted is not touched — `MarkHabitIntent` runs in the app's
process (`LiveActivityIntent`, #58) but opens a container of its own per tap,
and nothing tells any other context what it did. Every row on the day comes off, not the first one
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

`count(for:on:)`, `addCompletion(for:on:)` and `clearDay(for:on:)` are the
day-level primitives `toggleCompletion` cannot express, because it stores zero
or one row per day by construction. The per-day kind was what made a day with
several rows ordinary, and `recordTap` — which asked `DayRing.countAfterTap`
what a tap meant — went with it (#209). What is left for them is the case that
outlives it: a store written before day identities can hold two rows for one
civil day (#130), and `clearDay` has to take every one of them.

Every write ends in a private `commit()`: save, and then invalidate the widget
timelines. A save that throws rolls back, so a failed write leaves the store as
it was rather than leaving its changes pending for the next unrelated save to
commit (#140). `addAll(_:now:)` is the batch door — a whole list inserted and
saved once, which is how the curated set arrives.

`resetToDefaults(now:)` is the destructive door (#193), and since #228 it is
the **only** door the defaults come through: every completion and every habit
deleted, then `DefaultHabits.all` inserted, all inside one `commit()`. One
transaction, so a failure leaves the person's habits where they were rather than
half-way through a deletion — the property `addAll` established for the first-run
seed, applied where it matters more. The inserts are numbered from zero rather
than from `nextSortOrder()`, which would be answering from rows already staged
for deletion; `addAll` and the reset share a private `insert(_:from:now:)` so the
list is built the same way in both. Completions go explicitly rather than by
`.cascade`, because a cascade cannot reach a completion whose habit is nil and
the claim here is that nothing survives.

Two callers, and what separates them is what the store held. Settings' Reset to
Default Habits is behind a typed confirmation because it is destroying a list
somebody arranged — see decisions.md. `WeeklyGridView`'s empty state calls it
unguarded, because it is only offered on a store that holds nothing and there is
nothing there to destroy.

**Nothing seeds by itself** (#228). `HabitSeeder` and its `didSeedDefaultHabits`
flag are gone: the flag existed to tell "never seeded" from "deleted everything"
apart so an emptied store would not refill overnight, and with no automatic
insert left, an empty store means one thing and gets one answer — the empty
state's two buttons. `DailyHabitMigration` still runs unasked, still on a flag
written after its save, and is now the only thing on that pattern.

`DemoHistory` writes its own transaction, and the demo's provenance is
a column on `Completion` rather than a list of ids beside the store: one write,
so "what did the demo add" cannot disagree with what is there. Both are in
decisions.md.

**The stored shape is a declared version** (#283). `GlowSchemaV1` freezes the
schema shipping today, `GlowMigrationPlan` is the one plan every container
opens through, and `GlowStore.container(at:readOnly:)` is the one spelling of
an open — the app's writable container, the widget's read-only one, and the
tests all call it. The upgrade floor is TestFlight builds only, documented in
the plan's own comment: earlier shapes are explicitly unsupported and not
reconstructed. The three migration layers run in a fixed order — file
location (`StoreMigration.run`), then this plan at container open, then the
row backfills — and `SchemaContractTests` fails any model edit that changes
stored metadata without a version decision.

### Models

SwiftData, shaped for a CloudKit future even though v1 is local-only: every
property has a default, there are no unique constraints, and the relationship
is optional. CloudKit requires all three, and retrofitting them later means a
migration rather than a configuration change.

`Frequency` is stored as `isDaily` plus `timesPerWeek` rather than as an encoded
enum, so the column stays queryable and a schema change does not hinge on an
enum's `Codable` representation. `timesPerDay` is still a column and is always
zero in a shipped build (#209): dropping it is a schema change, and it is what
`DailyHabitMigration` finds the leftover rows *by*. #123's set shipped five
per-day habits, so an install updating from a build that carried them holds
habits nothing can now draw; the migration deletes them and their completions
once, at launch. **It destroys history** — repetitions logged during the
window the feature shipped in are gone — and the release notes for the build
carrying it have to say so.

`Habit.weekly` is the one fetch predicate, and it is the old `countedPerWeek`
clause under a name that says what it now does. It is deliberately not `true`:
with the per-day kind gone it filters the rows that kind left behind, and the
widget's process never runs the migration, so a home screen redrawing before
the app is next opened would otherwise show habits the app has no screen for.
It goes when the migration does.

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
cached across renders and nothing should be** — the widget's tap intent writes
this store through a container of its own (in the app's process since its
`LiveActivityIntent` conformance, #58, but on a context nothing here observes)
and never tells the app's live contexts, so a cache the writer cannot
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
logged, and the demo session's id for one the demo invented. It is what the demo
toggle reads and what its removal fetches on, so a demo is identifiable from the
store alone. Optional with a `nil` default, which makes it a lightweight
migration for a store written before it existed — verified against one.

### Views

Mostly layout. The one piece of real behaviour is `SlotView`'s completion
transition, which is documented in place and in [glow.md](glow.md).

`RootTabView` carries three tabs: Widgets, This Week and Settings, in that
order (#238), with This Week as the landing tab — the first tab is what the
app says it is about, the landing tab is what every launch opens to, and the
two are held separately on purpose. The Widgets tab began in Today's old slot:
Today drew the per-day habits as rings and is on `feature/daily-habits-2.0`
with `DayRingView` and the geometry under it (#209); the slot was left empty
rather than collapsed so that #210 could fill it in the same position, and the
bar reflowed once rather than twice. #238 then moved Widgets to the front,
an order argued on its own terms rather than inherited.

`WidgetsView` is that tab: every widget this bundle ships, previewed by the
shipping view, as three named cards — "Large Week Widget", "Medium Week
Widget", "Monthly View per Habit", largest first (#312). Four pieces make it
what it is.

**The previews are the production views.** `GlowWidget/WeekWidgetView.swift`,
`GlowWidget/MonthWidgetView.swift` and the two entry types are compiled into
the *app* target as well as into the extension — the same sharing
`GlowRenderTests` does, and the reason each view sits in a file with its entry
and neither a `@main` bundle nor a provider. The view is laid out at
`WidgetMetrics.size(of:)` for its family and then scaled to fit, because slot
size is derived from track width: drawn at a convenient width it would be a
different layout rather than a smaller one. `WeekWidgetView.familyOverride`
exists for the same reason the render harness needs it — `widgetFamily` is
read-only outside WidgetKit and reports medium everywhere else.

The small month uses the same top inset and type size, but its habit name owns
`WidgetMetrics.monthTitleHeight` rather than borrowing the week widget's
`headerHeight`. The latter is the compact weekday-letter row. The former is an
18pt text line box, which puts the month grid at y=32 in the authored 158pt
frame while leaving every week grid untouched (#493).

**The previews use the production optimistic state with an app-host adapter.**
WidgetKit owns touch delivery for its archived `Toggle(intent:)`, but the same
custom `ToggleStyle` receives no automatic press handling in an ordinary
SwiftUI hierarchy. `SlotMarkToggleStyle` therefore renders the same two faces
for both hosts while wrapping only the app-hosted face in a plain button that
mutates the supplied binding. That binding remains `SlotToggle`'s serialized,
optimistic operation path, so rapid taps still replace the pending value and
reconcile from the store. Socket flattening is orthogonal: only its decorative
background is rasterized, and that subtree never participates in hit testing.

**The catalog is the extension's own list.** `WidgetKind.families` declares
which families each kind supports and `supportedFamilies` is set from it, so
the page's list and the extension's are one list — read largest-first by
`WidgetCatalog.all`, because the page leads with its Large card (#312).
`WidgetCatalog` (in `Logic/`, pure) can also diff that list against what
`WidgetCenter` reported, dropping kinds this build no longer serves — a Home
Screen can still hold a `GlowTodaySmall` — and families outside
`supportedFamilies`. "Placed" means a family, not a kind. Nothing displays
that diff since #312 dropped the "Added" marks, so the view feeds it an empty
list; the logic and its tests stay for whatever displays it next.

**A per-habit widget is previewed per habit** (#237). `WidgetKind.isPerHabit`
declares whether a placed widget of that kind draws one habit somebody chose —
true for the month, whose `SelectWeeklyHabitIntent` asks as it is placed; false
for the week at every family, which is a `StaticConfiguration` over whatever the
week holds. `WidgetCatalog.groups(placed:habits:)` turns that into the page:
one group per placement, and under a per-habit placement one card per offered
habit, without a demonstration cap (#465). The group is what carries the card's one heading,
because a placement is one widget however many previews of it the page draws
(#312 named the headings and dropped the per-size captions). The habit ids
arrive as a parameter, read from the view's own `@Query` through
`MonthStore.offered`, so `Logic/` stays pure and the previews and the widget's
own picker cannot offer different habits. An empty list yields one card with no
habit, which is `MonthWidgetView`'s own empty state rather than a heading with
nothing under it. The clause that kept Week-Small to a single card went with
the family itself (PR #277).

**The catalog is lazy over one retained projection** (#478).
`WidgetsView` uses stable `WidgetCard.ID`s in nested `LazyVStack`s, so SwiftUI
realises only cards in or near the viewport. Before that change an ordinary
stack constructed the whole catalog, and each of Large and Medium evaluated a
separate week projection while every month preview opened another bounded
history read. `WidgetPreviewProjectionCache` now performs one read over
`MonthGrid.dayRange`; that range is made of whole weeks and already contains
the current week, so filtering its value snapshots supplies the one shared
`WeekEntry` as well as every `MonthEntry`. No preview body opens SwiftData.

The cache key is the normalized day, first-weekday preference, ordered habit
fingerprints and a successful-store revision. Ordinary geometry and optimistic
redraws therefore return values synchronously without another read or an empty
loading frame. Every successful `HabitStore` commit advances the revision via
`StoreChange.committed`; `DemoHistory` posts the same signal because it owns a
separate save boundary. Failed, unchanged and refused operations do not
invalidate history. `StoreChange.fromIntent` remains the redraw/reconciliation
signal for all final intent verdicts, while a successful intent also crosses
the commit signal from the shared `HabitStore` operation.

**Socket rendering follows the host, not the widget view** (#479).
`EnvironmentValues.flattensWidgetSockets` defaults to `false`, preserving the
live-vector path used and baselined by WidgetKit. `WidgetsView` sets it to
`true` around the real production view because that copy lives in a scrolling
app hierarchy. Each descendant `SlotMarkView` then sends only its socket
background through the existing `drawingGroup()` branch. The `SlotToggle`
stays above that layer, so rasterization cannot replace its hit testing,
optimistic state, label, hint or app/intent delivery adapter. Both toggle faces
inherit the host value, preventing an optimistic ring or dot from briefly
returning to live filters during a tap. `docs/widget-preview-scroll-trace.md`
is the repeatable physical gate for this boundary.

**Those production views are live controls in the app too** (#465). The page
does not disable hit testing or hide their accessibility trees. Today's
actionable week slots, frequency spans and month cell therefore remain the
same `SlotToggle` as a placed widget; past and future marks remain display-only
because the production views already derive them with
`SlotEditing.todayOnly`. WidgetKit backs that toggle with `MarkHabitIntent`.
An ordinary app host backs it with a local binding that changes `isOn` before
the write begins. Both adapters call the same idempotent `MarkHabitOperation`,
and the toggle style draws the same requested state from either adapter (#477).

A hosted app tree does not promote the accessibility label and hint attached
inside the custom AppIntent toggle style the way WidgetKit's archived tree
does. `WidgetsView` therefore marks the shared control as in-app through an
environment value, and `SlotToggle` repeats the same current label and hint at
the control boundary on that surface only. The installed widget keeps its
`configuration.isOn`-driven accessibility; the app's label and hint follow its
local optimistic binding and reconcile when the shared operation finishes.

The installed-widget intent writes through a peer `ModelContainer`, which
SwiftData does not merge into the app's already-fetched view state. The app
adapter instead hands the operation its already-live context. After every
operation verdict — including an unchanged duplicate or a refusal — the
historically named `StoreChange.fromIntent` is posted inside the process.
`WeeklyGridView` advances a local revision and takes fresh bounded snapshots.
`WidgetsView` redraws for every verdict but advances its retained projection
only for a successful commit, reconciling the optimistic face without making
an unchanged or refused operation refetch history. `WidgetRefresh`
independently asks installed widgets for a new timeline.

**`WidgetPlacementQuerying` is the seam.** `WidgetCenter` answers for the
Home Screen of the device it is running on, which a test cannot arrange, so the
one call and its mapping live behind a protocol in `Store/`
(`WidgetCenterPlacements`) and the diff is asserted against fixed lists. Since
#312 no view constructs the adapter — the page stopped asking when it stopped
saying "Added" — but the seam is where the ask goes when something says it
again. `currentConfigurations()` is a snapshot, not a subscription, so that
something would ask on `scenePhase == .active`: placing a widget necessarily
happens while the app is not frontmost.

**No API places a widget**, which is why the page is instructions plus
previews. `WidgetCenter` invalidates, reloads and reports;
`promptsForUserConfiguration()` is a `WidgetConfiguration` modifier that
prompts for a widget's *settings* after a manual add. Checked against the
iOS 26.5 SDK interface, not from memory.

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

## What a launch does, in order

Four steps, three of them in `GlowApp.init` and the last in `body`. The order is
not arrangement — each of the first three changes what the widget should draw,
and the reload is last so that it reloads against the settled answer.

1. **`DebugToday.clearOnLaunch()`**, before the store is opened (#204). The
   override lives in the App Group, so the widget reads it from its own process
   and draws the simulated week; clearing it changes what a widget is showing.
2. **The container opens**, or does not — `StoreUnavailableView` is the answer
   when it does not, and steps 3 and 4 do not happen at all.
3. **`DailyHabitMigration.runIfNeeded`**, on a context of that container
   (#239). It used to run when `WeeklyGridView` appeared, which is a screen a
   session can skip and another process cannot reach at all: the system's widget
   configurator calls `WeeklyHabitQuery.suggestedEntities()` from outside the
   app, reads the same file, and was offering rows the sweep had never been
   asked to delete. Everything downstream — the reload below, the pager's reach,
   the empty state's claim about what the store holds — then reads a swept
   store without knowing the sweep exists.
4. **`WidgetRefresh.invalidate()`**, unconditionally, from a `.task` on the
   container branch of `body` (#236). Every other reload in the app is
   write-triggered, so before this a build that changed what a widget *draws*
   rather than what the store *holds* reached the phone with nothing to tell
   WidgetKit to ask the provider again.

Steps 3 and 4 are inert in the test host without a second check: the binding in
`init` hands back no container under tests (#179), so there is nothing for the
migration to open a context on, and `body`'s `isRunningTests` guard draws
`Color.black` before the container branch is reached. A migration or a reload
running in the test process is the process-wide leak #105, #168, #175 and #179
closed.

On the one launch where the sweep actually deletes something, step 3 invalidates
too. `WidgetRefresh` coalesces calls made inside the same turn of the main
actor — the turn, not the launch — so whether that costs one reload or two is
the runtime's to decide. Measured on the simulator it was one:
`reloadAllTimelines()` appears once in chronod's log for that launch. Nothing
depends on the count, because a reload against already-correct data is a no-op
render. What the order buys is that the last word belongs to step 4.

## Day rollover

The open slot is defined as "today", so the screen has to notice when today
changes. Three paths, and all are needed:

- `NSCalendarDayChanged` covers the app being open across midnight.
- `scenePhase == .active` covers it being resumed the next morning without ever
  having been killed.
- `UserDefaults.didChangeNotification` covers the debug override moving (#204).
  It is set from Settings, which is a sibling tab, so the screens that draw the
  week stay alive and unredrawn while it moves — the same signal, and the same
  reason, as demo history.

## Which day the app thinks it is

`WeekCalendar.today()` is where "today" is established, and every surface that
needs one calls it and hands the answer down as a parameter. Nothing
downstream — `WeekGrid`, `WeekSpans`, `SlotEditing`'s future-write guard, the
widgets' timeline providers — knows there is anything to know.

`DebugToday` is what it consults first: a day of the current week, stored in the
App Group, that the app treats as today on every screen and in every widget
(#204). It is a simulation rather than a preview — a tap while it is on writes a
real completion dated to the simulated day — so it is fenced three ways, and
each fence exists because the failure it prevents is a write:

1. **Scoped to the real current week.** `override(calendar:)` compares the
   stored day against the seven midnights the real week is made of and clears
   the key when it is not one of them, so a stored day cannot outlive the week
   it meant something in. A midnight from another time zone matches none of
   them either, which fails in the safe direction.
2. **Cleared at launch**, first thing in `GlowApp.init`, before the store is
   opened. The longest a stray override can affect anything is one app session.
3. **Said out loud.** `DebugTodayBanner` sits on This Week for as long as one
   is set, and one tap on it clears the override — leaving it on must never be
   more convenient than turning it off.

It ships in every build, TestFlight included, and deliberately not behind
`#if DEBUG`: a Release archive is the build that gets installed on the phone
this app is tested on, and compiling the tool out of it would remove it from
the only place it is wanted.

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
at the design frame's own 338 × 354 — and, since #410, at one frame a phone
actually gives, 349.67 × 365, because a harness that renders only the design
frame is a harness that cannot fail for a reason a device would: the large
family lost a row on every phone and no signature moved. It also, once a design
export is committed
(`RenderTests/DesignReference/`), diffs the two and reports where they disagree
(#6). Its own target because `GlowTests` reaches the app module and the
widget's view is not in it — so it compiles the widget's sources directly, the
same sharing the widget target itself uses, hosted by the app so `Bundle.main`
carries the symbol catalogue. **It compiles a handful of the app's own views the
same way** (#386): `HabitRowView` and `WeekdayHeader`, with the two mark views
they draw with, so the gate holds isolated surfaces that are not widgets. It
also reaches the production app module for two full-screen frames.
`ImageRenderer` answers either screen's `NavigationStack` with SwiftUI's
invalid-configuration placeholder rather than the screen, so
`HostedScreenFrames` mounts the real `WeeklyGridView` and `WidgetsView` in a
`UIWindow` and captures the compositor with `drawHierarchy`. That path pins a
393 × 852 logical window, its 59pt top and 34pt bottom safe area, 2x
display/output scale, dark appearance and a fixed today. The safe-area
correction is applied before the hosting controller enters the live scene so a
simulator model cannot move the navigation layout (#481). It also carries the
**render baseline**: a
committed 16 × 16 grid of mean brightness per frame — the widget frames, three
isolated app frames and two whole app screens — in
`RenderTests/Baselines/render-signatures.json`, rendered for a pinned date at a
pinned glow setting. Each cell averages roughly 450 pixels, so antialiasing
moves a cell by well under one level while a mark that moves a column moves
several cells by tens. Direct frames were bit-identical across two simulator
models; after the safe-area pin, hosted-screen cells differed by at most one
level across three current-runtime models. The cell tolerance remains 3. The
hosted compositor's exact-black share spans 0.6 percentage points across those
models, so only those two frames use a measured 0.75-point black tolerance;
direct frames retain 0.5. A change that is deliberate is approved by copying
the manifest the run attached over the committed file; `Tools/test.sh` prints
that command with the run's own path in it.

`GlowUITests` is the process-level interaction exception. Its single fixture
launches Glow with a Debug-only, in-memory store containing one deterministic
daily habit, opens the Widgets tab, and taps the first visible preview mark at
screen coordinates. The assertion waits for the spoken control label to flip,
which proves both physical hit delivery and the optimistic face. The fixture
cannot inherit or mutate App Group history. This target exists because hosted
accessibility activation bypasses the physical-touch path that failed in #494;
logic remains in `GlowTests` and visual geometry remains in `GlowRenderTests`.

The grid is a gate on **geometry**, and it took #199 to say so: a mean dilutes,
and the marks that carry the unlit colour are thin, so #194 moved the whole
palette thirteen levels and no cell moved more than three against a tolerance of
three. The signature therefore carries a second statistic that thinness cannot
dilute — a **tone census**, the count of pixels painted flat at each level the
app is declared to paint, standing above the antialiased edge gradient that
passes through it. That number moves by the full population when a colour moves, and it caught
#194's move by a factor of a hundred where the grid caught it by nothing.
`Tools/test-inventory.json` says which claims the baseline makes and which it
does not.

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

Every file this app writes — the store and its sidecars, the fallback, the
legacy store, staging, quarantine, the migration record, both defaults
domains, temporary exports — is inventoried in `docs/data-inventory.md`,
along with what the OS does with each one: backup eligibility, protection
class, and why neither is set in code (#284).

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

**And nothing is archived whose source is not accounted for** (#287). Before
credentials are even read, the script proves the working tree is clean, that
`HEAD` equals fetched `origin/main` or a pushed annotated tag, and that CI
concluded successfully for that exact SHA — then writes a provenance record
(source SHA, ref, CI verdict, Xcode build, versions, and later the upload
itself) into the gitignored `private/provenance/`. The bundle validators answer
"is this build internally consistent?"; the preflight answers "which reviewed
commit produced it?", which no inspection of the artifact can. A dirty tree and
a wrong ref have no override; the CI verdict has exactly one, the named
`--allow-unverified-ci`, which is recorded. `--preflight-only` asks the
question without building anything.

The workflows themselves are part of the same contract:
`Tools/check-workflows.py` runs in CI's gate job and fails on a `uses:` that is
not a full commit SHA with its release named in an adjacent comment, and on a
`permissions:` declaration that is missing or broader than its allowlist — a
tag another repository's owner can move is code this repository never reviewed.

## The widgets

One widget kind since #322 — `"GlowWidget"`, three families, content decided
by family: medium and large draw the week, small draws one habit's month
through the same `MonthWidgetView` the month kind used. `GlowMonthSmall` is
removed rather than renamed, so a placed Month widget freezes; SPEC.md's
widgets section records why that was accepted. The week halves read the same
store through the App Group, with today's slot as an `AppIntent` button. Past
days are not buttons: the widget passes `SlotEditing.todayOnly`, which is R2's
asymmetry holding in a second process. (Small was the week's third family
until PR #277 dropped it for drawing unlabeled rows; #322's small is the
month's content, which names its habit.)

It renders the same HDR tile as the app, via the same `GlowImageView`, with
`fillsWidth` set because the widget's slots are distributed by an HStack rather
than measured by `SlotLayout`.

Which rows it draws is a per-widget choice (#188): `SelectWeekLayoutIntent`,
`WeekRowEntity` and `WeekRowQuery` in `Glow/Store/WeekWidgetConfig.swift` —
shared sources, for the reason the month widget's own note below gives. The
provider reads the store through `WeekWidgetStore` and hands the chosen ids to
`WidgetRows.rows(from:chosen:automaticSpacers:)`, which is the decision and
lives in `Logic/`. An unconfigured widget — nil, and also empty — follows the
view's family policy before the view cuts the eligible order to what its
measured frame holds: medium excludes automatic spacers, while large includes
them (#496). A non-empty configured selection always honours a chosen spacer.
`WeekEntry.rowsAreConfigured` carries that distinction through burst and
midnight entries. What the system's configuration sheet turned out to offer,
and what has not been confirmed on hardware, is on `SelectWeekLayoutIntent`
and in #191.

The Today widget is gone with the kind it drew (#209), and its two kind
strings — `GlowTodaySmall`, `GlowTodayMedium` — are removed rather than
renamed, so a placed Today widget leaves the Home Screen with the extension
that served it. `WidgetKind` now carries more than the strings: the families
each kind supports, its gallery name and its one-sentence description, all read
by the `WidgetConfiguration`s and by the Widgets tab, so the gallery and the
app cannot describe the same widget differently.

The small family's habit entity and query live in the
shared sources (`MonthWidgetConfig.swift`), not the widget target — bound now
to the unified `SelectWeekLayoutIntent`'s `habit` parameter (#322) — the app
exports AppIntents metadata of its own, the system consolidates metadata under
the app, and with the intent defined only in the extension the stored habit
choice never resolved when the provider ran. That was established on the Today
widget's own intent, which is where the note used to sit; the symptom is on the
surviving type in full.

**The gallery's preview is a fixture, and nothing else in the app is** (#365).
`WeekProvider` branches on `context.isPreview` before it reads anything, and so
does `placeholder(in:)`; both return `WidgetPreviewSample`, which builds the
curated `DefaultHabits.all` over `SeededHistory`'s invented past and lives in
`Logic/` with the day and the rest day as parameters. The reason is measured
and is in decisions.md: WidgetKit takes the gallery's picture by calling the
provider once per install of the extension and caching the render, so a store
read there freezes whatever the store said at that one moment — usually
"unavailable", because the commonest moment is before the app has ever been
launched. Everything below that branch is unchanged: a placed widget reads the
store and keeps #282's three outcomes.

## What is deliberately absent

- No network, no sync, no telemetry — **and enforced as an invariant rather
  than observed as a fact** (#281). Every production `ModelConfiguration`
  passes `cloudKitDatabase: .none`, because the parameter's default is
  `.automatic` and only the missing iCloud entitlement was standing between
  that default and a container. The entitlement itself is held closed from
  both ends: `Tools/check-project.py` rejects the six iCloud/ubiquity keys
  (and anything beyond the App Group) in what the generated project *requests*,
  and `Tools/check-release-build.py --require-signing` rejects the same keys
  (and anything beyond what distribution signing injects) in what the
  signature *grants*. `LocalOnlyContractTests` scans the production sources
  for the CloudKit/network API spellings the audit found absent; a match is a
  reviewed allowlist entry, not a silent merge. The privacy manifests remain
  declaration checks — none of this proves what Apple's frameworks do
  internally, only that changing Glow's own surface fails a gate.
- No view models. The logic that would live in one is in `Logic/`, and the rest
  is `@Query`.
- No coordinator or router. Three tabs on one `TabView`, sheets for what sits
  above them, and `DeepLink` mapping a widget URL to a tab is all the routing
  there is.
- No dependency injection container. The two things needing injection, the
  calendar and the model context, are parameters with defaults.
- No networking. There is none.
