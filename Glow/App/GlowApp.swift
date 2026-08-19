import SwiftData
import SwiftUI
import WidgetKit

@main
struct GlowApp: App {
    /// One container for the whole app. Local only: no CloudKit in v1, though
    /// the model shape is kept sync-ready. See docs/ARCHITECTURE.md.
    private let container: ModelContainer

    init() {
        do {
            container = try GlowStore.makeContainer()
        } catch {
            // A store that cannot open is not recoverable from inside the app,
            // and continuing would silently drop every write.
            fatalError("Could not open the habit store: \(error)")
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-glow-force-burst") {
            Self.forceBurst(in: container)
        }
        #endif
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
        WidgetBurst.record(habitID: habit.id)
        WidgetTrace.record("forced burst for \(habit.id.uuidString), reloading")
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            WeeklyGridView()
                .tint(GlowPalette.color)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
