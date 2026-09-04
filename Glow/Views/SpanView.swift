import SwiftUI

/// A run of days, and the same completion animation the single slots use.
///
/// The open span and the completed bar are one capsule at two sizes, exactly as
/// the ring and the dot are one circle at two diameters. Hold the stroke at
/// 1.5pt and close the height: the hole is height minus twice the stroke, so it
/// reaches zero at 3 and the outline becomes solid. The width closes too, by the
/// dot's own inset at each end, because a completed run starts where the first
/// day's dot would start rather than at the column's edge.
///
/// Not merged with `SlotView` despite the shared idea. That view animates one
/// number and this one animates two, and folding them together would mean a
/// size-shaped parameter and a branch at every use — more machinery than the
/// eight lines it would save.
struct SpanView: View {
    let span: SlotSpan
    let size: CGSize
    let habitName: String
    /// The rest day's column inside this span, in the span's own coordinates,
    /// or nil when the span does not cross one. Computed by the row from the
    /// track — see `RestWindow` — because the row is what knows the track.
    var restWindow: ClosedRange<CGFloat>?
    /// The whole row's track, which is what turns a touch inside this span into
    /// a column: the span knows where it starts, `SlotLayout` knows how wide a
    /// column is.
    let trackWidth: CGFloat
    /// The day a tap on a given column writes, or nil where that column takes
    /// no write. Supplied by the row from `SlotEditing`, so this view resolves
    /// geometry and asks about policy rather than deciding either.
    let dayAtColumn: (Int) -> Date?
    let onToggle: (Date) -> Void

    /// See `SlotView`: one setting, one rule, four drawings of the same
    /// completion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Non-nil only while a completion is closing.
    @State private var closing: CGSize?

    /// Where the current touch went down, in this span's own coordinates.
    ///
    /// A `Button` reports that it was pressed and not where, and the where is
    /// the whole point on a shape that covers up to seven weekdays. The gesture
    /// is `simultaneous` so the button keeps its own press handling, its
    /// highlight and its accessibility.
    @State private var touchX: CGFloat?

    /// Where a bar sits inside its span: the dot's margin, at each end.
    private var inset: CGFloat { (size.height - GlowShape.dotDiameter) / 2 }

    var body: some View {
        Group {
            if span.isTappable {
                // The span's whole frame, not the line drawn in it — see the
                // note in `SlotView`. It matters more here: an achieved span
                // and one still to come are both a 2pt line across several
                // columns, and both are now tap targets.
                Button { tap() } label: { mark.contentShape(Rectangle()) }
                    .buttonStyle(PressStyle(scale: MotionPolicy.pressScale(
                        SlotView.pressScale, reduceMotion: reduceMotion
                    )))
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { touchX = $0.location.x }
                    )
            } else {
                mark
            }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: span.state) { previous, next in
            transition(from: previous, to: next)
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityAddTraits(span.isTappable ? .isButton : [])
    }

    @ViewBuilder
    private var mark: some View {
        if let closing {
            GlowImageView(
                size: closing,
                shape: .ring,
                ringLineWidth: size.height * GlowShape.ringWeight,
                // The window does not go away for the 600ms — a bar flashing
                // across the cut and then being taken back is worse than never
                // cutting it. It is re-expressed, though: the closing shape is
                // centred in the span's frame and narrower than it, so the
                // window has to be measured from *its* leading edge.
                restWindow: restWindow.map { window in
                    let shift = (size.width - closing.width) / 2
                    return (window.lowerBound - shift)...(window.upperBound - shift)
                }
            )
        } else {
            SlotMarkView(
                mark: span.mark,
                size: size,
                spansDays: span.dayCount > 1,
                restWindow: restWindow,
                flattensSocket: true,
                anchorOffset: SlotLayout.anchorOffset(
                    trackWidth: trackWidth, dayCount: span.dayCount
                )
            )
        }
    }

    /// A day only when the span has one, and never its columns.
    ///
    /// A span covers a run of columns and is not day-pinned — the dots say
    /// which days this row was logged on, once, for the whole row (#47, #104) —
    /// so naming its columns here would announce a date the control does not
    /// act on. What it does name is the day an activation without a location
    /// would touch. See `SlotVoice`.
    private var label: String {
        SlotVoice.span(
            habitName: habitName,
            state: span.state,
            actionDay: span.actionDay,
            completionDay: span.completionDay,
            isBonus: span.isBonus
        )
    }

    /// What a press does — which on a filled span is not always an undo. A met
    /// row's mark covering today offers today as a bonus while today is
    /// unlogged (#560), and `span.actionIsUndo` is what tells the two apart.
    private var hint: String {
        guard let actionDay = span.actionDay else { return "" }
        if span.actionIsUndo { return SlotVoice.hint(isDone: true) }
        if span.state == .filled { return SlotVoice.bonusHint(for: actionDay) }
        return SlotVoice.hint(isDone: false)
    }

    /// Writes the weekday actually touched.
    ///
    /// A span is not day-pinned: it covers a run of columns and carries one
    /// nominal day, so the day a tap means is the column under the finger. The
    /// completion then draws on the day it really happened, which is already
    /// how the month grid renders these habits (#116).
    ///
    /// Two fallbacks, and they are different on purpose:
    ///
    ///  - **The rest column is refused.** `RestWindow` subtracts it from the
    ///    shape, so there is visibly nothing there to press, and pressing a
    ///    hole does nothing here as it does everywhere else.
    ///  - **Any other column this surface will not write** — a future day
    ///    inside the open span, on a week with demo history off — falls back to
    ///    the span's own day. That part of the capsule is drawn lit and
    ///    identical to today's column, and a lit shape that ignores a tap is
    ///    worse than one that does the obvious thing.
    ///
    /// A met row's filled bar goes through the same two steps (#560). Its one
    /// action is today, so today's column resolves to today through
    /// `WeekSpans.day` and every other column falls back to the same day: the
    /// bar has one thing it can do, and it does it wherever it is pressed —
    /// exactly as today's undo already does on a bar that covers other days.
    private func tap() {
        // Taken and cleared: an activation that came from VoiceOver or a
        // keyboard has no location, and must not inherit the last finger's.
        let touchX = touchX
        self.touchX = nil

        if let touchX {
            if let restWindow, restWindow.contains(touchX) { return }
            if let column = SlotLayout.column(
                atX: SlotLayout.columnStart(trackWidth: trackWidth, index: span.firstDay) + touchX,
                trackWidth: trackWidth
            ), let day = dayAtColumn(column) {
                onToggle(day)
                return
            }
        }
        guard let day = span.actionDay else { return }
        onToggle(day)
    }

    private func transition(from previous: SlotState, to next: SlotState) {
        guard MotionPolicy.closesCompletion(
            from: previous, to: next, reduceMotion: reduceMotion
        ) else {
            closing = nil
            return
        }

        closing = size
        withAnimation(SlotView.close) {
            closing = CGSize(
                width: max(0, size.width - inset * 2),
                height: GlowShape.barThickness
            )
        }

        Task {
            try? await Task.sleep(for: SlotView.closeDuration)
            if span.state == .filled { closing = nil }
        }
    }
}
