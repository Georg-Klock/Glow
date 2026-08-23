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
        WidgetTrace.record(WidgetTrace.resolution("month query", asked: identifiers, got: matched.map(\.id)))
        return matched
    }

    func suggestedEntities() async throws -> [WeeklyHabitEntity] {
        MonthStore.weeklyNames().map { WeeklyHabitEntity(id: $0.id, name: $0.name) }
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

/// One query shared by the month widget's provider and its entity query, so
/// the picker and the render cannot disagree about what is selectable.
///
/// Two readings of it (#135). This used to be a single function returning
/// every weekly habit's whole history, called by a picker that wanted names
/// and by a provider that draws exactly one habit's month. Both now say what
/// they are for: the picker reads no completions, and the provider reads one
/// habit's month.
enum MonthStore {
    /// Every weekly-cadence habit, in the user's order. Blank rows hold a
    /// position in a list and mean nothing in a month, so they are not
    /// offered.
    static func weeklyNames() -> [(id: UUID, name: String)] {
        guard let container = GlowStore.makeReadOnlyContainer() else { return [] }
        let context = ModelContext(container)
        return offered(in: context).map { ($0.id, $0.name) }
    }

    /// The habit this widget shows, over the month `date` falls in.
    ///
    /// `chosenID` is nil on a widget nobody has configured, which shows the
    /// first habit — something real rather than a "choose habit" placeholder.
    /// A chosen habit that has since been deleted resolves to nothing, and the
    /// widget's empty state says so rather than silently becoming a different
    /// habit.
    static func month(
        of chosenID: UUID?, containing date: Date, calendar: Calendar = WeekCalendar.calendar
    ) -> HabitSnapshot? {
        guard let container = GlowStore.makeReadOnlyContainer() else { return nil }
        let context = ModelContext(container)
        let offered = offered(in: context)
        let shown = chosenID.map { id in offered.first { $0.id == id } } ?? offered.first
        guard let shown, let days = MonthGrid.dayRange(containing: date, calendar: calendar)
        else { return nil }
        return Habit.snapshots(of: [shown], within: days, calendar: calendar).first
    }

    private static func offered(in context: ModelContext) -> [Habit] {
        let descriptor = FetchDescriptor<Habit>(
            predicate: Habit.countedPerWeek,
            sortBy: [SortDescriptor(\Habit.sortOrder)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isSpacer }
    }
}
