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
                        //
                        // On a filled circle with a chevron, because a bare
                        // glyph beside a text field reads as decoration and
                        // nothing about it says it can be changed. This is the
                        // same shape Reminders and Calendar use for the job.
                        Button { isPickingIcon = true } label: {
                            HabitIconView(icon: icon)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(.fill.tertiary))
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "chevron.down.circle.fill")
                                        .font(.caption2)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(GlowPalette.color, .black)
                                        .offset(x: 2, y: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Icon")
                        .accessibilityHint("Choose a different icon")
                        .accessibilityAddTraits(.isButton)

                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.sentences)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                    }
                }

                Section {
                    frequencyRow
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
            // Inside the stack, not on it. Applied to the NavigationStack
            // itself this compiles, shows nothing, and reads as a dead tap
            // target — there is no stack above it to push onto.
            .navigationDestination(isPresented: $isPickingIcon) {
                SymbolPickerView(selection: $icon)
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

    /// Minus, the reading, plus — in that order across the row.
    ///
    /// Hand-rolled rather than a `Stepper`, which always puts its label on one
    /// side and both buttons on the other and cannot be split around the middle.
    /// What a `Stepper` gives away for free has to be put back by hand, and the
    /// pieces below are exactly that: bounds that disable rather than clamp
    /// silently, hit targets a thumb can find, and an adjustable action so
    /// VoiceOver still reads this as one control with a value rather than as two
    /// unlabelled buttons either side of some text.
    private var frequencyRow: some View {
        HStack(spacing: 8) {
            stepButton("minus", enabled: timesPerWeek > Frequency.selectableCounts.lowerBound) {
                timesPerWeek -= 1
            }

            HStack(spacing: 0) {
                Text("\(timesPerWeek)")
                    .monospacedDigit()
                    .foregroundStyle(GlowPalette.color)
                Text("x per week")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            stepButton("plus", enabled: timesPerWeek < Frequency.selectableCounts.upperBound) {
                timesPerWeek += 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Times per week")
        .accessibilityValue("\(timesPerWeek)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where timesPerWeek < Frequency.selectableCounts.upperBound:
                timesPerWeek += 1
            case .decrement where timesPerWeek > Frequency.selectableCounts.lowerBound:
                timesPerWeek -= 1
            default:
                break
            }
        }
    }

    private func stepButton(
        _ symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        // Borderless, or a Form row treats its whole width as one button and
        // either control fires whichever was tapped.
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .accessibilityHidden(true)
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
