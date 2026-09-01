import SwiftData
import SwiftUI
import WidgetKit

/// The editor's fixed control geometry, kept outside the view so tests can
/// hold the relationship between the row and its step buttons rather than
/// inspecting source text.
enum HabitEditorGeometry {
    /// The icon, name and frequency platters are one height. The step faces
    /// leave this same inset at the row's outer left/right and top/bottom.
    static let rowHeight: CGFloat = 56
    static let stepInset: CGFloat = 10
    /// Width keeps the existing hit target; height makes the vertical margins
    /// equal to `stepInset` (#458).
    /// **88 wide, not 44** (#458 again). At 44 the faces measured ten points
    /// from every edge of the platter — verified off a device screenshot, band
    /// constant to within 0.24pt around the corners — and still read as sitting
    /// too low and too high in it. The gap was never the problem: the platter
    /// is 361 x 56, so a 44pt face is hugged on three sides and opens onto
    /// ~307pt of empty platter on the fourth, and the eye stops reading the
    /// whole platter as the container and reads only its rounded left cap.
    /// Against that cap an even ten points looks like too much air.
    ///
    /// Widening the face rather than heightening it fixes the proportion while
    /// keeping the ten: the inset is unchanged on all four sides, so the
    /// concentric radius below is unchanged too. Height stays 36 — this is a
    /// correction to what the face is shaped like, not to where it sits.
    static let stepSize = CGSize(width: 88, height: 36)
    /// Rounder than the old segmented-control corner, but short of a capsule.
    static let stepRadius: CGFloat = 16
    /// One footnote line, present whether or not it has anything to say. The
    /// warning changes opacity inside this slot rather than entering the
    /// layout, so typing the first too-wide glyph cannot move the field or the
    /// frequency row (#456).
    static let nameHintHeight: CGFloat = 18
    static let nameHintSpacing: CGFloat = 6

    /// The system default a `TextField` used before #456 made the field itself
    /// the compact-row preview. `@ScaledMetric` resolves this base at the
    /// current Dynamic Type size in `HabitEditorView`.
    static let nameFieldBaseTextSize: CGFloat = 17

    /// Enlarging both sides of the compact row's width-to-type ratio keeps the
    /// field's ellipsis on the same character even though the field is easier
    /// to read than the row it previews (#482).
    static func nameFieldWidth(
        rowNameWidth: CGFloat,
        rowTextSize: CGFloat,
        fieldTextSize: CGFloat
    ) -> CGFloat {
        guard rowNameWidth.isFinite,
              rowTextSize.isFinite,
              fieldTextSize.isFinite,
              rowNameWidth >= 0,
              rowTextSize > 0,
              fieldTextSize >= 0 else {
            return 0
        }
        return rowNameWidth * fieldTextSize / rowTextSize
    }
}

enum HabitEditorCopy {
    /// One source for the visible warning and the field's spoken hint.
    static let nameWarning =
        "Short titles work better. Long titles will be cut."
}

/// Add or edit a habit. One sheet for both, since the fields are identical.
struct HabitEditorView: View {
    let habit: Habit?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Restores the field's pre-#456 `.body` size while retaining Dynamic Type.
    /// Its width is scaled by the same resolved value below, so accessibility
    /// sizes do not turn the field into a different truncation preview.
    @ScaledMetric(relativeTo: .body)
    private var nameFieldTextSize = HabitEditorGeometry.nameFieldBaseTextSize

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

    /// One corner for every outer platter on this screen.
    ///
    /// The icon, the name and the stepper were three different heights: two
    /// hand-set and one whatever a Form row happened to size itself to. Now all
    /// three draw their own background at `HabitEditorGeometry.rowHeight`,
    /// which is the only way three rows agree — matching a system row's height
    /// by eye works until the OS changes its padding.
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
                    nameEditor

                    // One platter, and now one row on it. It held two while a
                    // habit could be counted within a day as well as across a
                    // week (#209): the kind and the count read top to bottom as
                    // a single decision. There is one kind left, so the row
                    // that chose between them is gone and the count is the
                    // whole decision.
                    frequencyRow
                        .frame(height: HabitEditorGeometry.rowHeight)
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
    /// label column. So `nameMaxWidth / textSize` is `71.75 / 12` on This Week
    /// whatever phone it is, and `71.75 / 12` in the widget. #405 assumed
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

    /// The compact row's available width enlarged by exactly the same factor
    /// as its type. That preserves the character at which the tail is cut.
    private var nameFieldWidth: CGFloat {
        HabitEditorGeometry.nameFieldWidth(
            rowNameWidth: rowPreview.nameMaxWidth,
            rowTextSize: rowPreview.textSize,
            fieldTextSize: nameFieldTextSize
        )
    }

