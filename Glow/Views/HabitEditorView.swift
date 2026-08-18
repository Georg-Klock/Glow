import SwiftData
import SwiftUI

/// Add or edit a habit. One sheet for both, since the fields are identical.
struct HabitEditorView: View {
    let habit: Habit?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var icon = HabitSymbol.default
    @State private var isDaily = true
    @State private var timesPerWeek = 3
    @State private var accent: HabitAccent = .teal

    @FocusState private var isNameFocused: Bool

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

                Section("Colour") {
                    // A palette-style Picker was the obvious choice and is the
                    // wrong one here: it imposes its own tint on every item, so
                    // the swatches all render in the app's accent and a colour
                    // picker ends up showing one colour. This is the same
                    // swatch grid the icon section uses, which keeps the two
                    // choices looking like the same kind of choice.
                    swatchRow
                }

                Section("Icon") {
                    symbolGrid
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
    }

    private var swatchRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
            ForEach(HabitAccent.allCases) { option in
                Button {
                    accent = option
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle()
                                .strokeBorder(.primary, lineWidth: accent == option ? 2.5 : 0)
                        }
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
                .accessibilityAddTraits(accent == option ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }

    private var symbolGrid: some View {
        ForEach(HabitSymbol.catalog, id: \.section) { group in
            VStack(alignment: .leading, spacing: 8) {
                Text(group.section)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 44), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(group.symbols, id: \.self) { symbol in
                        Button {
                            icon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 20))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(icon == symbol ? Color.white : accent.color)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(icon == symbol ? AnyShapeStyle(accent.color) : AnyShapeStyle(.fill.tertiary))
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(icon == symbol ? [.isSelected, .isButton] : .isButton)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func loadExisting() {
        guard let habit else {
            isNameFocused = true
            return
        }
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

/// A habit's icon, as a symbol or as whatever text was stored before symbols.
struct HabitIconView: View {
    let icon: String
    let accent: HabitAccent

    var body: some View {
        Group {
            if HabitSymbol.isSymbol(icon) {
                Image(systemName: icon)
                    .foregroundStyle(accent.color)
            } else {
                Text(icon)
            }
        }
        .font(.body)
        .frame(width: 24, alignment: .center)
    }
}
