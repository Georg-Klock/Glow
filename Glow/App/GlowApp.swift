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
        let attempt = Self.open()
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
            if let container {
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
