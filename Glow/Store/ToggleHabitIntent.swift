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
        let isNowComplete = try HabitStore(context: context).toggleCompletion(for: habit, on: Date())

        // A tap already costs a timeline reload, so the completion can animate
        // inside the timeline that reload produces. This is the note the
        // provider reads. Only completing animates; un-completing is a
        // correction and should not be celebrated.
        if isNowComplete { WidgetBurst.record(habitID: id) }

        // The widget's own timeline is now stale by definition.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