    /// Whether the name gets less room than it wants, and so ends in an
    /// ellipsis.
    ///
    /// **Still measured rather than compared with a copied constant.** The
    /// first version predicted the cut from `nameMaxWidth` and was a character
    /// optimistic on the screenshot that caught it. The row below is the real
    /// arrangement — icon column, its gap, name and trailing spacer — and it
    /// reports what SwiftUI actually granted at this sheet's width. That keeps
    /// the hint honest if any part of the arrangement moves again.
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

    /// `HabitRowView`'s label measured off-screen, laid out the way that view
    /// lays it out when it is not editing: the icon column, the name, a spacer,
    /// and the whole thing held to the label column's width.
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
    private var rowLabelProbe: some View {
        HStack(spacing: 0) {
            HabitIconView(icon: icon, size: rowPreview.iconSize)
                .frame(width: rowPreview.iconWidth)
                .padding(.trailing, rowPreview.iconGap)
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

    /// Icon picker and name field, with the warning occupying a permanent line
    /// immediately above them.
    ///
    /// The old editor drew a second habit label below the field. That made the
    /// field a place to enter one thing and the row beneath it the place to see
    /// another, and the block's arrival moved the frequency control. The field
    /// is the preview now. Its larger `.body` type and width are the row's type
    /// and width multiplied by one factor, so the hidden probes and the field
    /// still cut at the same character (#456, #482).
    ///
    /// The input remains the full string. Once it is wider than the row, the
    /// native field's scrolling text becomes transparent and a tail-truncated
    /// copy is drawn over the same bounds. The field still owns focus, input,
    /// selection and accessibility; only its pixels are replaced. This is the
    /// deliberate cost of always showing the shipped truncation while focused:
    /// the end being typed is no longer visible after the cut, exactly the
    /// choice made for this issue.
    ///
    /// The amber warning changes opacity inside a fixed-height slot. Empty,
    /// fitting and cut names therefore put every control below them at exactly
    /// the same y-position.
    private var nameEditor: some View {
        VStack(spacing: HabitEditorGeometry.nameHintSpacing) {
            HStack(spacing: 10) {
                Color.clear
                    .frame(width: HabitEditorGeometry.rowHeight, height: 1)

                Text(HabitEditorCopy.nameWarning)
                    .font(.footnote)
                    .foregroundStyle(GlowPalette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isNameCut ? 1 : 0)
                    .accessibilityHidden(!isNameCut)
            }
            .frame(height: HabitEditorGeometry.nameHintHeight)

            HStack(spacing: 10) {
                Button { isPickingIcon = true } label: {
                    // No chevron badge. It was there to say the icon could be
                    // changed, back when the glyph sat loose inside the name
                    // field and read as decoration. On its own platter it is
                    // plainly a control, and the badge was a label on
                    // something already labelled.
                    HabitIconView(icon: icon, size: Self.iconSize)
                        .frame(
                            width: HabitEditorGeometry.rowHeight,
                            height: HabitEditorGeometry.rowHeight
                        )
                        .background(platter)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Icon")
                .accessibilityHint("Choose a different icon")
                .accessibilityAddTraits(.isButton)

                ZStack(alignment: .leading) {
                    HStack {
                        TextField("Name", text: $name)
                            .font(.system(size: nameFieldTextSize))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(isNameCut ? Color.clear : Color.primary)
                            .textInputAutocapitalization(.sentences)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .frame(width: nameFieldWidth, alignment: .leading)

                        Spacer(minLength: 0)
                    }

                    if isNameCut {
                        Text(trimmedName)
                            .font(.system(size: nameFieldTextSize))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(
                                width: nameFieldWidth,
                                alignment: .leading
                            )
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, Self.namePadding)
                .frame(maxWidth: .infinity)
                .frame(height: HabitEditorGeometry.rowHeight)
                .background(platter)
                .accessibilityHint(
                    isNameCut ? HabitEditorCopy.nameWarning : ""
                )
            }

            // Kept in the ordinary layout rather than a background: both
            // probes must be remeasured on every keystroke (#405). Their own
            // explicit geometry is resolved before this zero-sized container
            // removes them from the visible arrangement.
            ZStack(alignment: .topLeading) {
                idealNameProbe
                rowLabelProbe
            }
            .frame(width: 0, height: 0)
            .hidden()
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
        .padding(.horizontal, HabitEditorGeometry.stepInset)
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
    /// At 44 × 36 inside a 56pt row, the visible face leaves the same 10pt at
    /// the row's outer horizontal edges and above and below it (#458).
    private func stepButton(
        _ symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(
                    width: HabitEditorGeometry.stepSize.width,
                    height: HabitEditorGeometry.stepSize.height
                )
                .background(
                    RoundedRectangle(
                        cornerRadius: HabitEditorGeometry.stepRadius,
                        style: .continuous
                    )
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
