import AppIntents
import Foundation
import SwiftData
import WidgetKit

/// Marks today done, or undoes it, from the widget.
///
/// This is what makes the widget worth having: the whole product claim is that
/// logging a habit is one tap, and a widget you have to open the app from is
/// two taps and a launch.
struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Habit"
    static let description = IntentDescription("Marks today's slot done, or undoes it.")

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
        if result == .completed { WidgetBurst.record(habitID: id) }

        let verdict = switch result {
        case .completed: "done"
        case .uncompleted: "undone"
        case .refused: "refused, rest day"
        }
        let outcome = "tap \(id.uuidString): \(verdict), burst \(result == .completed ? "recorded" : "skipped")"
        GlowLog.widget.notice("\(outcome, privacy: .public)")
        WidgetTrace.record(outcome)

        // The widget's own timeline is now stale by definition — and after a
        // refusal it was stale before the tap, which is how the tap happened.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
