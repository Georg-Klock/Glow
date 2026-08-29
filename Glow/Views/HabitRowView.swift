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
    ///
    /// **Floored at zero, and that is not defensive padding** (#136). This is a
    /// difference, not a product: the icon and its gap are subtracted from a
    /// label column that a narrow proposal can shrink to nothing, and the
    /// result then goes straight into `.frame(maxWidth:)`. At `totalWidth == 0`
    /// it is −13.5pt, which SwiftUI reports as
    /// `Invalid frame dimension (negative or non-finite)` — a line the suite
    /// has been logging at test-host startup.
    var nameMaxWidth: CGFloat { max(0, labelWidth + labelGap - iconWidth - iconGap) }

    /// A width this can actually divide up.
    ///
    /// A `GeometryReader` proposes zero on its first pass, and `.infinity` and
    /// `.nan` both arrive through layout often enough not to be theoretical.
    /// Non-finite collapses to zero rather than propagating: every value below
    /// is derived from this one, and one `.nan` here becomes a `.nan` in a
    /// frame modifier three properties later, where the warning names no
    /// source.
    private static func usable(_ width: CGFloat) -> CGFloat {
        width.isFinite ? max(0, width) : 0
    }

    init(totalWidth: CGFloat) {
        let width = Self.usable(totalWidth)
        let scale = max(1, width / WidgetMetrics.largeWidth)
        self.scale = scale

        // The label column grows with the user's text size, but never past a
        // point where the track it is stealing from stops being a week.
        let scaledLabel = UIFontMetrics(forTextStyle: .subheadline)
            .scaledValue(for: WidgetMetrics.labelWidth * scale)
        labelWidth = max(0, min(scaledLabel, width * 0.42))

        textSize = UIFontMetrics(forTextStyle: .subheadline)
            .scaledValue(for: WidgetMetrics.textSize * scale)

        let available = width
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

    /// The grid's own corner, where the widget is masked to the system's
    /// squircle and cannot ask for one (#370). The design file's 30, the same
    /// number the Widgets tab draws its previews with.
    static let panelCorner: CGFloat = 30
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
    /// Which days this surface lets a tap touch. The row does not decide it —
    /// the screen does, and hands the same answer to the grid, to the spans and
    /// to the touch resolution below, so all three agree.
    let editing: SlotEditing
    let onToggle: (Date) -> Void
    let onEdit: () -> Void

    /// The rest day, observed — and since #181 this is the *only* read of it on
    /// this screen. The logic no longer looks the value up; it takes it as a
    /// parameter, and this is where the parameter comes from.
    ///
    /// `@AppStorage` rather than `WeekPreferences.restDay` because the row has
    /// to redraw when Settings moves the day, and only a value SwiftUI can see
    /// does that. It is not enough for the property to exist — a row whose slots
    /// did not change was measured keeping the cut line on the old day until
    /// relaunch — it has to be read in `body`, which every use below is.
    @AppStorage(WeekPreferences.restDayKey, store: GlowSettings.store)
    private var restDayStorage: Int = 0

    /// The stored value as a rest day. `WeekPreferences` owns the conversion,
    /// including the clamp; this view owns only the observation.
    private var restDay: Int? { WeekPreferences.restDay(stored: restDayStorage) }

    /// The label dims on exactly the spring the mark closes on, so the row
    /// reads as one movement — which means it has to snap when the mark snaps.
    /// Two timings for one event is two events, and so is one timing and one
    /// jump. See `MotionPolicy` and #137.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the list is being edited, read straight from the environment.
    ///
    /// **A view that *builds* the `NavigationStack` cannot make this read, and
    /// the difference is which side of the stack the view sits on.** For a
    /// struct whose own `body` builds the stack, the `editMode` it reads is its
    /// parent's and never the one the toolbar's edit control toggles, so it has
    /// to own `@State` and inject it instead. The Today screen was the app's
    /// worked example until #209 removed it; the trap it paid for is in
    /// CLAUDE.md. This row is a plain descendant — `WeeklyGridView` builds the
    /// stack, the list and the `ForEach` above it — so it is inside the
    /// environment the button writes to, and reading it here sees the live
    /// value. Measured on the simulator before the fade was built on top of it:
    /// every row and the header flipped on the tap.
    ///
    /// `Binding<EditMode>?`, not `EditMode`, which is why this reads less
    /// directly than an owned copy would.
    @Environment(\.editMode) private var editMode
    private var isEditing: Bool { editMode?.wrappedValue.isEditing ?? false }

    /// How the week leaves when edit mode opens.
    ///
    /// Quick enough to read as getting out of the way rather than as a
    /// transition worth watching — roughly half of `SlotView.close`, which is
    /// this app's number for a change worth noticing. `easeOut` rather than a
    /// spring: nothing here is settling into a resting shape the way a
    /// completion does, it is leaving. The header borrows this timing rather
    /// than keeping its own, so the track and the letters over it go together.
    static let editFade = Animation.easeOut(duration: 0.15)

    private var slots: [Slot] {
        WeekGrid.slots(
            for: snapshot, in: week, today: today, editing: editing, restDay: restDay
        )
    }

    /// A habit due a number of times a week is not day-pinned, so it is drawn as
    /// shapes that stretch across the week rather than as seven columns.
    private var spans: [SlotSpan] {
        guard case .timesPerWeek(let target) = snapshot.frequency else { return [] }
        return WeekSpans.spans(
            for: snapshot, in: week, today: today, target: target,
            editing: editing, restDay: restDay
        )
    }

    private var slotHeight: CGFloat {
        SlotLayout.slotHeight(trackWidth: geometry.trackWidth)
    }

    /// Which column the rest day falls in, or nil for none.
    ///
    /// Derived from the observed value, so a row whose slots did not change
    /// still redraws when Settings moves the day. Called from `body`, which is
    /// what registers the dependency.
    private var restIndex: Int? {
        guard let restDay else { return nil }
        return week.days.firstIndex { WeekPreferences.isRestDay($0, restDay: restDay) }
    }

    var body: some View {
        HStack(spacing: geometry.labelGap) {
            if snapshot.isSpacer {
                // Nothing to draw, but the row still has to exist: it is holding
                // a position in the order, and it needs its height to be
                // draggable and its place to be visible as a gap.
                Color.clear
            } else {
                // Editing gives the week's width back. `List` draws a delete
                // circle at the leading edge and a reorder handle at the
                // trailing one, and the row they land beside has no business
                // still holding seven columns of a week nobody can tap: the
                // marks go, and the name takes the middle of what is left.
                //
                // Two spacers rather than a centred frame, so the label sits
                // between the system's own controls — the room being freed is
                // the room they are standing in, not just the track's.
                if isEditing { Spacer(minLength: 0) }
                label
                if isEditing {
                    Spacer(minLength: 0)
                } else {
                    track
                        .frame(width: geometry.trackWidth, alignment: .leading)
                }
            }
        }
        .frame(height: max(slotHeight, GridMetrics.minimumRowHeight))
        .background(alignment: .leading) { restDayCut }
        // Outside the background, so the cut leaves on the same timing the
        // track does. Reduce Motion takes the snap, as everywhere else the grid
        // moves — the label is also changing width and position here, and a
        // shorter version of that is still a version of it. See `MotionPolicy`.
        .animation(reduceMotion ? nil : Self.editFade, value: isEditing)
        .onAppear { lit = isDue ? 1 : 0 }
        .onChange(of: isDue) { _, due in
            withAnimation(reduceMotion ? nil : SlotView.close) { lit = due ? 1 : 0 }
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
        // Not while the list is being edited: the line is positioned from the
        // same geometry as the track and marks a weekday exactly as the track
        // does, so drawn beside a week that has gone it would point at nothing.
        //
        // `restIndex` reads the observed value, which is what makes every row —
        // including one whose slots are unchanged — redraw the line on the new
        // day the moment Settings moves it.
        if !isEditing,
           let cut, cut.contains(index),
           let restIndex {
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
                .fill(GlowPalette.grey)
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
                        // Which day this column is. These rows are day-pinned —
                        // column N is weekday N — and the row is what knows the
                        // week, so it hands the date down rather than the slot
                        // deriving one. It is what lets a mark say which
                        // Tuesday it is talking about (#137).
                        day: week.days.indices.contains(slot.index)
                            ? week.days[slot.index] : nil,
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
                        // A span covers several columns, so where it was
                        // touched decides which day a tap writes. The geometry
                        // runs backwards in `SlotLayout` and the verdict is
                        // `WeekSpans`'; the view does neither.
                        //
                        // `WeekSpans.day` rather than `SlotEditing.day` because
                        // the verdict depends on the span as well as on the
                        // surface: a filled span is an undo and may only land
                        // on a column that carries a completion (#256).
                        trackWidth: geometry.trackWidth,
                        dayAtColumn: { column in
                            WeekSpans.day(
                                atColumn: column, of: span, for: snapshot, in: week,
                                today: today, editing: editing, restDay: restDay
                            )
                        },
                        onToggle: onToggle
                    )
                }
            }
        }
        .overlay(alignment: .leading) { dots }
    }

    /// Which days this row was logged on, spoken.
    ///
    /// **The dots are gone and this is not** (#344). Their visual job went to
    /// the marks — a completed mark is lit now, so a lit dot on top of it says
    /// the same thing twice — but nothing else tells a screen reader *which*
    /// days a weekly row carried, and the marks say it less well than they
    /// look: one covers several columns. So the string becomes more valuable
    /// as the picture stops carrying it.
    ///
    /// The marks announce how much is left and this says when — so a row with
    /// nothing lit adds no stop to a swipe-through, and a row with three lit
    /// adds one rather than three. See `WeekDots.spokenDays` and #104.
    private var dotVoice: String? {
        WeekDots.spokenDays(for: snapshot, in: week, restDay: restDay)
    }

    /// The days a weekly row was logged on, as one spoken element and nothing
    /// drawn.
    ///
    /// It used to draw a lit dot per logged weekday over the spans (#47). #344
    /// lights the marks themselves, which makes the dots redundant with what is
    /// underneath them — so what is left is the element that was always the
    /// only way VoiceOver reached the days at all.
    ///
    /// `children: .ignore` on the stack rather than a label per day: the days
    /// are one fact. It takes no size, so it sits at the start of the track
    /// instead of covering it and swallowing the marks' own elements.
    @ViewBuilder
    private var dots: some View {
        if !spans.isEmpty {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(dotVoice.map { "\(snapshot.name), \($0)" } ?? "")
                .accessibilityHidden(dotVoice == nil)
        }
    }

    /// Whether this habit is still waiting on today.
    ///
    /// The label follows the slot: a habit with an open slot is the loudest
    /// thing in its row, and one already handled today steps back. Emphasis
    /// tracks "needs you now", not "went well" — a perfect week reads quieter
    /// than a single empty slot, which is the point.
    private var isDue: Bool {
        slots.contains { $0.state == .open } || spans.contains { $0.state == .open }
    }

    /// Handled today: something was asked of this habit today and it was done.
    /// The middle step of §8.5 — a finished row goes quiet rather than dark.
    private var isHandled: Bool {
        TypeTier.isHandled(snapshot, today: today, restDay: restDay)
    }

    /// How lit the label is, 1 through 0. Driven by `isDue` on the same spring
    /// the slot closes on, so the row dims as the ring shuts rather than after.
    @State private var lit: Double = 1

    private var label: some View {
        let text = HStack(spacing: geometry.iconGap) {
            HabitIconView(icon: snapshot.icon, size: geometry.iconSize)
                .frame(width: geometry.iconWidth)
            // **Truncated at the track, never shrunk.** Still never shrunk —
            // text at 12pt that quietly becomes 9pt is worse than text that
            // ends in an ellipsis — but it no longer *overflows* either.
            //
            // `fixedSize(horizontal:)` used to sit here, which makes the text
            // take its full ideal width and ignore the frame below. That was
            // right when it was written: the gap before the track was 15 and a
            // mark was a 3pt dot centred in a 17.455pt slot, so a long name ran
            // into ~22pt of air and, as the old comment put it, "stops short of
            // the grid". #331 took the gap to 4 and #332 made a mark fill its
            // slot, so the air is gone and "Watch Sunset" ran *under the first
            // circle* — measured on a device build.
            //
            // The design file has said truncate all along: its Habit Label
            // component reads "the name ... truncates at 84.5, which is exactly
            // where the track begins", and the frame's width is derived to land
            // exactly there. Dropping `fixedSize` is what lets it.
            Text(snapshot.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: geometry.nameMaxWidth, alignment: .leading)
            // The spacer and the column width below are what hold the name at
            // the leading edge, so editing drops both: a label still filling a
            // label-shaped column would centre that column rather than the
            // name in it, which is not the thing being centred.
            if !isEditing { Spacer(minLength: 0) }
        }
        .font(.system(size: geometry.textSize))

        // The lit label sits over the resting one and its opacity is what
        // moves, rather than the two swapping — a swap is instant, and this has
        // to take exactly as long as the ring takes to close beside it.
        //
        // A due label is full white with a drop shadow in the design, the same
        // thing the marks are. Rendered as bright text it was the one part of
        // the screen pretending to be lit.
        //
        // **Editing is the third rendering, and it is plain white** (#206). The
        // due/not-due crossfade is the light rule applied to type: a name glows
        // because that habit is actionable now. Editing is the one moment that
        // reading stops being the useful one — nobody reordering a list is
        // asking what they are due for — and half the names sitting at `grey`
        // while you try to read them is the cost. So while editing, both layers
        // step aside for a flat `GlowPalette.color`.
        //
        // Flat, not `.glowing`: the halo is this app's vocabulary for lit, the
        // same claim an open ring makes, and wearing it on every row would say
        // every habit is due at once. This is a title's white — the same white
        // as the week's dates above the grid — and it says legible, not lit.
        //
        // `lit` keeps running underneath: it is untouched here, so leaving edit
        // mode returns each name to whatever the crossfade had already settled
        // on rather than re-deriving it.
        return ZStack {
            if isEditing {
                text.foregroundStyle(GlowPalette.color)
            } else {
                // The resting or lit step underneath, with the emitting one
                // crossfaded over it (#335, §8.5). `lit` is the spring that
                // already ran this label; the step below it is what the
                // crossfade lands *on*, and it is the middle tier once the
                // habit has been handled today rather than the resting one.
                //
                // The whole label takes the tier, name and icon together: §8.5
                // is explicit that the two carry the same value in every state,
                // and a glowing name beside a resting icon reads as two facts.
                if isHandled {
                    text.foregroundStyle(GlowPalette.lit)
                } else {
                    text.foregroundStyle(GlowPalette.grey)
                }
                text.glowing(halo: GlowPalette.labelHalo).opacity(lit)
            }
        }
        .frame(width: isEditing ? nil : geometry.labelWidth, alignment: .leading)
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
