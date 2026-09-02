import ActivityKit
import SwiftData
import SwiftUI
import WidgetKit

@main
struct GlowApp: App {
    /// One container for the whole app. Local only: no CloudKit in v1, though
    /// the model shape is kept sync-ready. See docs/ARCHITECTURE.md.
    ///
    /// Optional, because opening it can fail and the app has something better
    /// to do about that than die. `GlowStore.makeContainer()` refuses to open a
    /// store whose migration did not complete, and the failure a person would
    /// hit is therefore *recoverable by definition*: their history is still on
    /// disk, at the path the app declined to abandon. A `fatalError` here
    /// crash-looped instead, which looks exactly like the data being gone.
    @State private var container: ModelContainer?
    @State private var failure: String?

    init() {
        // **An overridden "today" does not survive a launch** (#204). The
        // override is a full simulation with real write powers: a tap while it
        // is on logs a genuine completion dated to the simulated day, and once
        // that row is in the store nothing distinguishes it from a real one.
        // The week-boundary check in `DebugToday` bounds it to days; this
        // bounds it to one app session, which is the difference between a
        // debug tool somebody forgot to turn off and one that quietly rewrites
        // what "today" means until somebody happens to notice.
        //
        // First, before the store is opened or a view can read it, so no
        // surface is ever built from a stale override.
        DebugToday.clearOnLaunch()

        // **A setting no screen offers must not go on being read** (#390). The
        // rest day came out of Settings for MVP scope, which retires the UI
        // and not the arithmetic — so an install that had one stored before
        // this build would keep resting on that day with nothing anywhere to
        // turn it off. Cleared here, beside the override above and for the
        // same reason: before the store is opened or a view can read it.
        //
        // Runs in the test host too, and harmlessly: the host's store is a
        // per-process suite whose persistent domain `GlowSettings` already
        // wipes on creation, and this is over before any test writes a key.
        WeekPreferences.retireRestDay()

        // A unit-test host opens nothing and draws nothing. A UI test is a
        // different process: it must launch the real interface and drive a
        // screen-coordinate touch, but it must not inherit or mutate whatever
        // App Group history happens to be on the selected simulator (#494).
        #if DEBUG
        let runsWidgetPreviewUITest = ProcessInfo.processInfo.arguments.contains(
            "-glow-widget-preview-ui-test"
        )
        #else
        let runsWidgetPreviewUITest = false
        #endif
        let attempt: (container: ModelContainer?, failure: String?)
        if GlowSettings.isRunningTests {
            attempt = (nil, nil)
        } else if runsWidgetPreviewUITest {
        #if DEBUG
            attempt = Self.openWidgetPreviewUITestStore()
        #else
            attempt = Self.open()
        #endif
        } else {
            attempt = Self.open()
        }

        // Second, and only when a real store was opened: the sweep that takes
        // the per-day habits out (#239). It used to hang off `WeeklyGridView`
        // appearing, which is a screen the store can outlive being shown —
        // the system's widget configurator is a *separate process* reading the
        // same file, and it never opens that screen at all, so rows the app
        // believes it has deleted were still on disk when "Choose Habit" read
        // them.
        //
        // Here rather than in a `.task` on `body` for the ordering: everything
        // downstream — the reload below, `WeeklyGridView`'s own reach, the
        // empty state's claim about what the store holds — is then reading a
        // store that has already been swept, without any of them having to
        // know the sweep exists. Two `.task` bodies have no such order between
        // them.
        //
        // Inert in the test host by construction, not by a second check: the
        // binding above hands back no container under tests, so there is
        // nothing for this to open a context on. A migration running in the
        // test process is the process-wide store leak #105, #168, #175 and
        // #179 closed.
        if let container = attempt.container {
            Self.migrateDailyHabitsOut(in: container)
        }

        _container = State(initialValue: attempt.container)
        _failure = State(initialValue: attempt.failure)

        #if DEBUG
        if let container = attempt.container,
           ProcessInfo.processInfo.arguments.contains("-glow-force-burst") {
            Self.forceBurst(in: container)
        }
        if ProcessInfo.processInfo.arguments.contains("-glow-debug-pop") {
            Self.debugPop()
        }
        if ProcessInfo.processInfo.arguments.contains("-glow-dump-widgets") {
            Self.dumpPlacedWidgets()
        }
        #endif
    }

