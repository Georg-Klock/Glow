import SwiftData
import SwiftUI

/// Reorder and delete habits.
///
/// A separate sheet rather than an edit mode on the grid. The grid's rows are
/// a fixed-width track divided to the pixel, and putting drag handles and
/// delete buttons into them would either shrink the track (so the columns stop
/// lining up with the header) or overflow it. Reordering is also rare, and the
/// grid is the thing that has to stay uncluttered.
struct EditHabitsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Habit.sortOrder)]) private var habits: [Habit]

    @State private var editingHabit: Habit?

    private var store: HabitStore { HabitStore(context: context) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(habits) { habit in
                    Button {
                        editingHabit = habit
                    } label: {
                        HStack(spacing: 12) {
                            Text(habit.icon)
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.name)
                                    .foregroundStyle(.white)
                                Text(cadenceDescription(habit.frequency))
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer(minLength: 0)
                            Circle()
                                .fill(habit.accent.color)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: delete)
            }
            .navigationTitle("Edit habits")
            .navigationBarTitleDisplayMode(.inline)
            // Always on: the sheet exists to reorder, so making the user press
            // Edit first would be a step to reach the only thing here.
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditorView(habit: habit)
        }
    }

    private func cadenceDescription(_ frequency: Frequency) -> String {
        switch frequency {
        case .daily: "Every day"
        case .timesPerWeek(let count): "\(count) times per week"
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        do {
            try store.reorder(habits, from: source, to: destination)
        } catch {
            HabitStore.report(error, operation: "reorder")
        }
    }

    private func delete(at offsets: IndexSet) {
        for habit in offsets.map({ habits[$0] }) {
            do {
                try store.delete(habit)
            } catch {
                HabitStore.report(error, operation: "delete")
            }
        }
    }
}
