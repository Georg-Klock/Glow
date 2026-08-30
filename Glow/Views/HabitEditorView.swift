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

    /// How wide the typed name wants to be with nothing stopping it, and how
    /// much width the row actually gives it. Both measured off real `Text`
    /// views in the row's own font and the row's own layout, rather than
    /// computed — the thing that decides where the ellipsis goes is the thing
    /// being asked, so the warning and the preview cannot disagree about
    /// whether there is one. When the name fits, the two are equal.
    @State private var idealNameWidth: CGFloat = 0
    @State private var grantedNameWidth: CGFloat = 0
    /// The sheet's own width, which on a phone is the window's, which is what
    /// This Week measures its rows against. Starts at the widget's width so the
    /// first pass is a real row rather than a zero-wide one.
    @State private var sheetWidth: CGFloat = WidgetMetrics.largeWidth

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

                    // The name as the app will draw it, from the first letter
                    // on. See `namePreview`.
                    if !trimmedName.isEmpty { namePreview }

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
            // Outside the content's own padding: what the grid divides up is
            // the window's width, not this stack's.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                sheetWidth = width
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

    // MARK: - Where the name is cut

    /// The row a habit name is drawn in — This Week's own, built the way
    /// `WeeklyGridView` builds it: the window's width, less the panel's margin
    /// on both sides. Not a copy of the grid's numbers, the same call.
    ///
    /// **The screen's row and the widget's row are one row at two sizes.**
    /// `RowGeometry` is the large widget times one factor — the panel's width
    /// over 338 — and that factor is applied to `textSize` as well as to the
    /// label column. So `nameMaxWidth / textSize` is `73.5 / 12` on This Week
    /// whatever phone it is, and `73.5 / 12` in the widget. #405 assumed
    /// otherwise, on the strength of this type's own stale header comment;
    /// Dynamic Type came out of `RowGeometry` on 2026-08-24 (docs/decisions.md)
    /// and nothing has scaled independently since. `RowGeometryTests` holds
    /// that ratio now.
    ///
    /// Which is why one preview can be honest about both. Measured on a 390pt
    /// phone — panel 350, scale 1.036, so the grid's row is 12.43pt against the
    /// widget's 12 — "Watch Sunset Every Evening" cuts at "Watch Su…" on This
    /// Week, at "Watch Su…" in the widget rendered on the Widgets tab, and at
    /// "Watch Su…" here. Rendered at the grid's scale rather than the widget's
    /// because that is the row the person is one tap away from looking at.
    private var rowPreview: RowGeometry {
        RowGeometry(totalWidth: max(0, sheetWidth - GridMetrics.horizontalPadding * 2))
    }

    /// Whether the name gets less room than it wants, and so ends in an
    /// ellipsis.
    ///
    /// **Not `idealNameWidth > nameMaxWidth`**, which was the first version of
    /// this and was a character optimistic on the screenshot that caught it.
    /// `nameMaxWidth` is a ceiling the row never reaches: `HabitRowView` holds
    /// the whole label to `.frame(width: labelWidth)` when it is not editing,
    /// and `WeekWidgetView` does the same, so after the icon column, the two
    /// `HStack` gaps and the trailing spacer, what is left for the name is
    /// 65pt at a 12pt text size where `nameMaxWidth` says 73.5 — measured off
    /// the row below at 67.3pt on a 390pt phone, whose scale is 1.0355.
    ///
    /// Which is why nothing here recomputes that: the row below *is* the row,
    /// and it reports what the name was actually given.
    private var isNameCut: Bool { idealNameWidth > grantedNameWidth }

    /// The typed name with nothing holding it back, which is the width the row
    /// is not going to give it.
    ///
    /// **In the layout, not in a `.background`.** It was a background, and on
    /// the New Habit sheet the warning never appeared for a 24-character name:
    /// background content was not re-measured as the field's text changed, so
    /// both widths stayed at whatever the first pass saw. A `0 × 0` frame costs
    /// the same nothing and is measured every pass.
    private var idealNameProbe: some View {
        Text(trimmedName)
            .font(.system(size: rowPreview.textSize))
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                idealNameWidth = width
            }
            .frame(width: 0, height: 0)
            .hidden()
    }

    /// `HabitRowView`'s label, laid out the way that view lays it out when it is
    /// not editing: the icon column, the name, a spacer, and the whole thing
    /// held to the label column's width.
    ///
    /// **The arrangement is copied, not the numbers.** Which width the name ends
    /// up with is decided by this whole stack rather than by any one constant
    /// in it, so reproducing the stack is the only way the sheet and the row
    /// stay in step through a change to either.
    ///
    /// Editing is not reproduced. `HabitRowView` drops the spacer and the column
    /// width while the list is in edit mode, which gives the name more room —
    /// but that is a transient state of the list, not how the habit is read, and
    /// a preview should show the narrower of the two.
    private var rowLabel: some View {
        HStack(spacing: rowPreview.iconGap) {
            HabitIconView(icon: icon, size: rowPreview.iconSize)
                .frame(width: rowPreview.iconWidth)
            Text(trimmedName)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: rowPreview.nameMaxWidth, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    grantedNameWidth = width
                }
            Spacer(minLength: 0)
        }
        .font(.system(size: rowPreview.textSize))
        .frame(width: rowPreview.labelWidth, alignment: .leading)
    }

    /// The habit's row, drawn here exactly as This Week and the widget will draw
    /// it, so the ellipsis in the sheet is the ellipsis that ships.
    ///
    /// **A preview, not a counter.** A counter would have to name a number of
    /// letters, and there is no such number: the limit is a width, so
    /// "Illinois" and "Watch Waves" reach it at different lengths. And **not a
    /// cap on the field**: what is stored is what was typed, unchanged. This
    /// shows; it does not edit.
    ///
    /// **Shown from the first letter, not only once the name overruns.** The
    /// line under it is what changes — the row is the same row either way, and
    /// a block that appears at one keystroke and vanishes at the next is a
    /// worse way to say the same thing. It costs one 12pt row and one footnote,
    /// and it means the ellipsis, drawn by SwiftUI rather than predicted here,
    /// is what carries the warning.
    ///
    /// Grey rather than amber. `GlowPalette.warning` is documented as the app's
    /// one non-white colour, reserved for saying the glow is unavailable — this
    /// is not that, and widening it is a palette decision rather than a
    /// side effect of this screen.
    private var namePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                idealNameProbe
                rowLabel
            }

            Text(
                isNameCut
                    ? "Cut off here on This Week and in the widget."
                    : "How it reads on This Week and in the widget."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.namePadding)
        // One announcement rather than a glyph, a fragment of a name and a
        // sentence read as three stops.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isNameCut
                ? "This name is too long. On This Week and in the widget it is cut off."
                : "On This Week and in the widget this name is shown in full."
        )
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
                    .glowing()
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
