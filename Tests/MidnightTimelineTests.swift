import Foundation
import Testing
@testable import Glow

/// **The row re-flows at midnight, and the widget carries an entry for it**
/// (#345).
///
/// A row is a function of the record and of *today*, so it changes on exactly
/// two events: a completion logged or undone, and the day turning over. The
/// first is a write and writes reload the timeline explicitly. The second had
/// only a reload *policy* behind it — `.after(midnight)` — and a policy is a
/// request WidgetKit obliges when it chooses. Until it does, the Home Screen
/// keeps rendering the entry it was last given, which says today is yesterday.
///
/// The behavioural half is checked here against the real types. The provider
/// itself lives in the widget extension and is not reachable from this bundle,
/// so that half is a source scan — the `TestHostTests` pattern this repository
/// already uses for a claim a test cannot safely watch.
@Suite("Midnight")
struct MidnightTimelineTests {
    private let calendar = TestCalendar.monday

    // MARK: - What actually goes stale

    @Test("Yesterday's open mark is not today's")
    func theOpenMarkMoves() throws {
        // Three a week, nothing logged, and the day turns over from Wednesday
        // to Thursday. The open mark ends on today, so it must end one column
        // further along — an entry still dated Wednesday draws the ring on a
        // day that is over, which is the one thing SPEC §1 forbids.
        let week = WeekCalendar.week(containing: TestCalendar.date(2026, 8, 17), calendar: calendar)
        let habit = HabitSnapshot.fixture(frequency: .timesPerWeek(3))

        func openMark(on column: Int) -> SlotSpan? {
            WeekSpans.spans(
                for: habit, in: week, today: week.days[column], target: 3,
                editing: .todayOnly, bonus: .never, restDay: nil, calendar: calendar
            ).first { $0.state == .open }
        }

        let wednesday = try #require(openMark(on: 2))
        let thursday = try #require(openMark(on: 3))
        #expect(wednesday.lastDay == 2)
        #expect(thursday.lastDay == 3)
        #expect(wednesday.id != thursday.id, "the row did not re-flow")
    }

    @Test("A rep that ran out of days appears at midnight and not before")
    func aDeadRepArrivesAtMidnight() {
        // Five a week, nothing logged. On Wednesday every rep is still
        // reachable; when Wednesday ends, one is not. Nothing was written — the
        // clock moved — which is exactly the change a reload policy alone can
        // be late for.
        let week = WeekCalendar.week(containing: TestCalendar.date(2026, 8, 17), calendar: calendar)
        let habit = HabitSnapshot.fixture(frequency: .timesPerWeek(5))

        func crosses(on column: Int) -> Int {
            WeekSpans.spans(
                for: habit, in: week, today: week.days[column], target: 5,
                editing: .todayOnly, bonus: .never, restDay: nil, calendar: calendar
            ).count { $0.state == .missed }
        }

        #expect(crosses(on: 2) == 0, "a ✕ arrived as a warning")
        #expect(crosses(on: 3) == 1, "the ✕ did not arrive when the day ended")
    }

    @Test("The midnight after the last day of a week is in the next week")
    func midnightCanCrossTheWeek() throws {
        // Why the entry recomputes its week rather than carrying the old one
        // over: on a Sunday the next midnight belongs to a different seven
        // columns, and reusing them would draw the new day against the old week.
        let sunday = TestCalendar.date(2026, 8, 23)
        let week = WeekCalendar.week(containing: sunday, calendar: calendar)
        let midnight = try #require(
            calendar.date(byAdding: .day, value: 1, to: WeekCalendar.day(sunday, calendar: calendar))
        )
        let next = WeekCalendar.week(containing: midnight, calendar: calendar)
        #expect(week.days.last == sunday)
        #expect(next.start != week.start, "the week did not turn over")
        #expect(next.days.first == midnight)
    }

    // MARK: - That the provider carries one

    /// The widget extension's sources, which this bundle cannot import: the
    /// extension is built `APPLICATION_EXTENSION_API_ONLY`, and a provider is
    /// not a type a unit test can construct anyway.
    private var providerSource: String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = root.appendingPathComponent("GlowWidget/GlowWidget.swift")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    @Test("The week timeline is built with a midnight entry, on both paths")
    func theProviderBuildsAMidnightEntry() {
        let source = providerSource
        #expect(!source.isEmpty, "the provider's source was not found")
        #expect(source.contains("private func nextMidnightEntry"),
                "the midnight entry has no builder")
        // Both returns: the still timeline and the burst one. A burst that
        // dropped it would leave the row stale for exactly the taps that
        // touched it.
        let uses = source.components(separatedBy: "nextMidnightEntry(after:").count - 1
        #expect(uses >= 2, "only \(uses) of the two timeline paths carries a midnight entry")
        // The reload policy stays. The entry is what makes the row right
        // without a reload; the policy is what eventually refreshes the record.
        #expect(source.contains("policy: .after(midnight)"),
                "the midnight reload policy went with the change")
    }
}
