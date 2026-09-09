import Foundation
import Testing
@testable import Glow

/// What an open widget pill offers, and to which day.
///
/// **Two of these tests used to assert the bug** (#614). They pinned
/// `actions.map(\.column) == [2]` — one control, on today's own column — and
/// read as a statement about the editing policy. They were really a statement
/// about a projection that asked the wrong question per column: with
/// `SlotEditing` down to its single `.todayOnly` case, only today's column
/// could ever answer, so every other zone of a multi-day pill came back with
/// no control and fell through to WidgetKit's "open the app".
///
/// The policy they were guarding is untouched and still guarded, by the
/// assertion that matters: **every action writes today and no other day.**
/// What changed is how many zones carry it.
@Suite("Widget span day controls")
struct WidgetSpanActionsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Monday 31 August 2026, so column 0 is a Monday and column 2 is the
    /// Wednesday every test below treats as today.
    private func week() throws -> Week {
        let monday = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 31
        )))
        return WeekCalendar.week(containing: monday, calendar: calendar)
    }

    private func habit(createdDay: Date? = nil) -> HabitSnapshot {
        HabitSnapshot(
            id: UUID(), name: "Stretch", icon: "figure.flexibility",
            frequency: .timesPerWeek(4), completionCounts: [:], createdDay: createdDay
        )
    }

    @Test("Every column of an open span carries a control")
    func openSpanCoversItsWholeWidth() throws {
        let week = try week()
        let today = week.days[2]
        let span = SlotSpan(index: 0, firstDay: 0, lastDay: 2, state: .open, actionDay: today)

        let actions = WidgetSpanActions.openActions(
            for: span, habit: habit(), week: week, today: today,
            restDay: nil, calendar: calendar
        )

        // The pill is drawn across three columns, so it acts across three.
        // Monday's and Tuesday's zones had no control at all before this.
        #expect(actions.map(\.column) == [0, 1, 2])
        #expect(actions.allSatisfy { $0.day == today })
    }

    @Test("Every zone of the pill writes today, whichever zone was pressed")
    func everyZoneWritesToday() throws {
        let week = try week()
        let today = week.days[2]
        // Tuesday rests — column 1, inside the span.
        let span = SlotSpan(index: 0, firstDay: 0, lastDay: 6, state: .open, actionDay: today)

        let actions = WidgetSpanActions.openActions(
            for: span, habit: habit(), week: week, today: today,
            restDay: 3, calendar: calendar
        )

        #expect(actions.map(\.column) == Array(0...6))
        // The point of the whole projection: no zone can write a past day, a
        // future day or the rest day. A control over Friday's pixels still
        // logs Wednesday.
        #expect(Set(actions.map(\.day)) == [today])
        // Including the rest day's own column. Its notch is still drawn; the
        // write it takes is today's, and today is not the rest day.
        #expect(actions.contains { $0.column == 1 })
    }

    @Test("A span with no writable day offers nothing at all")
    func todayRestingOffersNothing() throws {
        let week = try week()
        let today = week.days[2]
        let span = SlotSpan(index: 0, firstDay: 0, lastDay: 6, state: .open, actionDay: today)

        // Wednesday is the rest day, and Wednesday is today: the one day this
        // span could have written is refused, so the pill is inert rather than
        // covered in controls that write nothing.
        #expect(WidgetSpanActions.openActions(
            for: span, habit: habit(), week: week, today: today,
            restDay: 4, calendar: calendar
        ).isEmpty)
    }

    @Test("A span in a week the habit did not live in offers nothing")
    func spanBeforeTheHabitExistedOffersNothing() throws {
        let week = try week()
        let today = week.days[2]
        let span = SlotSpan(index: 0, firstDay: 0, lastDay: 6, state: .open, actionDay: today)

        #expect(WidgetSpanActions.openActions(
            for: span, habit: habit(createdDay: week.days[5]), week: week,
            today: today, restDay: nil, calendar: calendar
        ).isEmpty)
    }

    @Test("Filled spans retain their one completion control")
    func filledSpanDoesNotGainBlankDayActions() throws {
        let week = try week()
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
