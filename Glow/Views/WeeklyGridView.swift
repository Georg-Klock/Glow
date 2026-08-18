import SwiftData
import SwiftUI

/// The whole app: every habit's status for the current week, one tap from done.
struct WeeklyGridView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: [SortDescriptor(\Habit.sortOrder)]) private var habits: [Habit]

    @State private var today = WeekCalendar.day(Date())
    @State private var editingHabit: Habit?
    @State private var isAddingHabit = false

    private var week: Week { WeekCalendar.week(containing: today) }
    private var store: HabitStore { HabitStore(context: context) }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let trackWidth = GridMetrics.trackWidth(totalWidth: geometry.size.width)
                Group {
                    if habits.isEmpty {
                        EmptyStateView { isAddingHabit = true }
                    } else {
                        grid(trackWidth: trackWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.appBackground)
            .navigationTitle(weekTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingHabit = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add habit")
                }
            }
            .toolbarBackground(Color.appBackground, for: .navigationBar)
        }
        .sheet(isPresented: $isAddingHabit) {
            HabitEditorView(habit: nil)
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditorView(habit: habit)
        }
        // The open slot is defined as "today", so the screen has to notice when
        // today changes. Both paths matter: the notification covers the app
        // being open across midnight, the scene phase covers it being resumed
        // the next morning without ever having been killed.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshToday()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshToday() }
        }
    }

    private func grid(trackWidth: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WeekdayHeader(trackWidth: trackWidth, week: week, today: today)
                ForEach(habits) { habit in
                    HabitRowView(
                        snapshot: habit.snapshot(),
                        week: week,
                        today: today,
                        trackWidth: trackWidth
                    ) { day in
                        toggle(habit, on: day)
                    }
                    .contextMenu {
                        Button("Edit") { editingHabit = habit }
                        Button("Delete", role: .destructive) { delete(habit) }
                    }
                }
            }
            .padding(.horizontal, GridMetrics.horizontalPadding)
            .padding(.vertical, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var weekTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = WeekCalendar.calendar
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: today)
    }

    private func refreshToday() {
        let current = WeekCalendar.day(Date())
        if current != today { today = current }
    }

    private func toggle(_ habit: Habit, on day: Date) {
        do {
            try store.toggleCompletion(for: habit, on: day)
        } catch {
            HabitStore.report(error, operation: "toggleCompletion")
        }
    }

    private func delete(_ habit: Habit) {
        do {
            try store.delete(habit)
        } catch {
            HabitStore.report(error, operation: "delete")
        }
    }
}

/// M T W T F S S, aligned to a seven-slot track.
///
/// Frequency rows deliberately do not line up with these: their pills are not
/// day-pinned, so there is nothing for them to line up with.
struct WeekdayHeader: View {
    let trackWidth: CGFloat
    let week: Week
    let today: Date

    var body: some View {
        HStack(spacing: GridMetrics.labelSpacing) {
            Color.clear
                .frame(width: GridMetrics.labelWidth, height: 1)
            HStack(spacing: SlotLayout.gap) {
                ForEach(Array(WeekCalendar.weekdayInitials().enumerated()), id: \.offset) { index, initial in
                    Text(initial)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(week.days[index] == today ? .white : Color.white.opacity(0.35))
                        .frame(width: SlotLayout.slotWidth(trackWidth: trackWidth, slotCount: 7))
                }
            }
            .frame(width: trackWidth, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

private struct EmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("No habits yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text("Add one, and today's slot will be waiting for you.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Button("Add a habit", action: onAdd)
                .buttonStyle(.borderedProminent)
                .tint(HabitAccent.teal.color)
                .padding(.top, 8)
        }
        .padding(32)
    }
}

#Preview {
    WeeklyGridView()
        .modelContainer(for: [Habit.self, Completion.self], inMemory: true)
}
