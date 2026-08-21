import SwiftUI
import WidgetKit

/// The Today widget's rings.
///
/// The same `DayRingView` the app draws, at widget size. The ring is a button
/// backed by `TapHabitIntent`, so a repetition is logged without leaving the
/// home screen — the same claim the week widget makes for a day.
///
/// Everything unlit is white-with-alpha from `GlowPalette`, which is what
/// survives accented rendering: a Clear or Tinted home screen tints content to
/// a single white and keeps only the alpha, so hierarchy stored in a hue would
/// collapse there.
struct TodaySmallView: View {
    let entry: TodayEntry

    var body: some View {
        if let habit = entry.habits.first {
            Button(intent: TapHabitIntent(habitID: habit.id)) {
                RingCell(habit: habit, diameter: 96, iconSize: 30)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TodayEmptyState()
        }
    }
}

struct TodayMediumView: View {
    let entry: TodayEntry

    var body: some View {
        if entry.habits.isEmpty {
            TodayEmptyState()
        } else {
            // All the same size, however many there are. Three icons, three
            // rings, no size hierarchy between them — a WHOOP widget without
            // the pecking order.
            HStack(spacing: 24) {
                ForEach(entry.habits) { habit in
                    Button(intent: TapHabitIntent(habitID: habit.id)) {
                        RingCell(habit: habit, diameter: 76, iconSize: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RingCell: View {
    let habit: DayRingSnapshot
    let diameter: CGFloat
    let iconSize: CGFloat

    private var isOpen: Bool { habit.done < habit.target }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                DayRingView(target: habit.target, done: habit.done, diameter: diameter)
                HabitIconView(icon: habit.icon, size: iconSize)
            }
            // The same rule as every label: due glows, handled rests.
            let name = Text(habit.name)
                .font(.system(size: WidgetMetrics.textSize))
                .lineLimit(1)
            if isOpen {
                name.glowing(halo: GlowPalette.labelHalo)
            } else {
                name.foregroundStyle(GlowPalette.labelResting)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(habit.name)
        .accessibilityValue("\(habit.done) of \(habit.target) done today")
        .accessibilityHint(isOpen ? "Adds one" : "Starts the day over")
    }
}

private struct TodayEmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "circle.dotted")
                .font(.title2)
            Text("No daily habits yet")
                .font(.system(size: WidgetMetrics.textSize))
        }
        .foregroundStyle(GlowPalette.headerRest)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