    #if DEBUG
    /// One deterministic, process-local habit for the physical-touch UI gate.
    /// Debug-only and in memory: a failed test cannot alter a person's or a
    /// simulator's existing Glow history, and each launch begins open again.
    private static func openWidgetPreviewUITestStore()
        -> (container: ModelContainer?, failure: String?)
    {
        do {
            let container = try ModelContainer(
                for: GlowStore.schema,
                configurations: ModelConfiguration(
                    schema: GlowStore.schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            )
            let context = ModelContext(container)
            context.insert(Habit(
                name: "Preview Touch Fixture",
                icon: "hand.tap",
                frequency: .daily,
                createdAt: WeekCalendar.today(),
                sortOrder: 0
            ))
            try context.save()
            return (container, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    /// Fires the goal pop without a goal, so its presentations can be looked
    /// at from a tethered Mac — the same reason `-glow-force-burst` exists for
    /// the widget's burst. The real pop lasts two seconds and only fires when
    /// a goal is actually met; this one stays up until the activity is ended
    /// or the system reaps it, because the point is a screenshot, not the
    /// gesture. It does not go through `GoalPopCentre` on purpose: the centre
    /// owns *when* a pop is allowed to fire, and a debug affordance that
    /// taught it a second answer would be the two-callers bug its type comment
    /// warns about.
    ///
    /// The line is the longest one the app writes, so what is being looked at
    /// is the worst case for truncation and wrap.
    private static func debugPop() {
        // Requested immediately, not after a settle delay: a backgrounded app
        // is suspended, so a sleeping task here never wakes and the request
        // never fires. Requesting from the foreground works — the Island just
        // does not *render* it until the app leaves the screen (measured; see
        // GoalPopCentre) — so the order is launch, request, then background
        // by hand and look.
        Task { @MainActor in
            let content = ActivityContent(
                state: GoalPopAttributes.ContentState(
                    habitName: "Early night", line: "that's the week"
                ),
                staleDate: nil
            )
            _ = try? Activity.request(attributes: GoalPopAttributes(), content: content)
        }
    }
    #endif

    private static func open() -> (container: ModelContainer?, failure: String?) {
        do {
            return (try GlowStore.makeContainer(), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    /// Takes the per-day habits out of the store, once per install (#209).
    ///
    /// The decision about *what* to delete is `DailyHabitMigration`'s and stays
    /// there; what moved in #239 is only when it is asked. A failure is logged
    /// and swallowed: the migration leaves the store exactly as it was and
    /// writes no flag, so the next launch tries again — which is the whole
    /// reason it must not be allowed to take a launch down with it.
    ///
    /// `refreshReach()` does not move with it. `reach` is `WeeklyGridView`'s
    /// own `@State`, and that view already calls `refreshReach()`
    /// unconditionally from its own `.task`; the extra call the migration used
    /// to make existed because the sweep could land *after* that task had run.
    /// From here it cannot — this is over before any view is built — so the
    /// unconditional call is the whole of it.
    private static func migrateDailyHabitsOut(in container: ModelContainer) {
        do {
            try DailyHabitMigration.runIfNeeded(context: ModelContext(container))
        } catch {
            HabitStore.report(error, operation: "migrateDailyHabitsOut")
        }
    }

    #if DEBUG
    /// Records a burst and reloads, so the widget's burst path can be driven
    /// from a tethered Mac without a thumb on the glass.
    ///
    /// This is not a substitute for watching the animation — it cannot say
    /// whether anything moved. What it can answer is the question underneath:
    /// the note expires after `WidgetBurst.maximumLag`, so if WidgetKit takes
    /// longer than that to call the provider, the burst is always gone before
    /// it is read and the widget renders still no matter how correct the logic
    /// is. The trace timestamps both ends, so the gap is measurable rather
    /// than argued about.
    ///
    /// That gap is the whole of #267: the expiry used to be `duration`, 0.3s,
    /// and a phone measured 431ms and 3.17s of it. See docs/glow.md.
    private static func forceBurst(in container: ModelContainer) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)])
        guard let habit = try? context.fetch(descriptor).first else {
            WidgetTrace.record("forced burst: no habits to burst")
            return
        }
        // A debug affordance for watching the burst, so it deliberately does
        // not honour Reduce Motion — the point of forcing one is to see it.
        WidgetBurst.record(habitID: habit.id, reduceMotion: false)
        WidgetTrace.record("forced burst for \(habit.id.uuidString), reloading")
        WidgetRefresh.invalidate()
    }
    /// Records every placed widget's kind and family into the trace, so a
    /// tethered Mac can see what is actually on a Home Screen without a thumb
    /// or an eye (#321).
    ///
    /// `WidgetCenter.getCurrentConfigurations` is the only public view of
    /// placements, and it answers the one question the providers' own trace
    /// lines cannot: an instance that is placed but no longer served builds no
    /// timeline and therefore leaves no line, so its absence from the trace is
    /// indistinguishable from its absence from the screen. This lists it
    /// either way. Kinds and families only — same privacy rule as the rest of
    /// `WidgetTrace`.
    private static func dumpPlacedWidgets() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            switch result {
            case .success(let infos):
                WidgetTrace.record("placed widgets: \(infos.count)")
                for info in infos {
                    WidgetTrace.record("placed: kind=\(info.kind), family=\(info.family)")
                }
            case .failure(let error):
                WidgetTrace.record("placed widgets: query failed, \(error)")
            }
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            if GlowSettings.isRunningTests {
                // **The test host runs no interface** (#179). The app's own
                // views observe preferences through `@AppStorage` —
                // `WeeklyGridView` the week's first day, every `HabitRowView`
                // the rest day, `GlowImageCache` the glow level — and the
                // tests write exactly those keys. Swift Testing runs off the
                // main thread, so each write published into a live SwiftUI
                // hierarchy from a background thread, which is undefined
                // behaviour and showed up as the host dying on an unwrap in
                // somebody else's code, failing a different innocent test each
                // time.
                //
                // Measured: 106 runtime warnings in one `GlowTests` run before
                // this, against 0 in `GlowRenderTests`, which hosts no
                // interface. A test bundle needs a process to live in, not an
                // app to race.
                Color.black.ignoresSafeArea()
            } else if let container {
                RootTabView()
                    .tint(GlowPalette.color)
                    .preferredColorScheme(.dark)
                    .modelContainer(container)
                    // **Every other reload in this app is write-triggered**
                    // (#236). `HabitStore.commit()` invalidates on every save,
                    // `DailyHabitMigration` after it sweeps, the intents after
                    // a tap — so until something writes, nothing tells
                    // WidgetKit to ask the provider again. A TestFlight update
                    // that changes what the widget *draws* rather than what the
                    // store *holds* lands in exactly that gap: the new code is
                    // installed, no write happens, and the placed widget goes
                    // on rendering what the old build left there.
                    //
                    // Unconditional, because there is nothing to compute: an
                    // argument-less `invalidate()` reloads every kind, and a
                    // reload against unchanged data is a no-op render.
                    //
                    // **Here, and not in `init`, because `init` is also the
                    // test host's.** The container branch is the one the host
                    // never reaches — `GlowSettings.isRunningTests` is checked
                    // first and draws `Color.black` instead, and under tests
                    // `container` is `nil` anyway because `init` opens none. A
                    // reload fired from `init` would fire in the test process
                    // too, which is the class of leak #179 closed.
                    //
                    // **Last of the three things a launch does, and the order
                    // is load-bearing.** `init` clears a stale `DebugToday`
                    // override (#204) and sweeps the per-day habits out
                    // (#239), and both change what the widget should draw —
                    // the override lives in the App Group where the widget
                    // reads it, and the sweep deletes rows the widget renders.
                    // A reload placed ahead of either would ask the provider
                    // for a redraw of data about to be discarded, and then
                    // nothing would ask again. `init` runs before any of
                    // `body`, so a `.task` here is strictly after both.
                    .task { WidgetRefresh.invalidate() }
            } else {
                StoreUnavailableView(message: failure ?? "") {
                    let attempt = Self.open()
                    container = attempt.container
                    failure = attempt.failure
                }
                .preferredColorScheme(.dark)
            }
        }
    }
}
