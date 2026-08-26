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
        try MonthStore.weeklyNames().map { WeeklyHabitEntity(id: $0.id, name: $0.name) }
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
    /// **Throws on a failed read** (#282), for the same reason
    /// `WeekWidgetStore.rowNames` does: the entity query is `async throws`,
    /// and the system's picker showing its own failure beats a sheet silently
    /// claiming there is no habit to choose.
    static func weeklyNames(
        container: ModelContainer? = GlowStore.makeReadOnlyContainer()
    ) throws -> [(id: UUID, name: String)] {
        guard let container else { throw GlowStore.Unreadable() }
        let context = ModelContext(container)
        return offered(among: try context.fetch(offeredDescriptor)).map { ($0.id, $0.name) }
    }

    /// The habit this widget shows, over the month `date` falls in.
    ///
    /// `chosenID` is nil on a widget nobody has configured, which shows the
    /// first habit — something real rather than a "choose habit" placeholder.
    /// A chosen habit that has since been deleted resolves to `empty`, and the
    /// widget's empty state says so rather than silently becoming a different
    /// habit.
    ///
    /// **A failed read is `unavailable`, not an empty month** (#282). Container
    /// and fetch failures both used to come back as nil, indistinguishable
    /// from "no weekly habits yet". `container` is injectable so a test can
    /// hand this the failure the simulator cannot produce on demand.
    static func month(
        of chosenID: UUID?, containing date: Date,
        calendar: Calendar = WeekCalendar.calendar,
        container: ModelContainer? = GlowStore.makeReadOnlyContainer()
    ) -> StoreRead<HabitSnapshot> {
        guard let container else {
            WidgetTrace.record("month: container unavailable")
            return .unavailable
        }
        let context = ModelContext(container)
        do {
            let offered = offered(among: try context.fetch(offeredDescriptor))
            let shown = chosenID.map { id in offered.first { $0.id == id } } ?? offered.first
            guard let shown else { return .empty }
            guard let days = MonthGrid.dayRange(containing: date, calendar: calendar),
                  let snapshot = try Habit.fetchedSnapshots(
                      of: [shown], within: days, calendar: calendar
                  ).first
            else {
                // A habit was there and the month could not be built around
                // it. Saying "no weekly habits yet" about it would be false;
                // unavailable at least points at the app.
                WidgetTrace.record("month: projection failed")
                return .unavailable
            }
            return .loaded(snapshot)
        } catch {
            // Counts and outcomes only, per `WidgetTrace` — never the error's
            // own text, which can carry a path.
            WidgetTrace.record("month: fetch failed")
            return .unavailable
        }
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

    /// One definition for both readers above, so a failure cannot be swallowed
    /// in one of two copies.
    private static let offeredDescriptor = FetchDescriptor<Habit>(
        predicate: Habit.weekly,
        sortBy: [SortDescriptor(\Habit.sortOrder)]
    )

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
