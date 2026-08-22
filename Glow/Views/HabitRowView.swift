import SwiftUI

/// How the screen is divided and sized: the large widget, scaled to the screen.
///
/// Tapping the widget is meant to land on a bigger version of the same thing,
/// so every measurement here is a `WidgetMetrics` number times one factor —
/// the screen's width over the widget's 338pt. The widget's spec is measured
/// from the design file; the screen has no frame of its own, so it borrows
/// that truth rather than keeping a second set of guesses beside it.
///
/// Computed once per layout and passed to the header and every row, so they
/// cannot disagree. If they did, the columns would stop lining up, which is
/// the one thing the whole screen is for.
///
/// Three deliberate departures, each a considered use of room the widget does
/// not have: text and the label column still grow with Dynamic Type (clamped
/// so the track never stops being a week), rows never shrink below a tappable
/// height, and the header carries dates under its letters.
struct RowGeometry: Equatable {
    /// The screen's width over the large widget's own.
    let scale: CGFloat
    let labelWidth: CGFloat
    let trackWidth: CGFloat
    /// The widget's 12pt, scaled to the screen and then by the user's type
    /// size.
    let textSize: CGFloat

    var horizontalPadding: CGFloat { WidgetMetrics.padLeading * scale }
    var labelGap: CGFloat { WidgetMetrics.labelGap * scale }
    /// Half the widget's row gap, applied above and below each list row.
    var rowInset: CGFloat { WidgetMetrics.rowGap * scale / 2 }
    var iconSize: CGFloat { WidgetMetrics.iconSize / WidgetMetrics.textSize * textSize }
    var iconWidth: CGFloat { WidgetMetrics.iconWidth * scale }
    var iconGap: CGFloat { WidgetMetrics.iconGap * scale }
    /// How far a name may run before truncating: into the gap, never into the
    /// track. The widget's rule, at the screen's scale.
    var nameMaxWidth: CGFloat { labelWidth + labelGap - iconWidth - iconGap }

    init(totalWidth: CGFloat) {
        let scale = max(1, totalWidth / WidgetMetrics.largeWidth)
        self.scale = scale

        // The label column grows with the user's text size, but never past a
        // point where the track it is stealing from stops being a week.
        let scaledLabel = UIFontMetrics(forTextStyle: .subheadline)
            .scaledValue(for: WidgetMetrics.labelWidth * scale)
        labelWidth = min(scaledLabel, max(0, totalWidth * 0.42))

        textSize = UIFontMetrics(forTextStyle: .subheadline)
            .scaledValue(for: WidgetMetrics.textSize * scale)

        let available = totalWidth
            - WidgetMetrics.padLeading * scale * 2
            - labelWidth
            - WidgetMetrics.labelGap * scale
        trackWidth = max(0, available)
    }
}

enum GridMetrics {
    /// Chrome that exists only in the app — the Low Power banner and the empty
    /// state — and so has no widget number to scale from.
    static let horizontalPadding: CGFloat = 20
    /// A floor the widget does not need: its rows are read, these are tapped.
    static let minimumRowHeight: CGFloat = 34
}

/// One habit: icon and name on the left, a fixed-width status track on the right.
struct HabitRowView: View {
    let snapshot: HabitSnapshot
    let week: Week
    let today: Date
    let geometry: RowGeometry
    /// This row's position in the grid, and the range of positions the rest
    /// day's line runs through. Both are needed to draw one segment of it: the
    /// range says whether this row is inside the cut, and which end of it.
    let index: Int
    let cut: ClosedRange<Int>?
    let onToggle: (Date) -> Void
    let onEdit: () -> Void

    /// The rest day, observed. The logic reads the same key through
    /// `WeekPreferences`; the row reads it *here* so the dependency is one
    /// SwiftUI can see. It is not enough for the property to exist — a row
    /// whose slots did not change was measured keeping the cut line on the
    /// old day until relaunch — the value has to be read in `body`, which
    /// `restDayCut` does.
    @AppStorage(WeekPreferences.restDayKey, store: GlowSettings.store)
    private var restDayStorage: Int = 0

    private var slots: [Slot] {
        WeekGrid.slots(for: snapshot, in: week, today: today)
    }

    /// A habit due a number of times a week is not day-pinned, so it is drawn as
    /// shapes that stretch across the week rather than as seven columns.
    private var spans: [SlotSpan] {
        guard case .timesPerWeek(let target) = snapshot.frequency else { return [] }
        return WeekSpans.spans(for: snapshot, in: week, today: today, target: target)
    }

    private var slotHeight: CGFloat {
        SlotLayout.slotHeight(trackWidth: geometry.trackWidth)
    }

    /// Which column the rest day falls in, or nil for none.
    ///
    /// Reads `restDayStorage` rather than `WeekPreferences.restDay` for the
    /// same reason `restDayCut` does: the raw value is what this view observes,
    /// and a row whose slots did not change has to redraw when Settings moves
    /// the day. Called from `body`, which is what registers the dependency.
    private var restIndex: Int? {
        guard restDayStorage != 0 else { return nil }
        return week.days.firstIndex { WeekPreferences.isRestDay($0) }
    }

    var body: some View {
        HStack(spacing: geometry.labelGap) {
            if snapshot.isSpacer {
                // Nothing to draw, but the row still has to exist: it is holding
                // a position in the order, and it needs its height to be
                // draggable and its place to be visible as a gap.
                Color.clear
            } else {
                label
                track
                    .frame(width: geometry.trackWidth, alignment: .leading)
            }
        }
        .frame(height: max(slotHeight, GridMetrics.minimumRowHeight))
        .background(alignment: .leading) { restDayCut }
        .onAppear { lit = isDue ? 1 : 0 }
        .onChange(of: isDue) { _, due in
            withAnimation(SlotView.close) { lit = due ? 1 : 0 }
        }
    }

