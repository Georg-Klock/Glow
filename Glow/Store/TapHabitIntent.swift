import AppIntents
import Foundation
import SwiftData
import WidgetKit

/// One tap on a per-day habit's ring, from the widget: one more repetition,
/// or — from a full ring — the reset to zero.
///
/// The second intent beside `ToggleHabitIntent`, under the same rule: it must
/// work from the home screen without opening the app. The two stay separate
/// because they answer different taps — a week slot toggles a day, a ring adds
/// a repetition — and one intent switching on the habit's kind would put a
/// product decision inside a dispatch.
struct TapHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Repetition"
    static let description = IntentDescription(
        "Adds one to a habit counted through the day. A finished ring starts over."
    )

    /// Deliberately not `openAppWhenRun`. The point is to never leave the home
    /// screen.
    static let openAppWhenRun = false

    @Parameter(title: "Habit")
    var habitID: String

    init() {}

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { return .result() }

        let container = try GlowStore.makeContainer()
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })

        guard let habit = try context.fetch(descriptor).first else { return .result() }
        let count = try HabitStore(context: context).recordTap(for: habit, on: Date())

        let outcome = "ring tap \(id.uuidString): now \(count) of \(habit.timesPerDay)"
        GlowLog.widget.notice("\(outcome, privacy: .public)")
        WidgetTrace.record(outcome)

        // The widget's own timeline is now stale by definition.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
