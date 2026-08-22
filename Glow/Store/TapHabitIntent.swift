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
///
/// **`LiveActivityIntent`, not plain `AppIntent`** (#58). ActivityKit will not
/// start an activity from a widget extension, and this intent has to be able to
/// — logging from the home screen is the *only* case the pop is visible in, for
/// a measured reason: the Dynamic Island does not render an activity while its
/// own app is in the foreground.
///
/// The conformance moves this intent into the app's process. It does **not**
/// bring the app forward, which is the property that had to be measured rather
/// than assumed: the whole point of this intent is that it never leaves the home
/// screen, and that is still true.
struct TapHabitIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log a Repetition"
    static let description = IntentDescription(
        "Adds one to a habit counted through the day. A finished ring starts over."
    )

    /// Deliberately not `openAppWhenRun`. The point is to never leave the home
    /// screen — and `LiveActivityIntent` does not change that: it runs the
    /// intent in the app's process without bringing the app to the foreground.
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

        // Every repetition now, and the goal on top of the one that meets it —
        // which of those actually speaks is `PopPreferences`' business, not
        // this call site's (#119). This is the path the pop is seen on; see
        // `ToggleHabitIntent`.
        //
        // **Except a reset**, which lands here as a count of zero. A full ring
        // tapped again is a correction, and a correction that says "logged" is
        // the app congratulating somebody for undoing something. The toggle
        // path has the same rule for free, because `.uncompleted` never calls
        // this at all.
        if count > 0 {
            GoalPopCentre.popIfMet(
                habit: habit.snapshot(),
                in: WeekCalendar.week(containing: Date()),
                today: Date()
            )
        }

        let outcome = "ring tap \(id.uuidString): now \(count) of \(habit.timesPerDay)"
        GlowLog.widget.notice("\(outcome, privacy: .public)")
        WidgetTrace.record(outcome)

        // The widget's own timeline is now stale by definition. Through
        // `WidgetRefresh` so it coalesces with the store's own invalidation
        // rather than asking twice.
        WidgetRefresh.invalidate()
        return .result()
    }
}
