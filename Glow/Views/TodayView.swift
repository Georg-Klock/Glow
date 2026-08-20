import SwiftData
import SwiftUI
import WidgetKit

/// Today, and nothing else.
///
/// The week grid answers "how am I doing"; this answers "what is left", which is
/// a different question and the one asked most often. So there is no history on
/// this screen at all — no past columns, no streak, no count of what went wrong
/// last Tuesday. Just the habits still open, and under them the ones already
/// handled, quiet.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: [SortDescriptor(\Habit.sortOrder)]) private var habits: [Habit]

    @State private var today = WeekCalendar.day(Date())

    private var week: Week { WeekCalendar.week(containing: today) }
    private var store: HabitStore { HabitStore(context: context) }

    /// The habit, and the slot that today's tap would toggle.
    private struct Entry: Identifiable {
        let habit: Habit
        let slot: Slot
        var id: UUID { habit.id }
    }

    private var entries: [Entry] {
        habits.filter { !$0.isSpacer }.compactMap { habit in
            let slots = WeekGrid.slots(for: habit.snapshot(), in: week, today: today)
            guard let slot = slots.first(where: \.isTappable) else { return nil }
            return Entry(habit: habit, slot: slot)
        }
    }

    private var open: [Entry] { entries.filter { $0.slot.state != .filled } }
    /// Nothing was expected today, so nothing is missing.
    private var resting: Bool {
        !habits.isEmpty && entries.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if habits.allSatisfy(\.isSpacer) {
                    ContentUnavailableView {
                        Label("No Habits", systemImage: "circle.dotted")
                    } description: {
                        Text("Add a habit in This Week and it will show up here.")
                    }
                } else if resting {
                    restDayState
                } else if open.isEmpty {
                    allDoneState
                } else {
                    list
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

    /// One list, in the habits' own order.
    ///
    /// It used to split into "left" and "done" and re-sort as you tapped, which
    /// meant a row moved out from under your thumb the moment you touched it,
    /// and the list you were reading was never the same list twice. The order is
    /// yours; only the marks change.
    private var list: some View {
        List {
            Section {
                ForEach(entries) { entry in row(entry) }
            } header: {
                Text(open.count == 1 ? "1 left" : "\(open.count) left")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ entry: Entry) -> some View {
        let isOpen = entry.slot.state != .filled
        return Button {
            toggle(entry)
        } label: {
            HStack(spacing: 14) {
                HabitIconView(icon: entry.habit.icon)
                let name = Text(entry.habit.name)
                    .font(.body)
                if isOpen {
                    name.glowing(halo: GlowPalette.labelHalo)
                } else {
                    name.foregroundStyle(GlowPalette.labelResting)
                }
                Spacer(minLength: 12)
                // The same mark the grid draws, at a size a thumb can find.
                SlotMarkView(mark: entry.slot.mark, size: CGSize(width: 30, height: 30))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.habit.name)
        .accessibilityValue(isOpen ? "due today" : "done")
        .accessibilityHint(isOpen ? "Mark as done" : "Mark as not done")
    }

    /// Everything expected today is logged. Says so and stops.
    private var allDoneState: some View {
        ContentUnavailableView {
            VStack(spacing: 14) {
                GlowImageView(size: CGSize(width: 54, height: 54), shape: .dot)
                Text("All Done")
            }
        } description: {
            Text("Every habit is logged for today.")
        }
    }

    private var restDayState: some View {
        ContentUnavailableView {
            Label("Rest Day", systemImage: "moon.zzz")
        } description: {
            Text("Nothing is expected today. Anything you log still counts.")
        }
    }

    private var title: String {
        today.formatted(
            .dateTime.weekday(.wide).day().month(.wide)
                .locale(WeekCalendar.calendar.locale ?? .current)
        )
    }

    private func toggle(_ entry: Entry) {
        guard let day = entry.slot.actionDay else { return }
        do {
            let isNowComplete = try store.toggleCompletion(for: entry.habit, on: day)
            if isNowComplete { Haptics.completed() } else { Haptics.uncompleted() }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            HabitStore.report(error, operation: "toggleFromToday")
        }
    }
}
