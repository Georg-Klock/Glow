import Foundation
import Testing
@testable import Glow

@Suite("Month grid", .serialized)
struct MonthGridTests {
    private let calendar = TestCalendar.monday
    /// Wednesday. August 2026 runs Saturday the 1st through Monday the 31st,
    /// so the month is ragged at both ends and spans six rows — the awkward
    /// case, which is why it is the fixture.
    private let today = TestCalendar.date(2026, 8, 19)

    /// Same discipline as WeekPreferencesTests: these write to the App Group's
    /// defaults, restored after each test so no later suite inherits them.
    private func withRestDay(_ restDay: Int?, _ body: () throws -> Void) rethrows {
        let previous = WeekPreferences.restDay
        defer { WeekPreferences.restDay = previous }
        WeekPreferences.restDay = restDay
        try body()
    }

    @Test("The 1st sits under its real weekday, and the rows are ragged")
    func monthShape() {
        let cells = MonthGrid.cells(for: .fixture(), today: today, calendar: calendar)

        #expect(cells.count == 31)
        #expect(MonthGrid.rowCount(of: cells) == 6)

        // Saturday the 1st: column 5 under a Monday-first week, top row.
        let first = cells.first { calendar.component(.day, from: $0.date) == 1 }
        #expect(first?.row == 0)
        #expect(first?.column == 5)

        // Monday the 31st: column 0, alone on the last row.
        let last = cells.first { calendar.component(.day, from: $0.date) == 31 }
        #expect(last?.row == 5)
        #expect(last?.column == 0)
        #expect(cells.count { $0.row == 5 } == 1)
    }

    @Test("A daily habit's month is the week grid's verdicts, day by day")
    func dailyMarks() {
        let done = TestCalendar.date(2026, 8, 10)
        let habit = HabitSnapshot.fixture(completedDays: [done])
        let cells = MonthGrid.cells(for: habit, today: today, calendar: calendar)
        let byDay = { (day: Int) in
            cells.first { self.calendar.component(.day, from: $0.date) == day }
        }

        #expect(byDay(10)?.mark == .donePast)
        // Yesterday, unlogged: a daily habit misses.
        #expect(byDay(18)?.mark == .missed)
        // Today, unlogged: the one open — and the one tappable — cell.
        #expect(byDay(19)?.mark == .openToday)
        #expect(byDay(19)?.isTappable == true)
        #expect(cells.count(where: \.isTappable) == 1)
        // Still to come.
        #expect(byDay(25)?.mark == .upcoming)
    }

    @Test("A rest day draws nothing in the month either")
    func restDayInheritsFromTheWeekGrid() {
        // Tuesday the 18th went unlogged; as the rest day it draws nothing —
        // not a cross, and since #72 not a socket either. Not re-decided here:
        // MonthGrid asks WeekGrid, so whatever the rest day means there is
        // what it means here, and the whole Tuesday column empties with it.
        withRestDay(calendar.component(.weekday, from: TestCalendar.date(2026, 8, 18))) {
            let cells = MonthGrid.cells(for: .fixture(), today: today, calendar: calendar)
            let tuesday = cells.first { calendar.component(.day, from: $0.date) == 18 }
            #expect(tuesday?.mark == .rest)

            // Every Tuesday, not only the one asked about — the column is the
            // shape a reader sees, and one blank cell among six sockets would
            // read as a bug rather than as a rest day.
            let tuesdays = cells.filter {
                calendar.component(.weekday, from: $0.date)
                    == calendar.component(.weekday, from: TestCalendar.date(2026, 8, 18))
            }
            #expect(tuesdays.count >= 4)
            #expect(tuesdays.allSatisfy { $0.mark == .rest })
            #expect(tuesdays.allSatisfy { !$0.isTappable })
        }
    }

    @Test("An N-per-week habit's empty days are sockets, never crosses")
    func frequencyNeverMisses() {
        // The open question the issue records — whether a month should carry a
        // per-week verdict — is deliberately not answered here. What is
        // asserted is the week grid's own rule carried over: an empty Monday
        // is not a failure on Tuesday, so no day of an N×/week habit is ever
        // drawn missed.
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3),
            completedDays: [TestCalendar.date(2026, 8, 10), TestCalendar.date(2026, 8, 12)]
        )
        let cells = MonthGrid.cells(for: habit, today: today, calendar: calendar)

        #expect(!cells.contains { $0.mark == .missed })
        #expect(cells.count { $0.mark == .donePast } == 2)
        // This week holds nothing yet, so today is open by the week row's own
        // verdict, and it is the only tappable cell.
        let todayCell = cells.first { $0.date == today }
        #expect(todayCell?.mark == .openToday)
        #expect(cells.count(where: \.isTappable) == 1)
    }

    @Test("A met week closes today, and a completion today can be undone")
    func frequencyFollowsTheWeekVerdict() {
        // Goal met this week without today: nothing open, nothing tappable.
        let monday = TestCalendar.date(2026, 8, 17)
        let tuesday = TestCalendar.date(2026, 8, 18)
        let met = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2), completedDays: [monday, tuesday]
        )
        let metCells = MonthGrid.cells(for: met, today: today, calendar: calendar)
        #expect(!metCells.contains { $0.mark == .openToday })
        #expect(metCells.allSatisfy { !$0.isTappable })

        // Done today: the mark says so, and the tap is the undo — the same
        // rule the week row applies to its own pill.
        let doneToday = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3), completedDays: [today]
        )
        let doneCells = MonthGrid.cells(for: doneToday, today: today, calendar: calendar)
        let todayCell = doneCells.first { $0.date == today }
        #expect(todayCell?.mark == .doneToday)
        #expect(todayCell?.isTappable == true)
    }

    @Test("Per-day habits and blank rows have no month")
    func backstops() {
        let perDay = HabitSnapshot.fixture(frequency: .timesPerDay(3))
        #expect(MonthGrid.cells(for: perDay, today: today, calendar: calendar).isEmpty)

        let spacer = HabitSnapshot.fixture(isSpacer: true)
        #expect(MonthGrid.cells(for: spacer, today: today, calendar: calendar).isEmpty)
    }
}
