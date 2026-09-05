import AppIntents
import SwiftUI
import WidgetKit

/// One rendered moment of the month widget.
///
/// Beside the view rather than beside the provider, and for the same reason
/// `WeekEntry` has its own file: the view is compiled without the `@main`
/// bundle — by the render harness (`GlowRenderTests`), and now by the app,
/// whose Widgets tab previews the real widget rather than a drawing of it
/// (#210). The entry is the view's input, so it travels with the view.
struct MonthEntry: TimelineEntry {
    let date: Date
    /// The habit shown, kept as the store answered it (#282): `empty` when
    /// there is genuinely nothing to show — no weekly habits at all, or a
    /// chosen habit that has since been deleted — and `unavailable` when the
    /// store did not answer, which must never wear the empty state's words.
    let habit: StoreRead<HabitSnapshot>
}

/// The habit's name over its month of marks.
///
/// The marks are `SlotMarkView`'s, so the month cannot drift away from the
/// week; which mark a day gets is `MonthGrid`'s, which asks `WeekGrid`. The
/// columns divide the width by the week track's own formula, so a month cell
/// sits in the same rhythm as a week column, one size down.
struct MonthWidgetView: View {
    let entry: MonthEntry

    var body: some View {
        // Empty and unavailable stay two different sentences (#282), exactly
        // as on the week widget.
        switch entry.habit {
        case .unavailable:
            WidgetUnavailableView()
        case .empty:
            VStack(spacing: 6) {
                Image(systemName: "circle.dotted")
                    .font(.title2)
                Text("No weekly habits yet")
                    .font(.system(size: WidgetMetrics.textSize))
            }
            .foregroundStyle(GlowPalette.grey)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let habit):
            month(for: habit)
        }
    }

    private func month(for habit: HabitSnapshot) -> some View {
        let today = WeekCalendar.day(entry.date)
        // The widget's one read of the rest day, as in `WeekWidgetView` (#181):
        // once per render, then passed to the grid and to the cut below.
        let restDay = WeekPreferences.restDay
        let cells = MonthGrid.cells(for: habit, today: today, restDay: restDay)
        let rows = MonthGrid.rowCount(of: cells)
        let isDue = cells.contains { $0.mark == .openToday }

        // The month's history, counted off the same cells the grid draws and
        // hung on the name — which is the one thing here that is already text,
        // and the one thing a VoiceOver user lands on first (#137). Thirty-one
        // dated stops would be a wall; the week widget's seven are a row. See
        // `HistoryVoice`.
        let summary = HistoryVoice.month(cells)
        let name = Text(habit.name)
            .font(.system(size: WidgetMetrics.textSize))
            .lineLimit(1)
            .accessibilityLabel(habit.name)
            .accessibilityValue(summary ?? "")

        return GeometryReader { proxy in
            // The month's own ratio, not the week's (`SlotLayout.monthGapRatio`).
            // Seven 16pt cells on a 20pt pitch fill 136 of track exactly (#553;
            // 19pt and 130 before it). The week's 8-on-24 gave 15.33pt cells
            // 5.11pt apart in the same frame — 4% small and 70% too far apart.
            let side = SlotLayout.monthCell(trackWidth: proxy.size.width)
            let gap = SlotLayout.monthGap(trackWidth: proxy.size.width)
            // Vertical spacing gives way before the cells do: a six-row month
            // tightens rather than overflowing the frame, and a four-row one
            // does not spread to fill it.
            let available = proxy.size.height
                - WidgetMetrics.monthTitleHeight - WidgetMetrics.monthHeaderGap
            let rowGap = rows > 1
                ? max(1, min(gap, (available - CGFloat(rows) * side) / CGFloat(rows - 1)))
                : 0
            // Top-anchored, not centred (2026-09-05): the design puts the first
            // row at 31pt for five rows and six alike and leaves the rest of the
            // frame below, so a short month does not float. #368's centring
            // stays the week widgets' rule through `WidgetMetrics.rowsOffset`.

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    // The label follows the week widget's rule: a habit still
                    // waiting on today is the loudest thing in its frame, and
                    // one already handled steps back.
                    if isDue {
                        name.glowing()
                    } else {
                        name.foregroundStyle(GlowPalette.grey)
                    }
                }
                // Centred in the frame, not flush with the grid's leading edge
                // (#553). The grid below fills the track exactly, so the title
                // is the one thing in this stack with somewhere to go; the
                // week widgets' headers are untouched by this.
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: WidgetMetrics.monthTitleHeight)
                .padding(.bottom, WidgetMetrics.monthHeaderGap)

                VStack(alignment: .leading, spacing: rowGap) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { column in
                                MonthCellView(
                                    cell: cells.first { $0.row == row && $0.column == column },
                                    side: side,
                                    habit: habit,
                                    renderedDay: today
                                )
                            }
                        }
                    }
                }
                // Behind the marks, and behind the whole grid rather than per
                // row: the month has no `RestCut` row range to honour, because
                // every one of its rows is a week and the cut runs through all
                // of them.
                .background(alignment: .leading) {
                    restCut(
                        cells: cells, restDay: restDay,
                        side: side, gap: gap, rows: rows, rowGap: rowGap
                    )
                }
                // Apply the shared row-block offset outside the background.
                // The padding therefore moves the grid and its rest cut as one
                // layout unit without making the cut itself rowsOffset taller
                // (#505). Six rows move only half a point; short months split
                // their otherwise-dead space above and below the block.
                Spacer(minLength: 0)
            }
        }
        .padding(.top, WidgetMetrics.monthTopInset)
    }
}

