import SwiftData
import SwiftUI
import WidgetKit

/// Today: the several-times-a-day habits, and nothing else.
///
/// This screen is the small and medium widget at app size — rings, one per
/// habit, each a day's repetitions as arcs. There is no history here and no
/// week: a per-day habit's count resets with the day, so the only question the
/// screen answers is "what is left today", asked by the glow.
///
/// The weekly cadences live in This Week and never appear here, which is the
/// either/or the model is built on: a habit is counted across a week or within
/// a day, never both.
struct TodayView: View {
    @Query(filter: Habit.countedPerDay, sort: [SortDescriptor(\Habit.sortOrder)])
    private var habits: [Habit]

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = WeekCalendar.day(Date())

    private var store: HabitStore { HabitStore(context: context) }

    /// Three rings to a row, like the medium widget. Sized so a full row sits
    /// inside an iPhone's width with the margins the widget would have.
    private static let ringDiameter: CGFloat = 92
    private static let columns = 3
    private static let rowSpacing: CGFloat = 28
    private static let columnSpacing: CGFloat = 20

    var body: some View {
        NavigationStack {
            Group {
                if habits.isEmpty {
                    ContentUnavailableView {
                        Label("No Habits", systemImage: "circle.dotted")
                    } description: {
                        Text("A habit done several times a day shows up here as a ring.")
                    }
                } else {
                    rings
                }
            }
            .navigationTitle(title)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = WeekCalendar.day(Date())
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = WeekCalendar.day(Date()) }
        }
    }

    /// Rows of three, centred — the medium widget's layout, stacked. A plain
    /// stack rather than a grid so a final row of one or two rings centres the
    /// way the widget would centre them, instead of hugging the leading edge.
    private var rings: some View {
        ScrollView {
            VStack(spacing: Self.rowSpacing) {
                ForEach(rows, id: \.first?.id) { row in
                    HStack(alignment: .top, spacing: Self.columnSpacing) {
                        ForEach(row) { habit in cell(habit) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }

    private var rows: [[Habit]] {
        stride(from: 0, to: habits.count, by: Self.columns).map {
            Array(habits[$0..<min($0 + Self.columns, habits.count)])
        }
    }

    private func cell(_ habit: Habit) -> some View {
        let target = habit.timesPerDay
        let done = habit.snapshot().count(on: today)
        let isOpen = done < target

        return Button {
            tap(habit, done: done, target: target)
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    DayRingView(target: target, done: done, diameter: Self.ringDiameter)
                    HabitIconView(icon: habit.icon, size: Self.ringDiameter * 0.3)
                }
                // The same rule as everywhere: a due name glows, a handled one
                // rests. The weight never changes, so completing does not
                // reflow.
                let name = Text(habit.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if isOpen {
                    name.glowing(halo: GlowPalette.labelHalo)
                } else {
                    name.foregroundStyle(GlowPalette.labelResting)
                }
            }
            .frame(width: Self.ringDiameter + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(habit.name)
        .accessibilityValue("\(done) of \(target) done today")
        .accessibilityHint(isOpen ? "Adds one" : "Starts the day over")
    }

    /// A tap is one more; a tap on a full ring starts the day over. The rule
    /// is `DayRing.countAfterTap`, applied by the store — this only reports
    /// what happened to a thumb that cannot see under itself.
    private func tap(_ habit: Habit, done: Int, target: Int) {
        do {
            let count = try store.recordTap(for: habit, on: today)
            // A reset is a correction, and should not feel like progress.
            if count == 0 && done > 0 { Haptics.uncompleted() } else { Haptics.completed() }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            HabitStore.report(error, operation: "recordTap")
        }
    }

    private var title: String {
        today.formatted(
            .dateTime.weekday(.wide).day().month(.wide)
                .locale(WeekCalendar.calendar.locale ?? .current)
        )
    }
}
