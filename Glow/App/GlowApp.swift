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

        // A test host opens nothing and draws nothing. See `body`.
        let attempt = GlowSettings.isRunningTests
            ? (container: ModelContainer?.none, failure: String?.none)
            : Self.open()
        _container = State(initialValue: attempt.container)
        _failure = State(initialValue: attempt.failure)

        #if DEBUG
        if let container = attempt.container,
           ProcessInfo.processInfo.arguments.contains("-glow-force-burst") {
            Self.forceBurst(in: container)
        }
        #endif
    }

    private static func open() -> (container: ModelContainer?, failure: String?) {
        do {
            return (try GlowStore.makeContainer(), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    #if DEBUG
    /// Records a burst and reloads, so the widget's burst path can be driven
    /// from a tethered Mac without a thumb on the glass.
    ///
    /// This is not a substitute for watching the animation — it cannot say
    /// whether anything moved. What it can answer is the question underneath:
    /// the note expires after `WidgetBurst.duration`, one second, so if
    /// WidgetKit takes longer than that to call the provider, the burst is
    /// always gone before it is read and the widget renders still no matter how
    /// correct the logic is. The trace timestamps both ends, so the gap is
    /// measurable rather than argued about. See docs/glow.md.
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
