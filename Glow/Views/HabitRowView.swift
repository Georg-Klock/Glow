import SwiftUI

/// One habit: icon and name on the left, a fixed-width status track on the right.
struct HabitRowView: View {
    let snapshot: HabitSnapshot
    let week: Week
    let today: Date
    let trackWidth: CGFloat
    let onToggle: (Date) -> Void

    private var slots: [Slot] {
        WeekGrid.slots(for: snapshot, in: week, today: today)
    }

    private var slotSize: CGSize {
        SlotLayout.slotSize(trackWidth: trackWidth, slotCount: snapshot.frequency.slotCount)
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
            .frame(width: trackWidth, alignment: .leading)
        }
        .frame(height: max(slotSize.height, GridMetrics.minimumRowHeight))
    }

    private var label: some View {
        HStack(spacing: 8) {
            Text(snapshot.icon)
                .font(.system(size: 18))
            Text(snapshot.name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(width: GridMetrics.labelWidth, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// Shared geometry, so the weekday header and every row divide the screen the
/// same way. If these drifted apart the columns would stop lining up, which is
/// the one thing the whole screen is for.
enum GridMetrics {
    static let labelWidth: CGFloat = 116
    static let labelSpacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 20
    static let minimumRowHeight: CGFloat = 34

    /// The width left for slots once the label column and padding are taken.
    static func trackWidth(totalWidth: CGFloat) -> CGFloat {
        max(0, totalWidth - horizontalPadding * 2 - labelWidth - labelSpacing)
    }
}
