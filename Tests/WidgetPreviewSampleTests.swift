import Foundation
import Testing
@testable import Glow

/// What the widget gallery advertises (#365).
///
/// The gallery's picture is taken once per install of the extension and cached
/// — re-opening the sheet does not call the provider again — so the sample has
/// to be complete, deterministic and free of any store read. Every test here
/// is one of those three claims.
@Suite("Widget preview sample")
struct WidgetPreviewSampleTests {
    private let calendar = TestCalendar.monday
    /// A Thursday: mid-week, so "before today" and "after today" are both
    /// non-empty and the open column is not at either end.
    private let today = TestCalendar.date(2026, 8, 20)

    private var week: Week { WeekCalendar.week(containing: today, calendar: calendar) }

    private func rows(restDay: Int? = nil) -> [HabitSnapshot] {
        WidgetPreviewSample.rows(
            in: week, today: today, restDay: restDay, calendar: calendar
        )
    }

    @Test("Every offered row is in the sample, blank rows in their places")
    func rowsMirrorTheCuratedSet() {
        let sample = rows()
        #expect(sample.count == DefaultHabits.all.count)
        #expect(sample.map(\.name) == DefaultHabits.all.map(\.name))
        #expect(sample.map(\.isSpacer) == DefaultHabits.all.map(\.isSpacer))
        #expect(sample.map(\.frequency) == DefaultHabits.all.map(\.frequency))
    }

    /// The regression itself. `.empty` and `.unavailable` are what the gallery
    /// drew before this existed — "No habits yet" at the week families and
    /// "Data unavailable" at the small one — and neither is a preview of
    /// anything.
    @Test("The sample is never empty")
    func theSampleHasHabitsInIt() {
        #expect(rows().contains { !$0.isSpacer })
        #expect(!WidgetPreviewSample.month(
            containing: today, restDay: nil, calendar: calendar
        ).name.isEmpty)
    }

    @Test("Something is lit: the sample carries an invented past")
    func theSampleHasCompletionsInTheWeek() {
        #expect(rows().contains { !$0.completedDays.isEmpty })
    }

    /// The open slot is the one thing the widget is *for*, so the sample must
    /// not fill it — the same rule `SeededHistory` states for the demo.
    @Test("Today is never already logged")
    func todayStaysOpen() {
        for habit in rows() {
            #expect(habit.count(on: WeekCalendar.day(today, calendar: calendar)) == 0)
        }
        let month = WidgetPreviewSample.month(
            containing: today, restDay: nil, calendar: calendar
        )
        #expect(month.count(on: WeekCalendar.day(today, calendar: calendar)) == 0)
    }

    @Test("A week row carries only the week it draws")
    func rowsAreBoundedToTheirWeek() {
        for habit in rows() {
            for day in habit.completedDays {
                #expect(week.contains(day), "\(habit.name) carries \(day), outside its week")
            }
        }
    }

    @Test("The month row carries only the month it draws")
    func theMonthIsBoundedToItsGrid() throws {
        let days = try #require(MonthGrid.dayRange(containing: today, calendar: calendar))
        let first = days.lowerBound.date(in: calendar)
        let last = days.upperBound.date(in: calendar)
        let month = WidgetPreviewSample.month(
            containing: today, restDay: nil, calendar: calendar
        )
        #expect(!month.completedDays.isEmpty)
        for day in month.completedDays {
            #expect(day >= first && day <= last, "\(day) is outside the month grid")
        }
    }

    /// The small family draws whichever habit an unconfigured widget resolves
    /// to, so the preview and a freshly placed widget advertise the same one.
    @Test("The month is the first offered habit")
    func theMonthIsTheFirstOfferedHabit() {
        let first = DefaultHabits.all.first { !$0.isSpacer }
        #expect(
            WidgetPreviewSample.month(
                containing: today, restDay: nil, calendar: calendar
            ).name == first?.name
        )
    }

    /// The render is cached, so two calls that disagreed would mean the
    /// picture in the sheet is whichever one happened to be taken.
    @Test("The sample is the same sample every time")
    func theSampleIsDeterministic() {
        #expect(rows() == rows())
        #expect(
            WidgetPreviewSample.month(containing: today, restDay: nil, calendar: calendar)
                == WidgetPreviewSample.month(containing: today, restDay: nil, calendar: calendar)
        )
    }

    /// The rest day arrives as a parameter here like everywhere else in
    /// `Glow/Logic/`, and it has to actually reach the generator — a sample
    /// that logged the rest day would draw completions on a column the app
    /// says nothing is expected on.
    ///
    /// Daily rows only, because that is the claim `SeededHistory` makes: a
    /// `timesPerWeek` past is filled by shuffling the week and taking a count,
    /// which does not consult the rest day.
    @Test("A daily row leaves the rest day clear")
    func theRestDayIsNeverLogged() {
        // Sunday, the last column of a Monday-first week.
        let sample = rows(restDay: 1)
        for habit in sample where habit.frequency == .daily {
            for day in habit.completedDays {
                #expect(
                    !WeekPreferences.isRestDay(day, restDay: 1, calendar: calendar),
                    "\(habit.name) is logged on the rest day"
                )
            }
        }
    }
}
