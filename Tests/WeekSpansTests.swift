import Foundation
import Testing
@testable import Glow

/// The span rule was inferred from three examples in the design file rather
/// than specified. These three tests are those examples, so if the inference is
/// wrong there is one obvious place to correct it.
@Suite("Week spans")
struct WeekSpansTests {
    private let calendar = TestCalendar.monday
    /// Friday of the week beginning Monday 2026-08-17.
    private let friday = TestCalendar.date(2026, 8, 21)
    private var week: Week { WeekCalendar.week(containing: friday, calendar: calendar) }

    private func spans(_ habit: HabitSnapshot, target: Int, today: Date? = nil) -> [SlotSpan] {
        WeekSpans.spans(
            for: habit,
            in: week,
            today: today ?? friday,
            target: target,
            calendar: calendar
        )
    }

    @Test("Two a week, nothing done: the open span runs to today and the rest waits")
    func openSpanEndsAtToday() {
        let row = spans(.fixture(frequency: .timesPerWeek(2)), target: 2)

        #expect(row.count == 2)
        #expect(row[0].state == .open)
        #expect(row[0].firstDay == 0 && row[0].lastDay == 4)  // Monday through Friday
        #expect(row[1].state == .inactive)
        #expect(row[1].firstDay == 5 && row[1].lastDay == 6)  // the weekend
    }

    @Test("Two a week, one done earlier: the open span runs from today to the end")
    func openSpanStartsAtToday() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2),
            completedDays: [TestCalendar.date(2026, 8, 18)]  // Tuesday
        )
        let row = spans(habit, target: 2)

        #expect(row.count == 2)
        #expect(row[0].state == .filled)
        #expect(row[0].firstDay == 0 && row[0].lastDay == 3)  // Monday through Thursday
        #expect(row[1].state == .open)
        #expect(row[1].firstDay == 4 && row[1].lastDay == 6)  // Friday through Sunday
    }

    @Test("Once the goal is met the week stops being divided at all")
    func goalMetIsOneSpan() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(1),
            completedDays: [TestCalendar.date(2026, 8, 18)]
        )
        let row = spans(habit, target: 1)

        #expect(row.count == 1)
        #expect(row[0].state == .filled)
        #expect(row[0].firstDay == 0 && row[0].lastDay == 6)
    }

    // MARK: - The edges the design file did not show

    @Test("The open span always contains today", arguments: 0...6)
    func openSpanContainsToday(dayIndex: Int) {
        let today = week.days[dayIndex]
        for target in 2...6 {
            let row = spans(.fixture(frequency: .timesPerWeek(target)), target: target, today: today)
            guard let open = row.first(where: { $0.state == .open }) else { continue }
            #expect(
                open.firstDay <= dayIndex && dayIndex <= open.lastDay,
                "\(target)x on day \(dayIndex): open span is \(open.firstDay)...\(open.lastDay)"
            )
        }
    }

    @Test("A completion logged today closes the row: nothing is left open")
    func doneTodayLeavesNothingOpen() {
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(3),
            completedDays: [friday]
        )
        let row = spans(habit, target: 3)

        #expect(!row.contains { $0.state == .open })
        // Today's completion is the one a tap undoes.
        #expect(row.filter(\.isTappable).count == 1)
        #expect(row.first(where: \.isTappable)?.state == .filled)
    }

    @Test("Spans tile the week exactly, whatever the day and the target")
    func spansTileTheWeek() {
        // The row is drawn as an HStack of span widths; a gap or an overlap in
        // the day ranges would put every column out of line with the daily rows.
        for dayIndex in 0...6 {
            let today = week.days[dayIndex]
            for target in 2...6 {
                for doneCount in 0...target {
                    let done = Set(week.days.prefix(doneCount))
                    let habit = HabitSnapshot.fixture(
                        frequency: .timesPerWeek(target),
                        completedDays: done
                    )
                    let row = spans(habit, target: target, today: today)
                    guard !row.isEmpty else { continue }

                    #expect(row.first?.firstDay == 0)
                    #expect(row.last?.lastDay == 6)
                    for (a, b) in zip(row, row.dropFirst()) {
                        let detail = "target \(target), day \(dayIndex), done \(doneCount): "
                            + "\(a.firstDay)...\(a.lastDay) then \(b.firstDay)...\(b.lastDay)"
                        #expect(b.firstDay == a.lastDay + 1, "\(detail)")
                    }
                }
            }
        }
    }

    @Test("More completions than the goal do not overflow the row")
    func extraCompletionsClamp() {
        // A habit edited from 5x down to 2x keeps its completions.
        let habit = HabitSnapshot.fixture(
            frequency: .timesPerWeek(2),
            completedDays: Set(week.days.prefix(5))
        )
        let row = spans(habit, target: 2)

        #expect(row.count == 1)
        #expect(row[0].lastDay == 6)
    }
}
