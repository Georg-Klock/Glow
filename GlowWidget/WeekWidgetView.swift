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
                        burst: entry.burstHabit == habit.id ? entry.coverage : nil
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
    /// Non-nil while this habit's completion is animating.
    let burst: Double?

    private var slots: [Slot] {
        WeekGrid.slots(for: habit, in: week, today: today)
    }

    /// Still waiting on today. The label follows the slot, same rule as the app.
    private var isDue: Bool {
        slots.contains { $0.state == .open }
    }

    var body: some View {
        HStack(spacing: 6) {
            if showsLabel {
                HStack(spacing: 5) {
                    HabitIconView(icon: habit.icon)
                    Text(habit.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption.weight(isDue ? .semibold : .regular))
                .foregroundStyle(isDue ? GlowPalette.labelDue : GlowPalette.labelResting)
                .frame(width: 74, alignment: .leading)
            }

            HStack(spacing: 3) {
                ForEach(slots) { slot in
                    WidgetSlot(
                        slot: slot,
                        habitID: habit.id,
                        habitName: habit.name,
                        burst: slot.isTappable ? burst : nil
                    )
                }
            }
        }
    }
}

private struct WidgetSlot: View {
    let slot: Slot
    let habitID: UUID
    let habitName: String
    /// Set only on the slot that was just tapped.
    let burst: Double?

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

    /// fillsWidth throughout: the widget's slots are distributed by the HStack,
    /// and pinning a width here would fight the layout.
    private static let slotSize = CGSize(width: 0, height: 14)

    @ViewBuilder
    private var shape: some View {
        if let burst, slot.state == .filled {
            // The app's three beats, sampled. The widget cannot cross-fade
            // across a snapshot boundary, so the burst arrives as a coverage
            // value per entry: the ring gives way to the solid capsule, and the
            // capsule to the checkmark, at the two thirds of the way through.
            ZStack {
                GlowImageView(size: Self.slotSize, shape: burstShape, fillsWidth: true)
            }
            .frame(height: Self.slotSize.height)
        } else {
            // The widget glows. Worth stating plainly, because this project
            // assumed the opposite for a long time and wrote it into the spec
            // as a non-goal: WidgetKit renders out-of-process and archives the
            // result, so HDR was supposed to be impossible here. Measured on an
            // iPhone 14 Pro running the real PQ tile, it is not.
            SlotMarkView(mark: slot.mark, size: Self.slotSize, fillsWidth: true)
        }
    }

    /// Which of the app's three beats this entry is on.
    ///
    /// `WidgetBurst.coverage` is flat at 0 through the hold and then eases to 1,
    /// so zero is the ring still waiting and the rest splits at the halfway
    /// point. Snapping between three shapes rather than cross-fading is not a
    /// compromise made for the widget — a snapshot cannot cross-fade at all, and
    /// at 10fps over one second the beats are what reads anyway.
    private var burstShape: GlowShape {
        guard let burst else { return .checkmark }
        if burst <= 0 { return .ring }
        return burst < 0.5 ? .capsule : .checkmark
    }
}