    /// The rest day cuts the week: one vertical line at that weekday's
    /// x-position, drawn as a segment per row so that the segments meet across
    /// rows and the grid reads as stopped there rather than as seven rows each
    /// carrying their own mark.
    ///
    /// Both ends land on a habit — `RestCut.rows` decides which — and a blank
    /// row between two habits still draws its segment. The line is a cut
    /// through the grid, and a gap the user placed is part of the grid.
    ///
    /// Behind the marks, not over them: a span crossing the rest day is a
    /// record, and the line marks the day, not the record.
    @ViewBuilder
    private var restDayCut: some View {
        // `restDayStorage`, not `WeekPreferences.restDay`: the raw value is
        // what this view observes, and reading it here is what makes every
        // row — including one whose slots are unchanged — redraw the line on
        // the new day the moment Settings moves it.
        if restDayStorage != 0,
           let cut, cut.contains(index),
           let restIndex = week.days.firstIndex(where: { WeekPreferences.isRestDay($0) }) {
            let width = GlowShape.barThickness
            let x = RestCut.x(
                restIndex: restIndex,
                trackWidth: geometry.trackWidth,
                labelWidth: geometry.labelWidth,
                labelGap: geometry.labelGap
            )
            // The row inset above and below, so adjacent segments touch —
            // except at the ends of the cut, where there is no neighbour to
            // meet and the overshoot would run into the header's air or past
            // the last habit.
            let above: CGFloat = index == cut.lowerBound ? 0 : geometry.rowInset
            let below: CGFloat = index == cut.upperBound ? 0 : geometry.rowInset
            let rowHeight = max(slotHeight, GridMetrics.minimumRowHeight)
            Rectangle()
                .fill(GlowPalette.restCut)
                // The span bar's weight, in points. The line is a line, and the
                // completed bar is the line this grid already draws; matching it
                // is what makes the cut read as part of the grid rather than as
                // a heavier ✕. It used to take the missed cross's stroke, which
                // is a *proportion* of the slot and so drew at ~1.2pt on the
                // phone against 2pt bars beside it.
                .frame(width: width, height: rowHeight + above + below)
                // Centred on the column. `.offset(x:)` moves the leading edge,
                // so offsetting by the centre put the whole line half its width
                // to the right of it — invisible at a hairline, a full point off
                // at two.
                .offset(x: x - width / 2, y: (below - above) / 2)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var track: some View {
        HStack(spacing: SlotLayout.gap(trackWidth: geometry.trackWidth)) {
            if spans.isEmpty {
                ForEach(slots) { slot in
                    // The tap lives inside the slot now: it needs touch-down to
                    // grow the ring, and an onTapGesture out here only ever
                    // hears about touch-up.
                    SlotView(
                        slot: slot,
                        size: CGSize(width: slotHeight, height: slotHeight),
                        habitName: snapshot.name,
                        onToggle: onToggle
                    )
                }
            } else {
                ForEach(spans) { span in
                    SpanView(
                        span: span,
                        size: CGSize(
                            width: SlotLayout.spanWidth(
                                trackWidth: geometry.trackWidth,
                                dayCount: span.dayCount
                            ),
                            height: slotHeight
                        ),
                        habitName: snapshot.name,
                        restWindow: RestWindow.inSpan(
                            firstDay: span.firstDay,
                            lastDay: span.lastDay,
                            restIndex: restIndex,
                            trackWidth: geometry.trackWidth
                        ),
                        onToggle: onToggle
                    )
                }
            }
        }
    }

    /// Whether this habit is still waiting on today.
    ///
    /// The label follows the slot: a habit with an open slot is the loudest
    /// thing in its row, and one already handled today steps back. Emphasis
    /// tracks "needs you now", not "went well" — a perfect week reads quieter
    /// than a single empty slot, which is the point.
    private var isDue: Bool {
        slots.contains { $0.state == .open }
    }

    /// How lit the label is, 1 through 0. Driven by `isDue` on the same spring
    /// the slot closes on, so the row dims as the ring shuts rather than after.
    @State private var lit: Double = 1

    private var label: some View {
        let text = HStack(spacing: geometry.iconGap) {
            HabitIconView(icon: snapshot.icon, size: geometry.iconSize)
                .frame(width: geometry.iconWidth)
            // Never shrunk — the widget's rule, adopted. A long name runs on
            // into the gap before the track and truncates only where the grid
            // begins; text that quietly becomes smaller text is worse than
            // text that uses the space beside it.
            Text(snapshot.name)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: geometry.nameMaxWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(.system(size: geometry.textSize))

        // The lit label sits over the resting one and its opacity is what
        // moves, rather than the two swapping — a swap is instant, and this has
        // to take exactly as long as the ring takes to close beside it.
        //
        // A due label is full white with a drop shadow in the design, the same
        // thing the marks are. Rendered as bright text it was the one part of
        // the screen pretending to be lit.
        return ZStack {
            text.foregroundStyle(GlowPalette.labelResting)
            text.glowing(halo: GlowPalette.labelHalo).opacity(lit)
        }
        .frame(width: geometry.labelWidth, alignment: .leading)
        // No clipping: the overflow is the point. The frame reserves the
        // column so the track still starts where the geometry says it does.
        .fixedSize(horizontal: true, vertical: false)
        // The whole label column is the edit target, not just the text. Editing
        // used to live only behind a leftward swipe, which is discoverable if
        // you already know it is there and invisible if you do not.
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        // The slots already announce the habit's name with their own state, so
        // this element says what it *does* rather than repeating the name on
        // its own.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Edit \(snapshot.name)")
        .accessibilityAddTraits(.isButton)
    }
}
