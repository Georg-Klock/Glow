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

    /// One height and one corner for every platter on this screen.
    ///
    /// The icon, the name and the stepper were three different heights: two
    /// hand-set and one whatever a Form row happened to size itself to. Now all
    /// three draw their own background at the same numbers, which is the only
    /// way three rows agree — matching a system row's height by eye works until
    /// the OS changes its padding.
    private static let rowHeight: CGFloat = 56
    /// 26, which is what the Form's own section corner measured at before the
    /// platters were drawn by hand: inset 36px at 12px down from the top edge,
    /// which solves to a 78px radius. On a 56pt row that is nearly a capsule,
    /// and it is what the stepper looked like when it was still a system row.
    private static let platterRadius: CGFloat = 26

    /// The icon's own size, passed rather than set with `.font` on the outside.
    /// `HabitIconView` sets its own font, so an outer `.font(.title3)` here did
    /// nothing at all and the glyph had been rendering at body size.
    private static let iconSize: CGFloat = 24

    /// How far the name sits from the platter's edge.
    private static let namePadding: CGFloat = 20

    /// The step buttons' own face. 44 × 32 was already the hit target; it is
    /// now also what you can see.
    private static let stepSize = CGSize(width: 44, height: 32)
    /// A quarter of the control's height, which is where a segmented control's
    /// selected segment sits at this size.
    ///
    /// The row's 26 is not a candidate: it is a ratio of a 56pt row, and on a
    /// 32pt button the same ratio is 15 — a capsule, which would read as a
    /// different family of control rather than the same one, smaller.
    private static let stepRadius: CGFloat = 8
    /// Spent, not merely quiet. Low enough to stop inviting a tap, high enough
    /// that the button is still plainly there and the row keeps its shape.
    private static let stepDisabledOpacity: Double = 0.45

    private var isEditing: Bool { habit != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var frequency: Frequency { Frequency(timesPerWeek: timesPerWeek) }

    /// The number the stepper is editing, and the bounds it steps inside.
    ///
    /// A `Binding` and a computed range for what is now one number in one
    /// range, because the row below is written against a control that had two
    /// of each while the per-day kind shipped (#209). Collapsing them into
    /// `$timesPerWeek` and a literal is a rewrite of that row for no behaviour.
    private var count: Binding<Int> { $timesPerWeek }

    private var countRange: ClosedRange<Int> { Frequency.selectableCounts }

    var body: some View {
        NavigationStack {
            // A plain stack rather than a Form.
            //
            // Three rows here draw their own platter, and inside a Form each
            // one was fighting a different piece of the list's own styling: the
            // section background, the row background, the row insets. The
            // result was three radii — measured at 4pt down from the top edge,
            // the corners were inset 9px, 15px and 41px — for three things
            // meant to look identical. Outside a list there is nothing to
            // override, and all three now measure 20/12/7/4 at 2/4/6/8pt down.
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        Button { isPickingIcon = true } label: {
                            // No chevron badge. It was there to say the icon
                            // could be changed, back when the glyph sat loose
                            // inside the name field and read as decoration. On
                            // its own platter it is plainly a control, and the
                            // badge was a label on something already labelled.
                            HabitIconView(icon: icon, size: Self.iconSize)
                                .frame(width: Self.rowHeight, height: Self.rowHeight)
                                .background(platter)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Icon")
                        .accessibilityHint("Choose a different icon")
                        .accessibilityAddTraits(.isButton)

                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.sentences)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .padding(.horizontal, Self.namePadding)
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.rowHeight)
                            .background(platter)
                    }

                    // One platter, and now one row on it. It held two while a
                    // habit could be counted within a day as well as across a
                    // week (#209): the kind and the count read top to bottom as
                    // a single decision. There is one kind left, so the row
                    // that chose between them is gone and the count is the
                    // whole decision.
                    frequencyRow
                        .frame(height: Self.rowHeight)
                        .background(platter)

                    if isEditing {
                        // No platter and no explanation. The confirmation
                        // dialog says what deleting costs, at the moment it
                        // costs it — a sentence under the button says it to
                        // everyone who is only passing by.
                        //
                        // Explicitly red: `role: .destructive` would colour it
                        // for free, except the app sets a white tint at the
                        // root and that wins.
                        Button("Delete Habit", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
            }
            .background(Color(.systemGroupedBackground))
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
        // This view is a sheet, and `RootTabView`'s copy of this alert cannot
        // present under an active sheet — a save failure in here would be
        // feedback nobody sees. See `operationNoticeAlert()` (#282).
        .operationNoticeAlert()
    }

    /// The background every platter draws, at one radius for all three.
    private var platter: some View {
        RoundedRectangle(cornerRadius: Self.platterRadius, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
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
            stepButton("minus", enabled: count.wrappedValue > countRange.lowerBound) {
                count.wrappedValue -= 1
            }

            HStack(spacing: 0) {
                // The count glows, and the `x` is part of the count rather
                // than part of the sentence: "7x" is the value the steppers
                // move, and splitting the multiplier off into the grey left
                // the lit part reading as a bare number.
                Text("\(count.wrappedValue)x")
                    .monospacedDigit()
                    .glowing(halo: GlowPalette.labelHalo)
                Text(" per week")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            stepButton("plus", enabled: count.wrappedValue < countRange.upperBound) {
                count.wrappedValue += 1
            }
        }
        // Inset from the platter's edges. Hard against them the controls read
        // as part of the container rather than as things inside it.
        .padding(.horizontal, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Times per week")
        .accessibilityValue("\(count.wrappedValue)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where count.wrappedValue < countRange.upperBound:
                count.wrappedValue += 1
            case .decrement where count.wrappedValue > countRange.lowerBound:
                count.wrappedValue -= 1
            default:
                break
            }
        }
    }

    /// Minus and plus, each on its own platter.
    ///
    /// They used to sit bare inside the row's platter, which made the two
    /// controls tapped most often the only things on this screen that did not
    /// look tappable — the icon, the name field and the toggle's segments all
    /// have a face of their own.
    ///
    /// The face cannot be the row's own `secondarySystemGroupedBackground`,
    /// which is what it is sitting on and would vanish into. It is a system
    /// fill for the same reason this whole screen uses system semantic colours
    /// (docs/decisions.md, "Two greys"): the editor is the system's surface,
    /// and a raised control here should track whatever the OS does to raised
    /// controls.
    ///
    /// The platter *is* the hit target rather than a smaller decoration inside
    /// it, so what looks pressable and what is pressable are the same rectangle.
    private func stepButton(
        _ symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: Self.stepSize.width, height: Self.stepSize.height)
                .background(
                    RoundedRectangle(cornerRadius: Self.stepRadius, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
                .contentShape(Rectangle())
        }
        // Borderless, or a Form row treats its whole width as one button and
        // either control fires whichever was tapped.
        .buttonStyle(.borderless)
        .disabled(!enabled)
        // The face dims with the glyph. `.disabled` alone fades the symbol and
        // leaves the platter lit, which reads as a live control that ignores
        // you — worse than one that plainly says it is spent.
        .opacity(enabled ? 1 : Self.stepDisabledOpacity)
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
        if let weekly = habit.frequency.slotCount {
            timesPerWeek = weekly
        }
    }

    private func delete() {
        guard let habit else { return }
        do {
            try HabitStore(context: context).delete(habit)
            dismiss()
        } catch {
            HabitStore.report(error, operation: "delete")
            // Destructive: no retry. The delete rolled back and the editor
            // stays up, still showing the habit that is still there (#282).
            OperationNotices.shared.report(.delete)
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
            dismiss()
        } catch {
            HabitStore.report(error, operation: isEditing ? "update" : "addHabit")
            // The save rolled back and `dismiss()` was never reached, so the
            // editor still holds everything that was typed; the retry re-runs
            // the same save over the same fields (#282).
            OperationNotices.shared.report(.save) { save() }
        }
    }
}
