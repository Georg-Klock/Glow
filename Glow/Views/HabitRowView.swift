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
    /// Wide enough for the longest seeded name at the body size. "Touch Grass"
    /// and "Watch Sunset" both truncated at 116, and a habit tracker whose first
    /// screen shows "Watch S..." has failed at the one thing it does.
    static let baseLabelWidth: CGFloat = 140
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
        .onAppear { lit = isDue ? 1 : 0 }
        .onChange(of: isDue) { _, due in
            withAnimation(SlotView.close) { lit = due ? 1 : 0 }
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
        let text = HStack(spacing: 8) {
            HabitIconView(icon: snapshot.icon)
            Text(snapshot.name)
                .lineLimit(1)
                // Shrink before truncating. A width picked for the longest
                // seeded name is a guess that a longer name, a larger Dynamic
                // Type setting or another language will beat.
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .font(.subheadline)

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
