import SwiftUI
import WidgetKit

/// The widget's grid, laid out to `WidgetMetrics`.
///
/// Deliberately not a reuse of `HabitRowView`. That view is built around a track
/// measured from the screen and rows that can afford a tap target, which is the
/// right model for a full screen and the wrong one for a 155pt square. What the
/// two do share is `SlotLayout`, `SlotMarkView` and `GlowPalette`, so the marks
/// and the column rhythm cannot drift apart between them.
///
/// The large family is the one the design specifies, and its numbers are used
/// literally. Medium and small have no frame, so they keep the same label column
/// and gaps and simply get a narrower track — the slot size falls out of that,
/// which is the same rule the app uses.
struct WeekWidgetView: View {
    let entry: WeekEntry
    /// The render harness's way in: `widgetFamily` is read-only outside
    /// WidgetKit, so a view rendered by `ImageRenderer` always reports medium
    /// and drops the header. Nothing in the widget passes this.
    var familyOverride: WidgetFamily?

    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    /// **Always, since PR #277 dropped Week-Small.** The labels came off at the
    /// small family and nowhere else; with that family gone there is no size
    /// this widget is offered at that hides them. Kept as a computed property
    /// rather than inlined so the two metrics below still read as a pair, and
    /// so restoring a label-less family is one line.
    private var showsLabels: Bool { true }
    /// Only the large family has the height to spend a row on the header.
    private var showsHeader: Bool { family == .systemLarge }

    private var labelWidth: CGFloat { showsLabels ? WidgetMetrics.labelWidth : 0 }
    private var labelGap: CGFloat { showsLabels ? WidgetMetrics.labelGap : 0 }

