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
        // **Small is the month** (#322): the one kind's third size draws one
        // habit's calendar, so the small render is `MonthWidgetView` over the
        // entry's month half. A small entry whose month half is missing can
        // only be a provider bug; it wears the unavailable sentence rather
        // than a plausible emptiness, per #282's rule.
        if family == .systemSmall {
            MonthWidgetView(entry: MonthEntry(date: entry.date, habit: entry.month ?? .unavailable))
        } else {
            weekBody
        }
    }

    @ViewBuilder
    private var weekBody: some View {
        // The three answers a read can give, kept apart all the way to the
        // pixels (#282): only a store that was *read* and holds nothing may
        // say "No habits yet". A failed read is a different sentence with a
        // recovery path, not a plausible emptiness.
        switch entry.habits {
        case .unavailable:
            WidgetUnavailableView()
        case .empty:
            VStack(spacing: 6) {
                Image(systemName: "circle.dotted")
                    .font(.title2)
                Text("No habits yet")
                    .font(.system(size: WidgetMetrics.textSize))
            }
            .foregroundStyle(GlowPalette.grey)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let habits):
            grid(habits)
        }
    }

    private func grid(_ habits: [HabitSnapshot]) -> some View {
        // One measurement for the whole widget, so every row divides the
        // same track by the same rule and the columns line up. Measured once
        // here rather than per row, which is also how the app does it.
        GeometryReader { proxy in
            // **The frame's track, which is not always the one drawn on**
            // (#410). A slot used to fall straight out of this, and a slot is a
            // row's height as well as a mark's width — so the row block grew
            // with the frame's width while the room for it grew with the
            // frame's height. Every phone measured is proportionally wider than
            // the design frame, so ten rows overran by half a point to two and
            // the large widget silently drew nine.
            //
            // `rowLayout` lets the height overrule: the slot shrinks by under a
            // percent until the design's rows fit, and the marks bring their
            // column rhythm down with them rather than stretching. What is left
            // over — 0.4 to 1.8pt — stays at the trailing edge, which is why
            // the track drawn on is re-derived from the slot here and handed to
            // every row, the header and the rest day's line alike.
            let frameTrack = max(0, proxy.size.width - labelWidth - labelGap)
            let rows = WidgetMetrics.rowLayout(
                trackWidth: frameTrack,
                contentHeight: proxy.size.height,
                designRows: WidgetMetrics.designRowCount(family, hasHeader: showsHeader),
                hasHeader: showsHeader
            )
            let side = rows.slot
            let track = SlotLayout.trackWidth(dailySlot: side)
            // A medium widget nobody configured spends its measured capacity
            // on habits, not the app's automatic cluster gaps (#496). Large
            // keeps those gaps, and a configured medium keeps a spacer the
            // person explicitly selected. The pure policy stays frame-free;
            // only this view knows both the family and the measured cut.
            let automaticSpacers: WidgetRows.AutomaticSpacers =
                family == .systemMedium && !entry.rowsAreConfigured ? .exclude : .include
            let eligible = WidgetRows.rows(
                from: habits,
                chosen: nil,
                automaticSpacers: automaticSpacers
            )
            // As many as fit, then a hard cut. A row spent saying how much
            // is missing is a row not showing a habit (docs/vision.md).
            // The app marks the boundary in its own grid, which is where
            // there is room to say it.
            let capacity = rows.capacity
            let shown = Array(eligible.prefix(capacity))
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
            let cut = RestCut.rows(eligible, capacity: capacity)

            VStack(alignment: .leading, spacing: WidgetMetrics.rowGap) {
                if showsHeader {
                    WidgetHeader(
                        week: entry.week,
                        today: entry.date,
                        track: track,
                        labelWidth: labelWidth,
                        labelGap: labelGap,
                        anyOpen: TypeTier.anyOpen(
                            in: eligible, week: entry.week, today: entry.date, restDay: restDay
                        )
                    )
                    // The header stands further from the first row than the
                    // rows stand from each other.
                    .padding(.bottom, WidgetMetrics.headerGap - WidgetMetrics.rowGap)
                }
                // **The rows centre in what the header leaves** (#368). The
                // offset is `WidgetMetrics.rowsOffset`, which the render
                // harness also samples by, so the widget and the thing
                // measuring it cannot disagree about where a row is. Where the
                // rows fill the family the offset is zero, which is why a large
                // widget at capacity is untouched.
                VStack(alignment: .leading, spacing: WidgetMetrics.rowGap) {
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
                }
                .padding(.top, WidgetMetrics.rowsOffset(
                    contentHeight: proxy.size.height,
                    slot: side,
                    rows: shown.count,
                    hasHeader: showsHeader
                ))
                // **§8.4's fourth recipe is not drawn here.** It belongs to
                // `Frame 14`, and that frame has no fill, so in the file its
                // inner shadow falls on the union of the marks' own alpha
                // rather than on a panel — the small widget's export settles
                // it, where every socket and every lit fill carries the shade
                // already composited into itself. It lives on the marks now,
                // and since #427 not on all of them: a completion's lit fill
                // carries it at 25% and the ✕ at 48%, and an open or upcoming
                // socket carries none — node `260:2819` draws no third inner
                // shadow there.
                //
                // A `Rectangle` across the track was the misreading: the file
                // has no such shape, and it read as a box drawn around the
                // grid.
            }
            // The stack fills the frame so the rows above have a leftover to
            // centre in; the header stays where it is.
            //
            // **The header does not travel with the rows** (#368). It labels the
            // columns under it, and the family that has one is the family with
            // the most rows — so pinning it costs nothing at capacity and keeps
            // the weekday letters at the top edge, where a person looks for
            // them, rather than floating them down beside a short grid.
            //
            // What replaced a trailing `Spacer(minLength: 0)` is the greedy
            // frame on the rows, not this: a spacer could only ever push the
            // slack downwards, which is why two habits on a medium sat against
            // the top edge with the frame empty under them.
            .frame(
                width: proxy.size.width, height: proxy.size.height, alignment: .topLeading
            )
        }
    }
}