private extension MonthWidgetView {
    /// The rest day's column, marked the way every other surface marks it.
    ///
    /// #72 emptied this column and left nothing saying why — six or seven blank
    /// cells with no more explanation than a rendering fault would have. The
    /// week grid does not have that problem because it draws the cut, and the
    /// month's columns are weekdays in exactly the same sense, so the same line
    /// says the same thing here (#79).
    ///
    /// Same weight and the same grey: `GlowShape.barThickness` in
    /// `GlowPalette.grey`. What does *not* carry over is `RestCut` itself —
    /// its job is deciding which rows a week grid's line runs through, and here
    /// every row is a week, so the line runs through all of them. The x is the
    /// month's own column pitch rather than `RestCut.x`, which divides a track
    /// after a label column the month does not have.
    @ViewBuilder
    func restCut(
        cells: [MonthCell], restDay: Int?,
        side: CGFloat, gap: CGFloat, rows: Int, rowGap: CGFloat
    ) -> some View {
        if let column = cells.first(where: {
            WeekPreferences.isRestDay($0.date, restDay: restDay)
        })?.column {
            let width = GlowShape.barThickness
            let centre = CGFloat(column) * (side + gap) + side / 2
            Rectangle()
                .fill(GlowPalette.grey)
                .frame(
                    width: width,
                    // The whole grid, first row's top to last row's bottom —
                    // the month's equivalent of ending on a habit.
                    height: CGFloat(rows) * side + CGFloat(max(0, rows - 1)) * rowGap
                )
                // `.offset(x:)` moves the leading edge, so the centre has to
                // have half the width taken off it. Same trap as #71.
                .offset(x: centre - width / 2)
                .accessibilityHidden(true)
        }
    }
}

private struct MonthCellView: View {
    /// Nil outside the month: the first and last rows are ragged, because the
    /// 1st sits under the weekday it really falls on.
    let cell: MonthCell?
    let side: CGFloat
    let habit: HabitSnapshot
    let renderedDay: Date

    var body: some View {
        if let cell {
            let mark = SlotMarkView(mark: cell.mark, size: CGSize(width: side, height: side))
            if cell.isTappable {
                let isToday = cell.date == renderedDay
                let isDone = cell.mark == .doneToday || cell.mark == .donePast
                let doneMark: SlotMark = isToday ? .doneToday : .donePast
                let undoneMark = MonthGrid.undoneMark(
                    for: cell, habit: habit, today: renderedDay
                )
                // The month keeps an exact-date control for today and nothing
                // else (#543, superseding #526). The optimistic `SlotToggle`
                // changes this cell before persistence; its resting face stays
                // `cell.mark`, so interactivity does not move a rendered pixel.
                SlotToggle(
                    habitID: habit.id,
                    isDone: isDone,
                    day: cell.date,
                    renderedDay: renderedDay,
                    onLabel: SlotVoice.label(
                        habitName: habit.name, mark: doneMark, day: cell.date
                    ),
                    offLabel: SlotVoice.label(
                        habitName: habit.name,
                        mark: isDone ? undoneMark : cell.mark,
                        day: cell.date
                    )
                ) {
                    SlotMarkView(mark: doneMark, size: CGSize(width: side, height: side))
                } offMark: {
                    SlotMarkView(
                        mark: isDone ? undoneMark : cell.mark,
                        size: CGSize(width: side, height: side)
                    )
                }
            } else {
                // Still hidden, and now with something saying what they were:
                // the habit's name carries a count of the whole month, so the
                // thirty other cells are spoken once rather than thirty times.
                mark.accessibilityHidden(true)
            }
        } else {
            Color.clear.frame(width: side, height: side)
        }
    }
}
