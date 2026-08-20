import SwiftUI

/// How the screen is divided horizontally.
///
/// Computed once per layout and passed to the header and every row, so they
/// cannot disagree. If they did, the columns would stop lining up, which is the
/// one thing the whole screen is for.
struct RowGeometry: Equatable {
    let labelWidth: CGFloat
    let trackWidth: CGFloat

    init(totalWidth: CGFloat) {
        // The label column grows with the user's text size, but never past a
        // point where the track it is stealing from stops being a week.
        let scaled = UIFontMetrics(forTextStyle: .subheadline)
            .scaledValue(for: GridMetrics.baseLabelWidth)
        labelWidth = min(scaled, max(0, totalWidth * 0.42))

        let available = totalWidth
            - GridMetrics.horizontalPadding * 2
            - labelWidth
            - GridMetrics.labelSpacing
        trackWidth = max(0, available)
    }
}

enum GridMetrics {
    static let baseLabelWidth: CGFloat = 116
    static let labelSpacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 20
    static let rowSpacing: CGFloat = 16
    static let minimumRowHeight: CGFloat = 34
}

/// One habit: icon and name on the left, a fixed-width status track on the right.
struct HabitRowView: View {
    let snapshot: HabitSnapshot
    let week: Week
    let today: Date
    let geometry: RowGeometry
    let onToggle: (Date) -> Void
    let onEdit: () -> Void

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

    var body: some View {
        HStack(spacing: GridMetrics.labelSpacing) {
            label
            track
                .frame(width: geometry.trackWidth, alignment: .leading)
        }
        .frame(height: max(slotHeight, GridMetrics.minimumRowHeight))
    }

    @ViewBuilder
    private var track: some View {
        HStack(spacing: SlotLayout.gap(trackWidth: geometry.trackWidth)) {
            if spans.isEmpty {
                ForEach(slots) { slot in
                    SlotView(
                        slot: slot,
                        size: CGSize(width: slotHeight, height: slotHeight),
                        habitName: snapshot.name
                    )
                    .onTapGesture {
                        guard let day = slot.actionDay else { return }
                        onToggle(day)
                    }
                }
            } else {
                ForEach(spans) { span in
                    SlotMarkView(
                        mark: span.mark,
                        size: CGSize(
                            width: SlotLayout.spanWidth(
                                trackWidth: geometry.trackWidth,
                                dayCount: span.dayCount
                            ),
                            height: slotHeight
                        ),
                        spansDays: span.dayCount > 1
                    )
                    .contentShape(Capsule(style: .continuous))
                    .onTapGesture {
                        guard let day = span.actionDay else { return }
                        onToggle(day)
                    }
                    .accessibilityElement()
                    .accessibilityLabel("\(snapshot.name), \(spanLabel(span))")
                    .accessibilityAddTraits(span.isTappable ? .isButton : [])
                }
            }
        }
    }

    private func spanLabel(_ span: SlotSpan) -> String {
        switch span.state {
        case .filled: "done"
        case .open: "due today"
        case .missed, .inactive: "still to come"
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

    @ViewBuilder
    private var label: some View {
        let text = HStack(spacing: 8) {
            HabitIconView(icon: snapshot.icon)
            Text(snapshot.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.subheadline)

        Group {
            // A due label is full white with a drop shadow in the design, which
            // is the same thing the marks are — so it gets the same treatment.
            // Rendered as bright text it was the one part of the screen
            // pretending to be lit.
            if isDue {
                text.glowing(halo: GlowPalette.labelHalo)
            } else {
                text.foregroundStyle(GlowPalette.labelResting)
            }
        }
        .frame(width: geometry.labelWidth, alignment: .leading)
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
