import SwiftData
import SwiftUI

/// The year, as one screen of days. This is History, reached from Settings —
/// the long view is context, not a peer of the week, so it does not spend a
/// tab. It moved here intact; nothing about the drawing changed.
///
/// Columns are weeks, rows are the days of the week in the same order the grid
/// uses, so a horizontal streak is a habit holding and a vertical band is a good
/// week. The same rule as everywhere else decides what is lit: a day glows when
/// everything expected of it was done, and everything else is a flat socket.
///
/// Nothing here is tappable. The year is for looking at — editing a day from
/// four months ago is not a thing this app does, and a grid that responds to
/// touch would promise that it is.
///
/// No `NavigationStack` of its own: it is pushed inside Settings' stack, and
/// a nested stack would swallow the push animation and the back button.
struct YearView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: Habit.countedPerWeek, sort: [SortDescriptor(\Habit.sortOrder)])
    private var habits: [Habit]

    @State private var today = WeekCalendar.day(Date())

    private var calendar: Calendar { WeekCalendar.calendar }

    /// Every week of the current year, as columns of seven days.
    private var weeks: [Week] {
        let year = calendar.component(.year, from: today)
        guard let jan1 = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let dec31 = calendar.date(from: DateComponents(year: year, month: 12, day: 31))
        else { return [] }

        var result: [Week] = []
        var cursor = WeekCalendar.startOfWeek(containing: jan1, calendar: calendar)
        while cursor <= dec31 {
            result.append(WeekCalendar.week(containing: cursor, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Every habit as a value, taken once and handed down.
    ///
    /// This used to be a dictionary of completion sets, rebuilt by the computed
    /// property on every one of the year's 365 cells. The verdict moved to
    /// `YearHistory` (#137) and the snapshots come with it: taken once per
    /// redraw, and read by a dictionary lookup per habit per day rather than by
    /// building a `Set` per habit per day.
    private var snapshots: [HabitSnapshot] { habits.map { $0.snapshot() } }

    /// Spacers hold a position in the grid and nothing else.
    private var realHabits: [Habit] { habits.filter { !$0.isSpacer } }

    private let cell: CGFloat = 10
    private let gap: CGFloat = 3

    var body: some View {
        Group {
            if realHabits.isEmpty {
                ContentUnavailableView {
                    Label("No Habits", systemImage: "square.grid.3x3")
                } description: {
                    Text("A year of days appears here once you are tracking something.")
                }
            } else {
                grid
            }
        }
        .navigationTitle(String(calendar.component(.year, from: today)))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = WeekCalendar.day(Date()) }
        }
    }

    private var grid: some View {
        // Taken once here rather than per cell: `body` is the one place that
        // can read the query, and 365 cells asking it 365 times is what this
        // view used to do.
        let snapshots = self.snapshots
        // The gutter sits outside the scroll view, or it scrolls away and the
        // rows become seven unlabelled bands. Only the weeks scroll, and only
        // horizontally: seven rows always fit.
        return HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                // A width as well as a height: Color.clear given only a height
                // is greedy horizontally and will take half the screen, leaving
                // the grid squeezed into whatever is left.
                Color.clear.frame(width: 10, height: monthLabelHeight)
                weekdayGutter
            }
            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 4) {
                        monthLabels
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                                let fills = YearHistory.fills(
                                    in: week, habits: snapshots,
                                    today: today, calendar: calendar
                                )
                                VStack(spacing: gap) {
                                    ForEach(Array(fills.enumerated()), id: \.offset) { _, fill in
                                        cellView(fill)
                                    }
                                }
                                .id(index)
                                // **The column is the stop** (#137). A year of
                                // days spoke nothing at all: the cells are
                                // `GlowImageView`s and plain `Circle`s, hidden
                                // from accessibility from the inside or
                                // carrying no label at all, and the two
                                // gutters that explain them are hidden on
                                // purpose. Fifty-two sentences is a year
                                // somebody can swipe through; 365 stops
                                // reading "complete" is a wall. A column is
                                // also what the grid is drawn to be read as —
                                // "a vertical band is a good week".
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(HistoryVoice.week(
                                    startingOn: week.start, fills: fills, calendar: calendar
                                ))
                            }
                        }
                    }
                }
                // Opens on this week. Neither end of the year is where anyone is
                // looking: January is history by March and December is empty
                // until it is not.
                .onAppear {
                    guard let index = currentWeekIndex else { return }
                    scroll.scrollTo(index, anchor: .center)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private let monthLabelHeight: CGFloat = 12

    private var currentWeekIndex: Int? {
        weeks.firstIndex { $0.contains(today) }
    }

    /// A month's initial over the first week that begins in it.
    private var monthLabels: some View {
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                // One letter, in exactly a cell's width. A wider label with
                // fixedSize pushes this row past the grid below it and the two
                // stop lining up, which is the only job the row has.
                Text(monthInitial(startingAt: index, week: week))
                    .font(.system(size: 9))
                    .foregroundStyle(GlowPalette.headerRest)
                    .frame(width: cell, height: monthLabelHeight, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }

    private func monthInitial(startingAt index: Int, week: Week) -> String {
        let month = calendar.component(.month, from: week.start)
        guard index > 0 else { return symbol(for: month) }
        let previous = calendar.component(.month, from: weeks[index - 1].start)
        return month == previous ? "" : symbol(for: month)
    }

    private func symbol(for month: Int) -> String {
        let symbols = calendar.shortStandaloneMonthSymbols
        guard symbols.count == 12, (1...12).contains(month) else { return "" }
        return String(symbols[month - 1].prefix(1))
    }

    /// The weekday initials down the left, so a row can be read without counting.
    private var weekdayGutter: some View {
        VStack(spacing: gap) {
            ForEach(Array(WeekCalendar.weekdayInitials(calendar: calendar).enumerated()), id: \.offset) { _, initial in
                Text(initial)
                    .font(.system(size: 8))
                    .foregroundStyle(GlowPalette.headerRest)
                    .frame(width: 10, height: cell, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cellView(_ fill: YearHistory.DayFill) -> some View {
        let size = CGSize(width: cell, height: cell)
        switch fill {
        case .full:
            // The same glow as a completion in the week grid, at a year's scale.
            GlowImageView(size: size, shape: .capsule)
        case .partial:
            Circle().fill(GlowPalette.color.opacity(0.45)).frame(width: cell, height: cell)
        case .empty:
            Circle().fill(GlowPalette.upcoming).frame(width: cell, height: cell)
        case .future:
            Circle().fill(GlowPalette.upcoming.opacity(0.4)).frame(width: cell, height: cell)
        }
    }
}