private struct WidgetHeader: View {
    let week: Week
    let today: Date
    let track: CGFloat
    let labelWidth: CGFloat
    let labelGap: CGFloat
    /// Whether anything in the week still wants doing today — the one piece of
    /// state a weekday letter needs that is not its own.
    let anyOpen: Bool

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
                        // Three steps, not two (#335, §8.5). Today's letter
                        // emits only while something is still open; once every
                        // habit is handled it steps down to the lit tier — the
                        // day is still today and still reads as today, it has
                        // simply stopped asking.
                        switch TypeTier.weekday(isToday: isToday, anyHabitOpen: anyOpen) {
                        case .emitting: letter.glowing()
                        case .lit: letter.foregroundStyle(GlowPalette.lit)
                        case .resting: letter.foregroundStyle(GlowPalette.grey)
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

    /// Handled today: something was asked of this habit today and it was done.
    /// The middle step of §8.5, and the reason a finished row is quieter than
    /// an untouched one rather than identical to it.
    private var isHandled: Bool {
        TypeTier.isHandled(habit, today: today, restDay: restDay)
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
            // **The dots are gone; their voice is not** (#344). A completed
            // mark is lit now, so a lit dot drawn on top of one said the same
            // thing twice — but the string is still the only way a screen
            // reader reaches *which* days a weekly row carried, and a mark
            // covering several columns says that less well than it looks. So
            // what is left of the overlay is the element, drawing nothing.
            .overlay(alignment: .leading) {
                let voice = WeekDots.spokenDays(for: habit, in: week, restDay: restDay)
                Color.clear
                    .frame(width: 0, height: 0)
                // One element for the run, no button trait: the days are a
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
        // The field and the row share this width: truncate at the track, never
        // shrink type to make a long name appear to fit (#405, #456).
        let tier = TypeTier.label(isOpenToday: isDue, isHandledToday: isHandled)
        HabitLabelView(
            icon: habit.icon,
            name: habit.name,
            iconSize: WidgetMetrics.iconSize,
            iconWidth: WidgetMetrics.iconWidth,
            iconGap: WidgetMetrics.iconGap,
            textSize: WidgetMetrics.textSize,
            nameMaxWidth: WidgetMetrics.nameMaxWidth,
            // An emitting widget label has no crossfade underneath it. The
            // shared view still supplies an icon-only base for an emoji, which
            // is how its colour survives the name's glow mask (#457).
            baseTier: tier == .emitting ? nil : tier,
            emittingOpacity: tier == .emitting ? 1 : 0
        )
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
            restWindow: restWindow,
            anchorOffset: SlotLayout.anchorOffset(
                trackWidth: track, dayCount: span.dayCount
            )
        )
        let label = SlotVoice.span(
            habitName: habit.name, state: span.state, actionDay: span.actionDay
        )
        if span.isTappable {
            // A `Toggle`, not a `Button` (#292) — see `WidgetSlot`. The two
            // faces are what this span's own two tappable states draw:
            // `.open` is the emitting ask, `.filled` is the lit mark it
            // becomes (#344). So the optimistic frame for a completion is the
            // ring filling at this span's own width; the re-division of the
            // row a write causes arrives with the reload — the toggle owns its
            // own pixels and nothing beside them.
            SlotToggle(
                habitID: habit.id,
                isDone: span.state == .filled,
                onLabel: SlotVoice.span(
                    habitName: habit.name, state: .filled, actionDay: span.actionDay
                ),
                offLabel: SlotVoice.span(
                    habitName: habit.name, state: .open, actionDay: span.actionDay
                )
            ) {
                // **The done face is lit** (#344). It was `.upcoming` — #47's
                // rule written straight into the view rather than read off
                // `span.mark`, which is why lighting the mark alone left this
                // one face dark and only the pixel tests said so.
                SlotMarkView(
                    mark: .donePast,
                    size: size,
                    spansDays: span.dayCount > 1,
                    restWindow: restWindow
                )
            } offMark: {
                SlotMarkView(
                    mark: .openToday,
                    size: size,
                    spansDays: span.dayCount > 1,
                    restWindow: restWindow
                )
            }
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
        // Only today's slot acts, and since #116 that is the widget's own rule
        // rather than the app's: the week view edits any day it shows, and a
        // widget stays a glance and a single confirmed action. A control
        // wrapping an untappable slot would still respond to touch and promise
        // something it does not do.
        //
        // **Every column speaks, tappable or not** (#137). Only two of them did:
        // today's, and the rest day, which #72 gave a voice because it draws
        // nothing. The other five draw a completion, a miss or a day still to
        // come — a week of history, on the surface most people look at most
        // often — and said none of it, while the app's identical row said all
        // of it. Seven dated facts is a row; it is a month and a year of them
        // that get counted into a sentence instead (`HistoryVoice`).
        if slot.isTappable {
            // A `Toggle`, not a `Button` (#292): the system draws the state
            // the tap asked for while the intent runs, instead of holding the
            // old mark until the provider is next scheduled — which #121
            // measured at seconds, and which is what made people tap twice
            // (#272). A tappable slot is today's, so its two faces are today's
            // two marks.
            SlotToggle(
                habitID: habitID,
                isDone: slot.state == .filled,
                onLabel: label(for: .doneToday),
                offLabel: label(for: .openToday)
            ) {
                doneShape
            } offMark: {
                SlotMarkView(mark: .openToday, size: size)
            }
        } else {
            // No control trait and no hint: there is nothing to do here.
            //
            // The widget glows. Worth stating plainly, because this project
            // assumed the opposite for a long time and wrote it into the spec as
            // a non-goal: WidgetKit renders out-of-process and archives the
            // result, so HDR was supposed to be impossible here. Measured on an
            // iPhone 14 Pro running the real PQ tile, it is not.
            SlotMarkView(mark: slot.mark, size: size)
                .accessibilityElement()
                .accessibilityLabel(label(for: slot.mark))
        }
    }

    private func label(for mark: SlotMark) -> String {
        guard let day else { return "\(habitName), \(SlotVoice.state(mark))" }
        return SlotVoice.label(habitName: habitName, mark: mark, day: day)
    }

    /// The completed face: the dot, or the tap's cross-fade arriving at it.
    @ViewBuilder
    private var doneShape: some View {
        if let burst {
            // A cross-fade, not the app's closing spring. The app's ring is
            // one shape whose hole shuts; a widget is a handful of stills,
            // and stills sampled off a spring play back at whatever rate
            // WidgetKit chooses — which read as a stutter, not a snap. Ring
            // out, dot in, still. The two surfaces read as different gestures
            // for the same act, and that is accepted: a gesture that reads
            // wrong is worse than one that reads different.
            //
            // Only on the completed face: the burst rides timeline entries the
            // provider built after a completion, so the slot it describes is
            // `.filled` — the same guard the old single-shape body spelled as
            // `slot.state == .filled`.
            ZStack {
                SlotMarkView(mark: .openToday, size: size).opacity(1 - burst)
                SlotMarkView(mark: .doneToday, size: size).opacity(burst)
            }
        } else {
            SlotMarkView(mark: .doneToday, size: size)
        }
    }

}
