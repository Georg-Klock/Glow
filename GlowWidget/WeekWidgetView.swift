import SwiftUI
import WidgetKit

/// The widget's grid.
///
/// Deliberately not a reuse of `HabitRowView`. That view is built around a
/// track width measured from the screen and a slot height derived from it,
/// which is the right model for a full screen and the wrong one for a 155pt
/// square. Here the row count is capped by family and the geometry is simply
/// whatever fits.
struct WeekWidgetView: View {
    let entry: WeekEntry

    @Environment(\.widgetFamily) private var family

    private var rowLimit: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        default: 7
        }
    }

    private var showsLabels: Bool { family != .systemSmall }

    private var habits: [HabitSnapshot] { Array(entry.habits.prefix(rowLimit)) }
    private var overflow: Int { max(0, entry.habits.count - rowLimit) }

    var body: some View {
        if entry.habits.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "circle.dotted")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No habits yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(habits) { habit in
                    WidgetRow(
                        habit: habit,
                        week: entry.week,
                        today: entry.date,
                        showsLabel: showsLabels,
                        phase: entry.phase
                    )
                }
                if overflow > 0 {
                    Text("+\(overflow) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct WidgetRow: View {
    let habit: HabitSnapshot
    let week: Week
    let today: Date
    let showsLabel: Bool
    let phase: Double

    private var slots: [Slot] {
        WeekGrid.slots(for: habit, in: week, today: today)
    }

    var body: some View {
        HStack(spacing: 6) {
            if showsLabel {
                HStack(spacing: 5) {
                    HabitIconView(icon: habit.icon)
                        .font(.caption)
                    Text(habit.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: 74, alignment: .leading)
            }

            HStack(spacing: 3) {
                ForEach(slots) { slot in
                    WidgetSlot(slot: slot, habitID: habit.id, habitName: habit.name, phase: phase)
                }
            }
        }
    }
}

private struct WidgetSlot: View {
    let slot: Slot
    let habitID: UUID
    let habitName: String
    let phase: Double

    private var fill: AnyShapeStyle {
        switch slot.state {
        case .open: AnyShapeStyle(GlowPalette.color)
        case .filled: AnyShapeStyle(GlowPalette.filled)
        case .inactive: AnyShapeStyle(.fill.secondary)
        }
    }

    var body: some View {
        // Only today's slot is a button, which is the same rule the app
        // enforces: past days are not editable, so they are not tappable here
        // either. A Button wrapping an untappable slot would still highlight
        // on touch and promise something it does not do.
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
        if slot.state == .open {
            // The widget glows. This is worth stating plainly because this
            // project assumed the opposite for a long time and wrote it into
            // the spec as a non-goal: WidgetKit renders out-of-process and
            // archives the result, so HDR was supposed to be impossible here.
            // Measured on an iPhone 14 Pro running the real PQ tile, it is not.
            //
            // fillsWidth because the widget's slots are distributed by the
            // HStack; pinning a width here would fight the layout.
            GlowImageView(size: CGSize(width: 0, height: 14), fillsWidth: true, phase: phase)
        } else {
            Capsule(style: .continuous)
                .fill(fill)
                .frame(height: 14)
        }
    }
}
