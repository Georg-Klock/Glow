import SwiftData
import SwiftUI
import WidgetKit

/// Add or edit a habit. One sheet for both, since the fields are identical.
struct HabitEditorView: View {
    let habit: Habit?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var icon = HabitSymbol.default
    /// Counted, never a mode. Seven means every day — `Frequency` normalizes it
    /// to `.daily`, so the two cadences are one number rather than a switch and
    /// a number that have to agree.
    @State private var timesPerWeek = Frequency.daysInWeek

    @FocusState private var isNameFocused: Bool
    @State private var isConfirmingDelete = false
    @State private var isPickingIcon = false

    private var isEditing: Bool { habit != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var frequency: Frequency { Frequency(timesPerWeek: timesPerWeek) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        // The icon leads the row, so a habit is a picture and a
                        // name in that order — the same order the grid reads in.
                        Button { isPickingIcon = true } label: {
                            HabitIconView(icon: icon)
                                .font(.title3)
                                .frame(width: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Icon")

                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.sentences)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                    }
                }

                Section {
                    // A Stepper, which is the system's own — and + pair. There
                    // is no cadence switch any more: seven times a week *is*
                    // daily, and a mode plus a count is two controls that can
                    // disagree with each other about one fact.
                    Stepper(value: $timesPerWeek, in: 1...Frequency.daysInWeek) {
                        HStack(spacing: 0) {
                            Text("\(timesPerWeek)")
                                .monospacedDigit()
                                .foregroundStyle(GlowPalette.color)
                            Text(timesPerWeek == 1 ? " time per week" : " times per week")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if isEditing {
                    Section {
                        Button("Delete Habit", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    } footer: {
                        Text("Deleting a habit also removes everything logged against it.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Habit" : "New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .navigationDestination(isPresented: $isPickingIcon) {
            SymbolPickerView(selection: $icon)
        }
        .onAppear(perform: loadExisting)
        // Destructive and irreversible: the completions cascade with it.
        .confirmationDialog(
            "Delete this habit?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Habit", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also removes every day logged against it. It cannot be undone.")
        }
    }

    private func loadExisting() {
        guard let habit else {
            // A new habit opens with an empty, focused name and an arbitrary
            // icon. The icon is a starting point rather than a suggestion —
            // something is always better than a placeholder tick, and it is one
            // tap from being changed.
            icon = HabitSymbol.random()
            isNameFocused = true
            return
        }
        name = habit.name
        icon = habit.icon
        timesPerWeek = habit.frequency.slotCount
    }

    private func delete() {
        guard let habit else { return }
        do {
            try HabitStore(context: context).delete(habit)
            WidgetCenter.shared.reloadAllTimelines()
            dismiss()
        } catch {
            HabitStore.report(error, operation: "delete")
        }
    }

    private func save() {
        let store = HabitStore(context: context)
        do {
            if let habit {
                try store.update(habit, name: trimmedName, icon: icon, frequency: frequency)
            } else {
                try store.addHabit(name: trimmedName, icon: icon, frequency: frequency)
            }
            WidgetCenter.shared.reloadAllTimelines()
            dismiss()
        } catch {
            HabitStore.report(error, operation: isEditing ? "update" : "addHabit")
        }
    }
}
