import Foundation
import os.signpost

/// The one bounded history projection feeding every card in the Widgets tab
/// (#478).
///
/// The month grid's range is made of whole weeks, so it already contains the
/// current week. One completion query over that range can therefore feed both
/// week cards and every per-habit month card: the week half is the same
/// snapshots filtered back to seven days, and the month half keeps the shared
/// result whole. Nothing here is a SwiftUI `body`, so a lazy card never opens
/// SwiftData as a side effect of being constructed.
struct WidgetPreviewProjection {
    let weekEntry: WeekEntry
    let monthEntries: [UUID: MonthEntry]
    let unconfiguredMonthEntry: MonthEntry

    func monthEntry(for habitID: UUID?) -> MonthEntry {
        guard let habitID else { return unconfiguredMonthEntry }
        return monthEntries[habitID] ?? MonthEntry(date: weekEntry.date, habit: .empty)
    }
}

/// Holds one projection for one relevant store/day/habit revision.
///
/// This is deliberately a small reference cache owned by `WidgetsView`, not a
/// model cache. The view has the complete invalidation contract: committed
/// writes advance `storeRevision`, `@Query` changes alter the habit
/// fingerprints, and day/week settings are part of the key. Re-evaluating a
/// GeometryReader or a lazy row with the same key therefore returns plain
/// values and performs no fetch.
@MainActor
final class WidgetPreviewProjectionCache {
    typealias Reader = ([Habit], ClosedRange<DayID>) -> [HabitSnapshot]

    private struct HabitFingerprint: Equatable {
        let id: UUID
        let name: String
        let icon: String
        let isDaily: Bool
        let timesPerWeek: Int
        let timesPerDay: Int
        let createdAt: Date
        let targetAtCreation: Int?
        let sortOrder: Int
        let isSpacer: Bool

        init(_ habit: Habit) {
            id = habit.id
            name = habit.name
            icon = habit.icon
            isDaily = habit.isDaily
            timesPerWeek = habit.timesPerWeek
            timesPerDay = habit.timesPerDay
            createdAt = habit.createdAt
            targetAtCreation = habit.targetAtCreation
            sortOrder = habit.sortOrder
            isSpacer = habit.isSpacer
        }
    }

    private struct Key: Equatable {
        let today: Date
        let firstWeekday: Int
        let storeRevision: Int
        let habits: [HabitFingerprint]
    }

    private let read: Reader
    private var cached: (key: Key, projection: WidgetPreviewProjection)?

    /// Tests inject a counting reader at this boundary. The production reader
    /// is the same shared bounded SwiftData pass every other list-shaped
    /// surface uses.
    init(read: @escaping Reader = { habits, days in
        Habit.snapshots(of: habits, within: days)
    }) {
        self.read = read
    }

    func projection(
        habits: [Habit],
        today: Date,
        firstWeekday: Int,
        storeRevision: Int
    ) -> WidgetPreviewProjection {
        let day = WeekCalendar.day(today)
        let key = Key(
            today: day,
            firstWeekday: firstWeekday,
            storeRevision: storeRevision,
            habits: habits.map(HabitFingerprint.init)
        )
        if let cached, cached.key == key { return cached.projection }

        let projection = load(habits: habits, today: day)
        cached = (key, projection)
        return projection
    }

    private func load(habits: [Habit], today: Date) -> WidgetPreviewProjection {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(
            .begin, log: Self.performanceLog, name: "Widgets projection",
            signpostID: signpostID, "habits %d", habits.count
        )
        defer {
            os_signpost(
                .end, log: Self.performanceLog, name: "Widgets projection",
                signpostID: signpostID
            )
        }

        let week = WeekCalendar.week(containing: today)
        let weekDays = week.dayIDs()
        // Every ordinary date has a month range. The week is a truthful,
        // bounded fallback for a calendar that somehow cannot produce one;
        // month entries stay empty in that exceptional state, matching the
        // previous guard rather than drawing an incomplete month.
        let monthDays = MonthGrid.dayRange(containing: today)
        let snapshots = read(habits, monthDays ?? weekDays)

        let weekSnapshots = snapshots.map { snapshot in
            var weekSnapshot = snapshot
            weekSnapshot.completionCounts = snapshot.completionCounts.filter {
                weekDays.contains(DayID($0.key, calendar: WeekCalendar.calendar))
            }
            return weekSnapshot
        }
        let weekEntry = WeekEntry(
            date: today,
            week: week,
            habits: StoreRead(read: weekSnapshots)
        )

        guard monthDays != nil else {
            return WidgetPreviewProjection(
                weekEntry: weekEntry,
                monthEntries: [:],
                unconfiguredMonthEntry: MonthEntry(date: today, habit: .empty)
            )
        }

        let offered = MonthStore.offered(among: habits)
        let offeredIDs = Set(offered.map(\.id))
        var byID: [UUID: HabitSnapshot] = [:]
        for snapshot in snapshots where offeredIDs.contains(snapshot.id) {
            // A corrupt duplicate id must not make a preview crash. The first
            // habit is the one `MonthStore.offered` and the catalog would show.
            if byID[snapshot.id] == nil { byID[snapshot.id] = snapshot }
        }
        let monthEntries = byID.mapValues {
            MonthEntry(date: today, habit: .loaded($0))
        }
        let first = offered.first.flatMap { byID[$0.id] }
        let unconfigured = first.map {
            MonthEntry(date: today, habit: .loaded($0))
        } ?? MonthEntry(date: today, habit: .empty)

        return WidgetPreviewProjection(
            weekEntry: weekEntry,
            monthEntries: monthEntries,
            unconfiguredMonthEntry: unconfigured
        )
    }

    private static let performanceLog = OSLog(
        subsystem: "com.georgklock.glow",
        category: .pointsOfInterest
    )
}
