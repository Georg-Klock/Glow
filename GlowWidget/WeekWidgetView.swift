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

    @Environment(\.widgetFamily) private var family

    private var rowLimit: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        default: 8
        }
    }

    private var showsLabels: Bool { family != .systemSmall }
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
            .foregroundStyle(GlowPalette.headerRest)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // One measurement for the whole widget, so every row divides the
            // same track by the same rule and the columns line up. Measured once
            // here rather than per row, which is also how the app does it.
            GeometryReader { proxy in
                let track = max(0, proxy.size.width - labelWidth - labelGap)
                let side = SlotLayout.slotHeight(trackWidth: track)

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
                    ForEach(Array(entry.habits.prefix(rowLimit))) { habit in
                        WidgetRow(
                            habit: habit,
                            week: entry.week,
                            today: entry.date,
                            track: track,
                            side: side,
                            labelWidth: labelWidth,
                            labelGap: labelGap,
                            showsLabel: showsLabels,
                            burst: entry.burstHabit == habit.id ? entry.coverage : nil
                        )
                    }
                    if entry.habits.count > rowLimit {
                        Text("+\(entry.habits.count - rowLimit) more")
                            .font(.system(size: WidgetMetrics.textSize))
                            .foregroundStyle(GlowPalette.headerRest)
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
                            letter.foregroundStyle(GlowPalette.headerRest)
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
    /// Non-nil while this habit's completion is animating.
    let burst: Double?

    private var slots: [Slot] {
        WeekGrid.slots(for: habit, in: week, today: today)
    }

    /// A habit due a number of times a week is not day-pinned, so it is drawn as
    /// shapes stretching across the week rather than as seven columns.
    private var spans: [SlotSpan] {
        guard case .timesPerWeek(let target) = habit.frequency else { return [] }
        return WeekSpans.spans(for: habit, in: week, today: today, target: target)
    }

    /// Still waiting on today. The label follows the slot, same rule as the app.
    private var isDue: Bool {
        slots.contains { $0.state == .open } || spans.contains { $0.state == .open }
    }

    var body: some View {
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
                            burst: slot.isTappable ? burst : nil
                        )
                    }
                } else {
                    ForEach(spans) { span in
                        WidgetSpan(span: span, track: track, side: side, habit: habit)
                    }
                }
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
                text.foregroundStyle(GlowPalette.labelResting)
            }
        }
        .frame(width: labelWidth, alignment: .leading)
        // No clipping: the overflow is the point. The frame reserves the
        // column so the track still starts where the design says it does.
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A span on a widget row. Tappable only when it is today's, same rule as a slot.
private struct WidgetSpan: View {
    let span: SlotSpan
    let track: CGFloat
    let side: CGFloat
    let habit: HabitSnapshot

    private var size: CGSize {
        CGSize(
            width: SlotLayout.spanWidth(trackWidth: track, dayCount: span.dayCount),
            height: side
        )
    }

    var body: some View {
        let mark = SlotMarkView(mark: span.mark, size: size, spansDays: span.dayCount > 1)
        if span.isTappable {
            Button(intent: ToggleHabitIntent(habitID: habit.id)) { mark }
                .buttonStyle(.plain)
                .accessibilityLabel("\(habit.name), \(span.state == .filled ? "done" : "due today")")
        } else {
            mark
        }
    }
}

private struct WidgetSlot: View {
    let slot: Slot
    let size: CGSize
    let habitID: UUID
    let habitName: String
    /// Set only on the slot that was just tapped.
    let burst: Double?

    var body: some View {
        // Only today's slot is a button, which is the same rule the app
        // enforces: past days are not editable, so they are not tappable here
        // either. A Button wrapping an untappable slot would still highlight on
        // touch and promise something it does not do.
        if slot.isTappable {
            Button(intent: ToggleHabitIntent(habitID: habitID)) {
                shape
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(habitName), \(slot.state == .filled ? "done" : "due today")")
            .accessibilityHint(slot.state == .filled ? "Mark as not done" : "Mark as done")
        } else {
            shape
        }
    }

    @ViewBuilder
    private var shape: some View {
        if let burst, slot.state == .filled {
            // The app's three beats, sampled. A widget cannot cross-fade across
            // a snapshot boundary, so the burst arrives as a coverage value per
            // entry and the beats snap instead.
            GlowImageView(size: size, shape: burstShape)
        } else {
            // The widget glows. Worth stating plainly, because this project
            // assumed the opposite for a long time and wrote it into the spec as
            // a non-goal: WidgetKit renders out-of-process and archives the
            // result, so HDR was supposed to be impossible here. Measured on an
            // iPhone 14 Pro running the real PQ tile, it is not.
            SlotMarkView(mark: slot.mark, size: size)
        }
    }

    /// Which of the app's three beats this entry is on.
    ///
    /// `WidgetBurst.coverage` is flat at 0 through the hold and then eases to 1,
    /// so zero is the ring still waiting and the rest splits at the halfway
    /// point. Snapping between three shapes rather than cross-fading is not a
    /// compromise made for the widget — a snapshot cannot cross-fade at all, and
    /// at 10fps over one second the beats are what reads anyway.
    private var burstShape: GlowShape {
        guard let burst else { return .dot }
        if burst <= 0 { return .ring }
        return burst < 0.5 ? .capsule : .dot
    }
}
