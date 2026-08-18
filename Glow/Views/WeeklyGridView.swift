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
    @State private var isEditingList = false

    private var week: Week { WeekCalendar.week(containing: today) }
    private var store: HabitStore { HabitStore(context: context) }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let rowGeometry = RowGeometry(totalWidth: geometry.size.width)
                Group {
                    if habits.isEmpty {
                        EmptyStateView { isAddingHabit = true }
                    } else {
                        grid(rowGeometry)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.appBackground)
            .navigationTitle(monthTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !habits.isEmpty {
                        Button {
                            isEditingList = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                        .accessibilityLabel("Edit habits")
                    }
                }
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
        .sheet(isPresented: $isEditingList) {
            EditHabitsView()
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

    private func grid(_ rowGeometry: RowGeometry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GridMetrics.rowSpacing) {
                WeekdayHeader(geometry: rowGeometry, week: week, today: today)
                    .padding(.bottom, 2)
                ForEach(habits) { habit in
                    HabitRowView(
                        snapshot: habit.snapshot(),
                        week: week,
                        today: today,
                        geometry: rowGeometry
                    ) { day in
                        toggle(habit, on: day)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editingHabit = habit }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(habit)
                        }
                    }
                }
            }
            .padding(.horizontal, GridMetrics.horizontalPadding)
            .padding(.vertical, 18)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = WeekCalendar.calendar
        formatter.locale = WeekCalendar.calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: today)
    }

    private func refreshToday() {
        let current = WeekCalendar.day(Date())
        if current != today { today = current }
    }

    private func toggle(_ habit: Habit, on day: Date) {
        do {
            let isNowComplete = try store.toggleCompletion(for: habit, on: day)
            if isNowComplete {
                Haptics.completed()
            } else {
                Haptics.uncompleted()
            }
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

/// M T W T F S S over the dates they stand for, aligned to a seven-slot track.
///
/// Frequency rows deliberately do not line up with these: their pills are not
/// day-pinned, so there is nothing for them to line up with.
struct WeekdayHeader: View {
    let geometry: RowGeometry
    let week: Week
    let today: Date

    private var initials: [String] { WeekCalendar.weekdayInitials() }
    private var numbers: [String] { WeekCalendar.dayNumbers(in: week) }

    var body: some View {
        HStack(spacing: GridMetrics.labelSpacing) {
            Color.clear
                .frame(width: geometry.labelWidth, height: 1)
            HStack(spacing: SlotLayout.gap) {
                ForEach(0..<7, id: \.self) { index in
                    let isToday = week.days[index] == today
                    VStack(spacing: 3) {
                        Text(initials[index])
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isToday ? .white : Color.white.opacity(0.3))
                        Text(numbers[index])
                            .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                            .foregroundStyle(isToday ? .white : Color.white.opacity(0.45))
                            .monospacedDigit()
                    }
                    .frame(width: SlotLayout.slotWidth(trackWidth: geometry.trackWidth, slotCount: 7))
                }
            }
            .frame(width: geometry.trackWidth, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

private struct EmptyStateView: View {
    let onAdd: () -> Void

    /// A live slot rather than an illustration: the empty state shows the exact
    /// thing the app is about, rendered by the same code that draws the grid.
    /// On an HDR screen it glows here too.
    private let sampleSize = CGSize(width: 56, height: 56)

    var body: some View {
        VStack(spacing: 0) {
            GlowImageView(size: sampleSize, accent: .teal)
                .padding(.bottom, 28)
            Text("No habits yet")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text("Add one, and today's slot will be waiting for you.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 24)
            Button("Add a habit", action: onAdd)
                .buttonStyle(.borderedProminent)
                .tint(HabitAccent.teal.color)
                .foregroundStyle(.black)
                .padding(.top, 24)
        }
        .padding(32)
    }
}

#Preview {
    WeeklyGridView()
        .modelContainer(for: [Habit.self, Completion.self], inMemory: true)
}
