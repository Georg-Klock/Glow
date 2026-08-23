import AppIntents
import Foundation
import SwiftData

/// The month widget's configuration: which habit it shows.
///
/// In the shared sources, and that is load-bearing: the system consolidates
/// AppIntents metadata under the app, and an intent defined only in the
/// extension configures but never resolves — the stored choice arrives
/// unresolved on every render. Compiled into both targets, the choice
/// round-trips.
///
/// The entity is named `Weekly` because it once shared this app with a per-day
/// kind and a picker that offered it (#209). What it offers now is every habit
/// there is, minus the rows that kind left behind — see `Habit.weekly`. Renaming
/// it is an AppIntents identifier change, which is a stored-configuration
/// migration rather than a rename, so it keeps the name it registered under.
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

    // No `defaultResult()`: a freshly placed widget is seeded by the provider,
    // so it shows something real without the query guessing on the system's
    // behalf.
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

    /// One entry, and a refresh at midnight — the open dot is defined as
    /// "today", so the day rolling over is the only moment a month goes stale
    /// on its own. Every write reloads the timelines explicitly.
    ///
    /// It lived on `TodayStore` and moved here when that went with the per-day
    /// kind (#209). Its one caller is the month provider.
    static func midnight(after now: Date) -> Date {
        WeekCalendar.calendar.date(
            byAdding: .day, value: 1, to: WeekCalendar.day(now)
        ) ?? now.addingTimeInterval(3600)
    }

    private static func offered(in context: ModelContext) -> [Habit] {
        let descriptor = FetchDescriptor<Habit>(
            predicate: Habit.weekly,
            sortBy: [SortDescriptor(\Habit.sortOrder)]
        )
        return offered(among: (try? context.fetch(descriptor)) ?? [])
    }

    /// The same rule, over habits somebody has already fetched.
    ///
    /// The Widgets tab previews the month widget from its own `@Query` rather
    /// than opening a second container to ask (#210), and "which habit does an
    /// unconfigured month widget show" has to be one answer — a preview showing
    /// a different habit than the widget it is a preview of is worse than no
    /// preview. Expects the weekly-cadence habits in the user's order, which is
    /// what the descriptor above and the tab's query both produce.
    static func offered(among habits: [Habit]) -> [Habit] {
        habits.filter { !$0.isSpacer }
    }
}
