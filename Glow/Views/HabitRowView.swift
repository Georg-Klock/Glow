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
                        accent: snapshot.accent,
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

    private var label: some View {
        HStack(spacing: 8) {
            Text(snapshot.icon)
                .font(.system(size: 18))
            Text(snapshot.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(width: geometry.labelWidth, alignment: .leading)
        // The slots carry the habit's name in their own labels, so reading the
        // row aloud twice would be noise.
        .accessibilityHidden(true)
    }
}
