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
        TodayStore.perDayNames().map { HabitEntity(id: $0.id, name: $0.name) }
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

/// One query shared by the Today widget's providers and the entity query, so
/// none of them can disagree about which habits a ring can be.
///
/// Two readings of it, because they need different things: the providers draw
/// a ring and need today's count, the picker lists names and needs no history
/// at all.
enum TodayStore {
    /// The per-day habits, in the user's order, with no history read at all.
    ///
    /// The configuration picker lists names (#135). It was calling
    /// `perDayHabits`, which reads every completion of every per-day habit and
    /// projects all of them onto a calendar, and then kept two fields of each
    /// result. The rings and the picker still fetch the same habits in the same
    /// order — that is what `descriptor` being one definition is for — they
    /// simply no longer read the same history.
    static func perDayNames() -> [(id: UUID, name: String)] {
        guard let container = GlowStore.makeReadOnlyContainer() else { return [] }
        let context = ModelContext(container)
        return (try? context.fetch(descriptor))?.map { ($0.id, $0.name) } ?? []
    }

    static func perDayHabits() -> [DayRingSnapshot] {
        let calendar = WeekCalendar.calendar
        let today = WeekCalendar.day(Date(), calendar: calendar)
        guard let container = GlowStore.makeReadOnlyContainer() else { return [] }
        let context = ModelContext(container)
        guard let habits = try? context.fetch(descriptor) else { return [] }

        // A ring is one day's count. Bounded to that day rather than taken off
        // a whole-history snapshot per habit, which is what this did — and a
        // per-day habit is the kind that accumulates rows fastest. See #135.
        let dayID = DayID(today, calendar: calendar)
        let counts = Habit.dayCounts(of: habits, within: dayID...dayID, in: context)
        return habits.map { habit in
            DayRingSnapshot(
                id: habit.id,
                name: habit.name,
                icon: habit.icon,
                target: habit.timesPerDay,
                done: counts[habit.id]?[dayID] ?? 0
            )
        }
    }

    /// The per-day habits, in the user's order. One definition, so the picker
    /// and the rings cannot offer different rows.
    private static let descriptor = FetchDescriptor<Habit>(
        predicate: Habit.countedPerDay,
        sortBy: [SortDescriptor(\Habit.sortOrder)]
    )

    /// One entry, and a refresh at midnight — the count resets with the day,
    /// so the day rolling over is the only moment a ring goes stale on its
    /// own. Every tap reloads the timelines explicitly.
    static func midnight(after now: Date) -> Date {
        WeekCalendar.calendar.date(
            byAdding: .day, value: 1, to: WeekCalendar.day(now)
        ) ?? now.addingTimeInterval(3600)
    }
}
