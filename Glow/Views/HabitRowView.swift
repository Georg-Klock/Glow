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

    private var slotSize: CGSize {
        SlotLayout.slotSize(
            trackWidth: geometry.trackWidth,
            slotCount: snapshot.frequency.slotCount
        )
    }

    var body: some View {
        HStack(spacing: GridMetrics.labelSpacing) {
            label
            HStack(spacing: SlotLayout.gap) {
                ForEach(slots) { slot in
                    SlotView(
                        slot: slot,
                        size: slotSize,
                        habitName: snapshot.name
                    )
                    .onTapGesture {
                        guard let day = slot.actionDay else { return }
                        onToggle(day)
                    }
                }
            }
            .frame(width: geometry.trackWidth, alignment: .leading)
        }
        .frame(height: max(slotSize.height, GridMetrics.minimumRowHeight))
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

    private var label: some View {
        HStack(spacing: 8) {
            HabitIconView(icon: snapshot.icon)
            Text(snapshot.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.subheadline.weight(isDue ? .semibold : .regular))
        .foregroundStyle(isDue ? GlowPalette.labelDue : GlowPalette.labelResting)
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
