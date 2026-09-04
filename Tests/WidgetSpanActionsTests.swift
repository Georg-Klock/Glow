import Foundation
import Testing
@testable import Glow

@Suite("Widget span day controls")
struct WidgetSpanActionsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }()

    @Test("An open span exposes a dated control for today only")
    func openSpanHasTodaysAction() throws {
        let monday = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 31
        )))
        let week = WeekCalendar.week(containing: monday, calendar: calendar)
        let today = week.days[2]
        let habit = HabitSnapshot(
            id: UUID(), name: "Stretch", icon: "figure.flexibility",
            frequency: .timesPerWeek(4), completedDays: []
        )
        let span = SlotSpan(
            index: 0, firstDay: 0, lastDay: 2,
            state: .open, actionDay: today
        )

        let actions = WidgetSpanActions.openActions(
            for: span, habit: habit, week: week, today: today,
            restDay: nil, calendar: calendar
        )

        #expect(actions.map(\.column) == [2])
        #expect(actions.map(\.day) == [today])
    }

    @Test("Future and rest columns never receive controls")
    func unavailableColumnsStayInert() throws {
        let monday = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 31
        )))
        let week = WeekCalendar.week(containing: monday, calendar: calendar)
        let today = week.days[2]
        let habit = HabitSnapshot(
            id: UUID(), name: "Stretch", icon: "figure.flexibility",
            frequency: .timesPerWeek(4), completedDays: []
        )
        let span = SlotSpan(
            index: 0, firstDay: 0, lastDay: 6,
            state: .open, actionDay: today
        )

        let actions = WidgetSpanActions.openActions(
            for: span, habit: habit, week: week, today: today,
            restDay: 3, calendar: calendar
        )

        #expect(actions.map(\.column) == [2])
    }

    @Test("Filled spans retain their one completion control")
    func filledSpanDoesNotGainBlankDayActions() throws {
        let monday = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 31
        )))
        let week = WeekCalendar.week(containing: monday, calendar: calendar)
        let habit = HabitSnapshot(
            id: UUID(), name: "Stretch", icon: "figure.flexibility",
            frequency: .timesPerWeek(1), completedDays: [week.days[2]]
        )
        let span = SlotSpan(
            index: 0, firstDay: 0, lastDay: 6,
            state: .filled, actionDay: week.days[2]
        )

        #expect(WidgetSpanActions.openActions(
            for: span, habit: habit, week: week, today: week.days[2],
            restDay: nil, calendar: calendar
        ).isEmpty)
    }
}
