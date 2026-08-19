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
    @State private var isDaily = true
    @State private var timesPerWeek = 3

    @FocusState private var isNameFocused: Bool
    @State private var isConfirmingDelete = false

    private var isEditing: Bool { habit != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var frequency: Frequency {
        isDaily ? .daily : Frequency(timesPerWeek: timesPerWeek)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .focused($isNameFocused)
                        .submitLabel(.done)

                    NavigationLink {
                        SymbolPickerView(selection: $icon)
                    } label: {
                        LabeledContent("Icon") {
                            HabitIconView(icon: icon)
                        }
                    }
                }

                Section("Frequency") {
                    Picker("Cadence", selection: $isDaily) {
                        Text("Every day").tag(true)
                        Text("Times per week").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if !isDaily {
                        Stepper(value: $timesPerWeek, in: Frequency.selectableCounts) {
                            LabeledContent("Per week", value: "\(timesPerWeek)")
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
            isNameFocused = true
            return
        }
        name = habit.name
        icon = habit.icon
        switch habit.frequency {
        case .daily:
            isDaily = true
        case .timesPerWeek(let count):
            isDaily = false
            timesPerWeek = count
        }
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
