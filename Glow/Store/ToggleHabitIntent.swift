import AppIntents
import Foundation
import UIKit
import SwiftData
import WidgetKit

/// Marks today done, or undoes it, from the widget.
///
/// This is what makes the widget worth having: the whole product claim is that
/// logging a habit is one tap, and a widget you have to open the app from is
/// two taps and a launch.
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
struct ToggleHabitIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Habit"
    static let description = IntentDescription("Marks today's slot done, or undoes it.")

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
        let result = try HabitStore(context: context).toggleCompletion(for: habit, on: Date())

        // A tap already costs a timeline reload, so the completion can animate
        // inside the timeline that reload produces. This is the note the
        // provider reads. Only completing animates; un-completing is a
        // correction and a refusal is nothing at all — neither is celebrated.
        //
        // A refusal can genuinely arrive here: this process runs against a
        // surface that may have been rendered before the rest day was set, so
        // a stale widget can offer a button the store will not honour. The
        // store's answer wins, and the reload below replaces the stale surface.
        if result == .completed {
            // Read here, on the main actor, and carried with the note — see
            // `WidgetBurst.record`.
            WidgetBurst.record(
                habitID: id, reduceMotion: UIAccessibility.isReduceMotionEnabled
            )
            // The completion, and the week's goal on top of it if this was
            // the tap that met it — which of those actually speaks is
            // `PopPreferences`' business, not this call site's (#119).
            //
            // Only on `.completed`, which is what makes un-logging silent: an
            // undo is a correction, and a correction that says "logged" is the
            // app congratulating somebody for taking something back.
            //
            // This is the path the pop is actually seen on: the Island does not
            // render an activity while its own app is in front, so a completion
            // logged in the app fires one nobody looks at, and one logged from
            // the home screen fires one they are already looking at.
            GoalPopCentre.popIfMet(
                habit: habit.snapshot(),
                in: WeekCalendar.week(containing: Date()),
                today: Date()
            )
        }

        let verdict = switch result {
        case .completed: "done"
        case .uncompleted: "undone"
        case .refused: "refused, rest day"
        }
        let outcome = "tap \(id.uuidString): \(verdict), burst \(result == .completed ? "recorded" : "skipped")"
        GlowLog.widget.notice("\(outcome, privacy: .public)")
        WidgetTrace.record(outcome)

        // Explicit, and not redundant with the store's own invalidation: a
        // refusal saves nothing, so nothing would invalidate — and after a
        // refusal the surface was stale *before* the tap, which is how the tap
        // happened. Same mechanism, so the two coalesce. See `WidgetRefresh`.
        WidgetRefresh.invalidate()
        return .result()
    }
}
