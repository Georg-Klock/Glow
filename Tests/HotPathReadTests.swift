import Foundation
import Testing
@testable import Glow

/// #667: what a row costs to derive, and what the reads under it cost.
///
/// Measured rather than argued, in one process, arms alternated, the first
/// round dropped and the median of the rest reported — the reason is at the top
/// of `HistoryProjectionTests`: two runs measure the machine, not the change.
///
/// Two suspects were named in the issue, and this suite answers both:
///
/// - **The App Group defaults.** `GlowSettings.store` constructs a
///   `UserDefaults(suiteName:)` on every production access, and
///   `WeekCalendar.calendar` reaches it through `WeekPreferences.firstWeekday`
///   each time it is used as a default argument. Under tests the store is the
///   private suite (#168), so the production shape is timed here directly:
///   a fresh suite object per read against one kept instance.
/// - **The row's derivation.** A weekly row's body used to ask
///   `WeekSpans.spans` four times and `WeekGrid.slots` twice; a day-pinned
///   row asked `slots` twice. It now asks each once. The counts are the calls
///   `HabitRowView.body` makes; the functions are the app's own, through the
///   same default calendar the view uses.
@Suite("Hot-path reads")
@MainActor
struct HotPathReadTests {
    private func median(_ values: [Double]) -> Double {
        values.sorted()[values.count / 2]
    }

    private func microseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1e6
            + Double(elapsed.components.attoseconds) / 1e12
    }

    /// Thirty habits, half day-pinned and half weekly, with a few days logged.
    private func habits(in week: Week, today: Date) -> [HabitSnapshot] {
        (0..<30).map { index in
            var counts: [Date: Int] = [:]
            for (column, day) in week.days.enumerated()
            where day < today && (index + column) % 3 == 0 {
                counts[day] = 1
            }
            return HabitSnapshot(
                id: UUID(), name: "Habit \(index)", icon: "book",
                frequency: index.isMultiple(of: 2) ? .daily : .timesPerWeek(1 + index % 6),
                completionCounts: counts, createdDay: nil, targetAtCreation: nil
            )
        }
    }

    @Test("A row derives its marks once per body")
    func aRowDerivesOnce() {
        let today = WeekCalendar.day(Date())
        let week = WeekCalendar.week(containing: today)
        let rows = habits(in: week, today: today)

        func slots(_ habit: HabitSnapshot) -> [Slot] {
            WeekGrid.slots(for: habit, in: week, today: today, editing: .todayOnly, restDay: nil)
        }
        func spans(_ habit: HabitSnapshot) -> [SlotSpan] {
            guard case .timesPerWeek(let target) = habit.frequency else { return [] }
            return WeekSpans.spans(
                for: habit, in: week, today: today, target: target,
                editing: .todayOnly, bonus: .today, restDay: nil
            )
        }

        var sink = 0
        var repeated: [Double] = []
        var once: [Double] = []
        for round in 0..<9 {
            var start = ContinuousClock.now
            for habit in rows {
                for _ in 0..<4 { sink &+= spans(habit).count }
                for _ in 0..<2 { sink &+= slots(habit).count }
            }
            let repeatedTime = microseconds(since: start)

            start = ContinuousClock.now
            for habit in rows {
                sink &+= spans(habit).count
                sink &+= slots(habit).count
            }
            let onceTime = microseconds(since: start)

            if round > 0 {
                repeated.append(repeatedTime)
                once.append(onceTime)
            }
        }
        #expect(sink > 0)

        let before = median(repeated)
        let after = median(once)
        print(
            "L667 medians over 8 rounds, 30 rows (15 weekly, 15 daily): "
                + "spans x4 + slots x2 per row \(before)us, spans x1 + slots x1 per row \(after)us"
        )
        // The shape rather than a number: the machine varies, three fewer
        // derivations a row does not.
        #expect(after * 2 < before)
    }

    @Test("The App Group suite, fresh per read against kept")
    func appGroupSuiteCost() {
        let reads = 10_000
        let kept = UserDefaults(suiteName: StoreLocation.appGroupID) ?? .standard
        var sink = 0
        var fresh: [Double] = []
        var cached: [Double] = []
        var calendar: [Double] = []
        for round in 0..<9 {
            var start = ContinuousClock.now
            for _ in 0..<reads {
                let store = UserDefaults(suiteName: StoreLocation.appGroupID) ?? .standard
                sink &+= (store.object(forKey: WeekPreferences.firstWeekdayKey) as? Int) ?? 1
            }
            let freshTime = microseconds(since: start) / Double(reads)

            start = ContinuousClock.now
            for _ in 0..<reads {
                sink &+= (kept.object(forKey: WeekPreferences.firstWeekdayKey) as? Int) ?? 1
            }
            let cachedTime = microseconds(since: start) / Double(reads)

            start = ContinuousClock.now
            for _ in 0..<reads { sink &+= WeekCalendar.calendar.firstWeekday }
            let calendarTime = microseconds(since: start) / Double(reads)

            if round > 0 {
                fresh.append(freshTime)
                cached.append(cachedTime)
                calendar.append(calendarTime)
            }
        }
        #expect(sink > 0)
        print(
            "L667 medians over 8 rounds, per read: "
                + "fresh App Group suite \(median(fresh))us, kept suite \(median(cached))us, "
                + "WeekCalendar.calendar (test store) \(median(calendar))us"
        )
    }
}
