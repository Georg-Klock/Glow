import AppIntents
import Foundation
import SwiftData

/// The Today widget's configuration: which habit a small widget shows.
///
/// Lives in the shared sources, not the widget target, and that placement is
/// load-bearing. The app exports AppIntents metadata of its own (the tap and
/// toggle intents), and the system consolidates intent metadata under the app.
/// With this intent defined only in the extension, the configuration sheet
/// worked — it reads the extension's metadata — but the timeline never could:
/// the stored choice arrived unresolved on every render, the entity query was
/// never consulted, and the widget silently fell back to the first habit.
/// Compiled into both targets, the choice round-trips.
struct HabitEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = PerDayHabitQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PerDayHabitQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        let matched = try await suggestedEntities().filter { identifiers.contains($0.id) }
        // Resolution is the step that silently failed under extension-only
        // metadata, so it stays traced for the device check.
        WidgetTrace.record(WidgetTrace.resolution("query", asked: identifiers, got: matched.map(\.id)))
        return matched
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        TodayStore.perDayHabits().map { HabitEntity(id: $0.id, name: $0.name) }
    }

    // No `defaultResult()`. A freshly placed widget is seeded by the provider
    // instead, so an unconfigured widget still shows something real without
    // the query having to guess on the system's behalf.
}

struct SelectHabitIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Habit"
    static let description = IntentDescription("Which habit this ring shows.")

    @Parameter(title: "Habit")
    var habit: HabitEntity?
}

/// One habit's day: what a ring needs and nothing else.
struct DayRingSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let target: Int
    let done: Int
}

/// One fetch shared by the Today widget's providers and the entity query, so
/// none of them can disagree about what a day's ring holds.
enum TodayStore {
    static func perDayHabits() -> [DayRingSnapshot] {
        let today = WeekCalendar.day(Date())
        guard let container = GlowStore.makeReadOnlyContainer() else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Habit>(
            predicate: Habit.countedPerDay,
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor))?.map { habit in
            DayRingSnapshot(
                id: habit.id,
                name: habit.name,
                icon: habit.icon,
                target: habit.timesPerDay,
                done: habit.snapshot().count(on: today)
            )
        } ?? []
    }

    /// One entry, and a refresh at midnight — the count resets with the day,
    /// so the day rolling over is the only moment a ring goes stale on its
    /// own. Every tap reloads the timelines explicitly.
    static func midnight(after now: Date) -> Date {
        WeekCalendar.calendar.date(
            byAdding: .day, value: 1, to: WeekCalendar.day(now)
        ) ?? now.addingTimeInterval(3600)
    }
}
