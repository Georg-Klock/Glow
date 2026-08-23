import AppIntents
import SwiftUI
import WidgetKit

/// The month widget: one habit's calendar month, small family only.
///
/// The week widget answers "how is this week going" and the Today widget
/// answers "what is left today"; this one answers "am I actually keeping this
/// up", which otherwise lives buried in Settings and shows every habit at
/// once. One habit, chosen per widget — the Today small widget's model — so
/// several of these can sit on one home screen showing different habits.
///
/// Small only, deliberately: one habit's month is one thing to say, and a
/// bigger frame would only invite a second.
struct MonthWidget: Widget {
    let kind = WidgetKind.month.rawValue

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectWeeklyHabitIntent.self,
            provider: MonthProvider()
        ) { entry in
            MonthWidgetView(entry: entry)
                .padding(.leading, WidgetMetrics.padLeading)
                .padding(.trailing, WidgetMetrics.padTrailing)
                .padding(.vertical, WidgetMetrics.padVertical)
                // The same background contract as every other widget here:
                // declared with `containerBackground`, left removable, black
                // only under the Default appearance. See GlowWidget.swift.
                .containerBackground(GlowPalette.widgetBackground, for: .widget)
                // Today's dot acts in place through its intent; everything
                // else opens the app on This Week — the weekly cadence, seen
                // over a longer run.
                .widgetURL(DeepLink.week)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Glow Up: This Month")
        .description("One habit's month. Tap today's dot to log it.")
        .supportedFamilies([.systemSmall])
    }
}

struct MonthEntry: TimelineEntry {
    let date: Date
    /// The habit shown, or nil when there is nothing to show — no weekly
    /// habits at all, or a chosen habit that has since been deleted.
    let habit: HabitSnapshot?
}

struct MonthProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MonthEntry {
        MonthEntry(date: Date(), habit: nil)
    }

    func snapshot(for configuration: SelectWeeklyHabitIntent, in context: Context) async -> MonthEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectWeeklyHabitIntent, in context: Context) async -> Timeline<MonthEntry> {
        let now = Date()
        WidgetTrace.record(
            "month timeline: habit=\(WidgetTrace.tag(configuration.habit?.id))"
        )
        // One entry, and a refresh at midnight: the open dot is defined as
        // "today", and a month only ever changes at a midnight too. Writes
        // reload the timelines explicitly, same as the other widgets.
        return Timeline(
            entries: [entry(for: configuration)],
            policy: .after(MonthStore.midnight(after: now))
        )
    }

    private func entry(for configuration: SelectWeeklyHabitIntent) -> MonthEntry {
        // One habit, one month. Both halves of that used to be paid for
        // whether or not they were drawn: every weekly habit's whole history
        // was projected, and all but one of the results thrown away. See #135.
        let now = Date()
        return MonthEntry(
            date: now,
            habit: MonthStore.month(of: configuration.habit?.id, containing: now)
        )
    }
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
        if let habit = entry.habit {
            month(for: habit)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "circle.dotted")
                    .font(.title2)
                Text("No weekly habits yet")
                    .font(.system(size: WidgetMetrics.textSize))
            }
            .foregroundStyle(GlowPalette.grey)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            let side = SlotLayout.slotHeight(trackWidth: proxy.size.width)
            let gap = SlotLayout.gap(trackWidth: proxy.size.width)
            // Vertical spacing gives way before the cells do: a six-row month
            // tightens rather than overflowing the frame, and a four-row one
            // does not spread to fill it.
            let available = proxy.size.height
                - WidgetMetrics.headerHeight - WidgetMetrics.headerGap
            let rowGap = rows > 1
                ? max(1, min(gap, (available - CGFloat(rows) * side) / CGFloat(rows - 1)))
                : 0

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    // The label follows the week widget's rule: a habit still
                    // waiting on today is the loudest thing in its frame, and
                    // one already handled steps back.
                    if isDue {
                        name.glowing(halo: GlowPalette.labelHalo)
                    } else {
                        name.foregroundStyle(GlowPalette.grey)
                    }
                }
                .frame(height: WidgetMetrics.headerHeight)
                .padding(.bottom, WidgetMetrics.headerGap)

                VStack(alignment: .leading, spacing: rowGap) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { column in
                                MonthCellView(
                                    cell: cells.first { $0.row == row && $0.column == column },
                                    side: side,
                                    habit: habit
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
                Spacer(minLength: 0)
            }
        }
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

    var body: some View {
        if let cell {
            let mark = SlotMarkView(mark: cell.mark, size: CGSize(width: side, height: side))
            if cell.isTappable {
                // Only today: `MonthGrid` asks `WeekGrid` with
                // `SlotEditing.todayOnly`, so this grid edits what every widget
                // surface edits and nothing more (#116). The same intent as the
                // week widget's slot, so the store's rules — including a
                // refusal — cannot differ by surface.
                Button(intent: ToggleHabitIntent(habitID: habit.id)) { mark }
                    .buttonStyle(.plain)
                    .accessibilityLabel(SlotVoice.label(
                        habitName: habit.name, mark: cell.mark, day: cell.date
                    ))
                    .accessibilityHint(SlotVoice.hint(isDone: cell.mark == .doneToday))
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