    var body: some View {
        if entry.habits.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "circle.dotted")
                    .font(.title2)
                Text("No habits yet")
                    .font(.system(size: WidgetMetrics.textSize))
            }
            .foregroundStyle(GlowPalette.grey)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // One measurement for the whole widget, so every row divides the
            // same track by the same rule and the columns line up. Measured once
            // here rather than per row, which is also how the app does it.
            GeometryReader { proxy in
                let track = max(0, proxy.size.width - labelWidth - labelGap)
                let side = SlotLayout.slotHeight(trackWidth: track)
                // As many as fit, then a hard cut. A row spent saying how much
                // is missing is a row not showing a habit (docs/vision.md).
                // The app marks the boundary in its own grid, which is where
                // there is room to say it.
                let capacity = WidgetMetrics.rowCapacity(
                    height: proxy.size.height, slot: side, hasHeader: showsHeader
                )
                let shown = Array(entry.habits.prefix(capacity))
                // **The widget's one read of the rest day** (#181). A widget
                // renders out of process from an archived surface, so there is
                // no `@AppStorage` to observe and nothing to observe it for:
                // the value is read once per render and handed to every row,
                // which is the same shape the app's row uses.
                let restDay = WeekPreferences.restDay
                // The rest day's line, decided once for the whole widget: which
                // column it falls in, and which of the rows it actually shows
                // run through it. Both ends land on a habit — see RestCut.
                let restIndex = entry.week.days.firstIndex(where: {
                    WeekPreferences.isRestDay($0, restDay: restDay)
                })
                let cut = RestCut.rows(entry.habits, capacity: capacity)

                VStack(alignment: .leading, spacing: WidgetMetrics.rowGap) {
                    if showsHeader {
                        WidgetHeader(
                            week: entry.week,
                            today: entry.date,
                            track: track,
                            labelWidth: labelWidth,
                            labelGap: labelGap
                        )
                        // The header stands further from the first row than the
                        // rows stand from each other.
                        .padding(.bottom, WidgetMetrics.headerGap - WidgetMetrics.rowGap)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, habit in
                        WidgetRow(
                            habit: habit,
                            week: entry.week,
                            today: entry.date,
                            track: track,
                            side: side,
                            labelWidth: labelWidth,
                            labelGap: labelGap,
                            showsLabel: showsLabels,
                            index: index,
                            cut: cut,
                            restIndex: restIndex,
                            restDay: restDay,
                            burst: entry.burstHabit == habit.id ? entry.progress : nil
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct WidgetHeader: View {
    let week: Week
    let today: Date
    let track: CGFloat
    let labelWidth: CGFloat
    let labelGap: CGFloat

    private var initials: [String] { WeekCalendar.weekdayInitials() }

    var body: some View {
        HStack(spacing: labelGap) {
            Color.clear.frame(width: labelWidth, height: 1)
            HStack(spacing: SlotLayout.gap(trackWidth: track)) {
                ForEach(0..<7, id: \.self) { index in
                    let isToday = week.days[index] == today
                    let letter = Text(initials[index])
                        .font(.system(size: WidgetMetrics.textSize))

                    Group {
                        // Today's letter is white with a drop shadow in the
                        // design, so it is a glow and not a brighter grey.
                        if isToday {
                            letter.glowing(halo: GlowPalette.headerHalo)
                        } else {
                            letter.foregroundStyle(GlowPalette.grey)
                        }
                    }
                    .frame(width: SlotLayout.slotWidth(trackWidth: track, slotCount: 7))
                }
            }
        }
        .frame(height: WidgetMetrics.headerHeight)
        .accessibilityHidden(true)
    }
}

private struct WidgetRow: View {
    let habit: HabitSnapshot
    let week: Week
    let today: Date
    let track: CGFloat
    let side: CGFloat
    let labelWidth: CGFloat
    let labelGap: CGFloat
    let showsLabel: Bool
    /// This row's position among the rows the widget shows, the range of
    /// positions the rest day's line runs through, and which column it falls
    /// in. All three are decided once for the widget and handed down, so no row
    /// re-derives them and no two rows can disagree. The column carries two
    /// jobs: it places the line, and it is subtracted from any span that
    /// crosses it (`RestWindow`).
    let index: Int
    let cut: ClosedRange<Int>?
    let restIndex: Int?
    /// The weekday nothing is expected on, read once by the widget and handed
    /// down with the rest (#181).
    let restDay: Int?
    /// Non-nil while this habit's completion is animating.
    let burst: Double?

    private var slots: [Slot] {
        // The widget edits today and nothing else, whatever the app can
        // reach — a glance and a single confirmed action. See `SlotEditing`.
        WeekGrid.slots(
            for: habit, in: week, today: today, editing: .todayOnly, restDay: restDay
        )
    }

    /// A habit due a number of times a week is not day-pinned, so it is drawn as
    /// shapes stretching across the week rather than as seven columns.
    private var spans: [SlotSpan] {
        guard case .timesPerWeek(let target) = habit.frequency else { return [] }
        return WeekSpans.spans(
            for: habit, in: week, today: today, target: target,
            editing: .todayOnly, restDay: restDay
        )
    }

    /// Still waiting on today. The label follows the slot, same rule as the app.
    private var isDue: Bool {
        slots.contains { $0.state == .open } || spans.contains { $0.state == .open }
    }

    var body: some View {
        Group {
            if habit.isSpacer {
                // Holds its height and nothing else. It is a gap the user
                // placed — and the rest day's line still crosses it, because
                // the line cuts the grid rather than marking each habit.
                Color.clear.frame(height: side)
            } else {
                row
            }
        }
        .background(alignment: .leading) { restDayCut }
    }

    /// This row's segment of the rest day's line, at the same weight and the
    /// same x the app draws — `RestCut` owns both formulas so the two surfaces
    /// cannot drift apart. Behind the marks, not over them.
    @ViewBuilder
    private var restDayCut: some View {
        if let restIndex, let cut, cut.contains(index) {
            let width = GlowShape.barThickness
            let x = RestCut.x(
                restIndex: restIndex,
                trackWidth: track,
                labelWidth: labelWidth,
                labelGap: labelGap
            )
            // Half the row gap above and below, so adjacent segments touch —
            // except at the ends, where there is no neighbour to meet.
            let above: CGFloat = index == cut.lowerBound ? 0 : WidgetMetrics.rowGap / 2
            let below: CGFloat = index == cut.upperBound ? 0 : WidgetMetrics.rowGap / 2
            Rectangle()
                .fill(GlowPalette.grey)
                .frame(width: width, height: side + above + below)
                // `.offset(x:)` moves the leading edge, so the centre has to
                // have half the width taken off it.
                .offset(x: x - width / 2, y: (below - above) / 2)
                .accessibilityHidden(true)
        }
    }

    private var row: some View {
        HStack(spacing: labelGap) {
            if showsLabel { label }

            HStack(spacing: SlotLayout.gap(trackWidth: track)) {
                if spans.isEmpty {
                    ForEach(slots) { slot in
                        WidgetSlot(
                            slot: slot,
                            size: CGSize(width: side, height: side),
                            habitID: habit.id,
                            habitName: habit.name,
                            // Which day this column is, handed down by the row
                            // exactly as the app's row hands it down. A widget
                            // row and an app row are the same row, so they say
                            // the same seven things (#137).
                            day: week.days.indices.contains(slot.index)
                                ? week.days[slot.index] : nil,
                            burst: slot.isTappable ? burst : nil
                        )
                    }
                } else {
                    ForEach(spans) { span in
                        WidgetSpan(
                            span: span, track: track, side: side, habit: habit,
                            restIndex: restIndex
                        )
                    }
                }
            }
            // A lit dot on each weekday this row was actually logged on, over
            // the spans rather than inside them — a span covers several columns
            // and knows nothing about which of them carried a completion. Same
            // mark and same column centres as a daily row, so the two put their
            // light in exactly the same places. See #47.
            .overlay(alignment: .leading) {
                let voice = WeekDots.spokenDays(for: habit, in: week, restDay: restDay)
                ZStack(alignment: .leading) {
                    ForEach(
                        WeekDots.columns(for: habit, in: week, restDay: restDay), id: \.self
                    ) { column in
                        SlotMarkView(mark: .donePast, size: CGSize(width: side, height: side))
                            .offset(
                                x: SlotLayout.columnCentre(trackWidth: track, index: column)
                                    - side / 2
                            )
                    }
                }
                // One element for the run, no button trait: the dots are a
                // record, and a past day is not tappable here. The app row does
                // the same from the same string. See #104.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(voice.map { "\(habit.name), \($0)" } ?? "")
                .accessibilityHidden(voice == nil)
            }
        }
        .frame(height: side)
    }

    @ViewBuilder
    private var label: some View {
        let text = HStack(spacing: WidgetMetrics.iconGap) {
            HabitIconView(icon: habit.icon, size: WidgetMetrics.iconSize)
                .frame(width: WidgetMetrics.iconWidth)
            // Never shrunk. A name longer than the label column runs on into the
            // gap before the track, which is what the design does: seven of its
            // eight labels clip and the eighth — the only one long enough to
            // need it — does not, so "Watch Sunset" simply overflows and stops
            // short of the grid. Text at 12pt that quietly becomes 9pt is worse
            // than text that uses the space next to it.
            Text(habit.name)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: WidgetMetrics.nameMaxWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(.system(size: WidgetMetrics.textSize))

        Group {
            // Full white with a drop shadow in the design means a real glow, the
            // same rule the marks follow.
            if isDue {
                text.glowing(halo: GlowPalette.labelHalo)
            } else {
                text.foregroundStyle(GlowPalette.grey)
            }
        }
        .frame(width: labelWidth, alignment: .leading)
        // No clipping: the overflow is the point. The frame reserves the
        // column so the track still starts where the design says it does.
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A span on a widget row. Tappable only when it is today's, same rule as a
/// slot — and the widget has no touch location to resolve a column with, which
/// is a second reason its spans write today or nothing (#116).
private struct WidgetSpan: View {
    let span: SlotSpan
    let track: CGFloat
    let side: CGFloat
    let habit: HabitSnapshot
    /// Which column the rest day falls in, decided once by the row.
    let restIndex: Int?

    private var size: CGSize {
        CGSize(
            width: SlotLayout.spanWidth(trackWidth: track, dayCount: span.dayCount),
            height: side
        )
    }

    /// The rest day's column inside this span, or nil when it does not cross
    /// one. See `RestWindow`.
    private var restWindow: ClosedRange<CGFloat>? {
        RestWindow.inSpan(
            firstDay: span.firstDay,
            lastDay: span.lastDay,
            restIndex: restIndex,
            trackWidth: track
        )
    }

    var body: some View {
        let mark = SlotMarkView(
            mark: span.mark,
            size: size,
            spansDays: span.dayCount > 1,
            restWindow: restWindow
        )
        let label = SlotVoice.span(
            habitName: habit.name, state: span.state, actionDay: span.actionDay
        )
        if span.isTappable {
            // `done:` is the complement of what this span drew, so the
            // request is the one the mark was making (#272). A stale surface
            // or a duplicated delivery then asks for the same state twice
            // rather than flipping it back.
            Button(intent: MarkHabitIntent(
                habitID: habit.id, done: span.state != .filled
            )) { mark }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityHint(SlotVoice.hint(isDone: span.state == .filled))
        } else {
            // A span that cannot be tapped is still a share of the week that
            // was drawn, so it is still a share of the week that is said. It
            // was silent here while the app said it — the widget's rows were
            // the tappable column and nothing else (#137).
            mark
                .accessibilityElement()
                .accessibilityLabel(label)
        }
    }
}

private struct WidgetSlot: View {
    let slot: Slot
    let size: CGSize
    let habitID: UUID
    let habitName: String
    /// The calendar day this column stands for. See `SlotVoice`.
    let day: Date?
    /// Set only on the slot that was just tapped.
    let burst: Double?

    var body: some View {
        // Only today's slot is a button, and since #116 that is the widget's
        // own rule rather than the app's: the week view edits any day it shows,
        // and a widget stays a glance and a single confirmed action. A Button
        // wrapping an untappable slot would still highlight on touch and
        // promise something it does not do.
        //
        // **Every column speaks, tappable or not** (#137). Only two of them did:
        // today's, and the rest day, which #72 gave a voice because it draws
        // nothing. The other five draw a completion, a miss or a day still to
        // come — a week of history, on the surface most people look at most
        // often — and said none of it, while the app's identical row said all
        // of it. Seven dated facts is a row; it is a month and a year of them
        // that get counted into a sentence instead (`HistoryVoice`).
        if slot.isTappable {
            Button(intent: MarkHabitIntent(
                habitID: habitID, done: slot.state != .filled
            )) {
                shape
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityHint(SlotVoice.hint(isDone: slot.state == .filled))
        } else {
            // No button trait and no hint: there is nothing to do here.
            shape
                .accessibilityElement()
                .accessibilityLabel(label)
        }
    }

    private var label: String {
        guard let day else { return "\(habitName), \(SlotVoice.state(slot.mark))" }
        return SlotVoice.label(habitName: habitName, mark: slot.mark, day: day)
    }

    @ViewBuilder
    private var shape: some View {
        if let burst, slot.state == .filled {
            // A cross-fade, not the app's closing spring. The app's ring is
            // one shape whose hole shuts; a widget is a handful of stills,
            // and stills sampled off a spring play back at whatever rate
            // WidgetKit chooses — which read as a stutter, not a snap. Ring
            // out, dot in, still. The two surfaces read as different gestures
            // for the same act, and that is accepted: a gesture that reads
            // wrong is worse than one that reads different.
            ZStack {
                SlotMarkView(mark: .openToday, size: size).opacity(1 - burst)
                SlotMarkView(mark: slot.mark, size: size).opacity(burst)
            }
        } else {
            // The widget glows. Worth stating plainly, because this project
            // assumed the opposite for a long time and wrote it into the spec as
            // a non-goal: WidgetKit renders out-of-process and archives the
            // result, so HDR was supposed to be impossible here. Measured on an
            // iPhone 14 Pro running the real PQ tile, it is not.
            SlotMarkView(mark: slot.mark, size: size)
        }
    }

}
