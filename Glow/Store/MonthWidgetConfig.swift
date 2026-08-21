import AppIntents
import Foundation
import SwiftData

/// The month widget's configuration: which weekly-cadence habit it shows.
///
/// In the shared sources for the same load-bearing reason as
/// `TodayWidgetConfig`: the system consolidates AppIntents metadata under the
/// app, and an intent defined only in the extension configures but never
/// resolves — the stored choice arrives unresolved on every render. Compiled
/// into both targets, the choice round-trips.
///
/// A separate entity from `HabitEntity`, not a shared one: the entity type is
/// what binds the picker to its query, and this picker offers the weekly
/// cadences where that one offers the per-day kind. Per-day habits are not
/// selectable here on purpose — their day is a count, not a yes, and a dot
/// meaning "some of the water" would be a third mark state that exists
/// nowhere else.
struct WeeklyHabitEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = WeeklyHabitQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WeeklyHabitQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WeeklyHabitEntity] {
        let matched = try await suggestedEntities().filter { identifiers.contains($0.id) }
        WidgetTrace.record("month query resolve \(identifiers.count) id(s) -> \(matched.map(\.name).joined(separator: ","))")
        return matched
    }

    func suggestedEntities() async throws -> [WeeklyHabitEntity] {
        MonthStore.weeklyHabits().map { WeeklyHabitEntity(id: $0.id, name: $0.name) }
    }

    // No `defaultResult()`, same as the Today widget: a freshly placed widget
    // is seeded by the provider, so it shows something real without the query
    // guessing on the system's behalf.
}

struct SelectWeeklyHabitIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Habit"
    static let description = IntentDescription("Which habit this month shows.")

    @Parameter(title: "Habit")
    var habit: WeeklyHabitEntity?
}

/// One fetch shared by the month widget's provider and its entity query, so
/// the picker and the render cannot disagree about what is selectable.
enum MonthStore {
    /// Every weekly-cadence habit, in the user's order. Blank rows hold a
    /// position in a list and mean nothing in a month, so they are not
    /// offered.
    static func weeklyHabits() -> [HabitSnapshot] {
        guard let container = GlowStore.makeReadOnlyContainer() else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Habit>(
            predicate: Habit.countedPerWeek,
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor))?
            .map { $0.snapshot() }
            .filter { !$0.isSpacer } ?? []
    }
}
