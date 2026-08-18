import SwiftData
import SwiftUI

/// Add or edit a habit. One sheet for both, since the fields are identical.
struct HabitEditorView: View {
    let habit: Habit?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var icon: String = "⭐️"
    @State private var isDaily: Bool = true
    @State private var timesPerWeek: Int = 3
    @State private var accent: HabitAccent = .teal

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
                    // Emoji rather than a curated SF Symbols set: free text is
                    // less work and lets the user pick anything. See
                    // docs/decisions.md.
                    TextField("Icon", text: $icon)
                        .onChange(of: icon) { _, new in
                            icon = String(new.prefix(2))
                        }
                }

                Section("Frequency") {
                    Picker("Cadence", selection: $isDaily) {
                        Text("Every day").tag(true)
                        Text("Times per week").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if !isDaily {
                        Stepper(
                            "\(timesPerWeek) times per week",
                            value: $timesPerWeek,
                            in: Frequency.selectableCounts
                        )
                    }
                }

                Section("Colour") {
                    HStack(spacing: 14) {
                        ForEach(HabitAccent.allCases) { option in
                            Button {
                                accent = option
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(.white, lineWidth: accent == option ? 2 : 0)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.displayName)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isEditing ? "Edit habit" : "New habit")
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
    }

    private func loadExisting() {
        guard let habit else { return }
        name = habit.name
        icon = habit.icon
        accent = habit.accent
        switch habit.frequency {
        case .daily:
            isDaily = true
        case .timesPerWeek(let count):
            isDaily = false
            timesPerWeek = count
        }
    }

    private func save() {
        let store = HabitStore(context: context)
        do {
            if let habit {
                try store.update(habit, name: trimmedName, icon: icon, frequency: frequency, accent: accent)
            } else {
                try store.addHabit(name: trimmedName, icon: icon, frequency: frequency, accent: accent)
            }
            dismiss()
        } catch {
            HabitStore.report(error, operation: isEditing ? "update" : "addHabit")
        }
    }
}
