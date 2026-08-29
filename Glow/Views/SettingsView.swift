import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// Settings, in three clusters: **Glow**, **Week**, **Data**.
///
/// Glow leads because it is the product rather than a preference about it.
/// Week holds both controls that decide what a week is — where it starts and
/// which day the app stops asking about — which were two sections, one of them
/// headerless. Data holds the export beside the one control that writes
/// something invented into the same store.
///
/// A tab now rather than a sheet, so there is no Done button and nothing to
/// dismiss — the changes are live and the way out is the tab bar.
struct SettingsView: View {
    @Environment(\.modelContext) private var context

    /// Every habit, per-day and per-week alike, because an export of "your
    /// history" that quietly left one kind out would be worse than no export.
    @Query(sort: [SortDescriptor(\Habit.sortOrder)]) private var habits: [Habit]

    /// The file to hand to the share sheet, or nil while there is none.
    /// Written only when the button is pressed — see `HistoryFile`.
    @State private var exportFile: HistoryFile?

    /// Where an export lives between being written and being shared, and what
    /// takes it away again. See `ExportStore` and #142.
    private let exportStore = ExportStore()

    /// The file the share sheet is currently holding.
    ///
    /// Kept beside `exportFile` rather than read off it, because `sheet(item:)`
    /// clears its own binding *before* `onDismiss` runs — so a cleanup that
    /// asked `exportFile` for the URL would find nil every time and delete
    /// nothing, which is the failure this issue is about wearing a different
    /// hat.
    @State private var pendingExport: URL?
    @State private var isChoosingFormat = false

    /// Mirrors `PopPreferences.level`, so the picker moves on the tap.
    @State private var popLevel = PopPreferences.level

    @AppStorage(GlowSettings.key, store: GlowSettings.store)
    private var peak: Double = GlowSettings.defaultValue

    /// On means off: the toggle stores the halo's *removal*, so a fresh
    /// install — nothing stored — ships the halo, and flipping the switch on
    /// is what takes it away (#313). The HDR fill is a separate layer and
    /// stays either way.
    @AppStorage(GlowSettings.haloDisabledKey, store: GlowSettings.store)
    private var haloDisabled: Bool = false

    /// Mirrors `DemoHistory.isSeeded`. State rather than a computed binding so
    /// the toggle animates the flip it caused instead of waiting on a re-read.
    @State private var isDemoSeeded = false

    /// Mirrors `DebugToday.override()`, for the same reason `isDemoSeeded`
    /// mirrors the record: a `Date?` in the App Group is not something
    /// `@AppStorage` can bind to, so the control is driven from state and the
    /// store is written behind it. Nil is off.
    @State private var overrideDay: Date?

    /// Whether the reset confirmation is up, and what has been typed into it.
    /// See `resetRow`.
    @State private var isConfirmingReset = false
    @State private var typedConfirmation = ""

    @AppStorage(WeekPreferences.firstWeekdayKey, store: GlowSettings.store)
    private var firstWeekday: Int = WeekPreferences.defaultFirstWeekday

    /// Zero means none. `AppStorage` cannot hold an optional Int, and a
    /// sentinel here is better than a parallel "has rest day" flag that could
    /// disagree with the day itself.
    @AppStorage(WeekPreferences.restDayKey, store: GlowSettings.store)
    private var restDay: Int = 0

    var body: some View {
        NavigationStack {
            form
            // True black under the whole screen rather than the grouped
            // background, so the halo falls off into the same black the grid
            // uses and there is no seam where the row would have been.
            .background(Color.black)
            // Everything that scrolls up to the top of the screen dissolves
            // into black before it gets there. See `TopFade`.
            .overlay(alignment: .top) { TopFade() }
            .navigationTitle("Settings")
            // The bar is opaque from the start, because the preview scrolls
            // under it now. Measured on screen: a column down the left edge
            // reads 0,0,0 straight through the bar and past its boundary — no
            // grey band across the one screen that exists to show the product,
            // which is #87's argument, and no seam.
            //
            // **Without a `Color`.** `.toolbarBackground(Color.black, for:)`
            // compiles, renders black, and silently removes the title — large
            // and inline both. `.visible` alone over this view's own black
            // background gives the same black and keeps the title.
            //
            // The alternative was to leave the bar as it was, and it is worse
            // than it sounds: the system material dims the capsule to grey and
            // prints "Settings" on top of it, so the product's one lit object
            // slides under the title as a smear. Screenshotted before choosing.
            //
            // **It does not make the bar opaque, and the measurement above was
            // read as saying it does.** Scrolled 200pt and screenshotted at
            // rest, the preview capsule reads 249,249,248 through the bar with
            // the inline title printed over it. The column that read 0,0,0 was
            // a column with nothing bright behind it. The bar is still declared
            // visible — it is what stops the material smear — and what actually
            // keeps light off the top of the screen is `TopFade`. See #195.
            .toolbarBackground(.visible, for: .navigationBar)

            .onAppear {
                isDemoSeeded = DemoHistory(context: context).isSeeded
                // Re-read rather than assumed: the banner on another screen
                // can have cleared it, and the week can have rolled over and
                // expired it, since this view was last built.
                overrideDay = DebugToday.override()
            }
            // Cleared from a banner on another tab, this row has to follow.
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                let current = DebugToday.override()
                if current != overrideDay { overrideDay = current }
            }
            // Covers the toggle and the day picker both: the widget draws the
            // same week and withholds the same taps, and it is not told when
            // the setting moves.
            // Three preferences, and every one of them changes what a widget
            // draws: the rest day empties a column and withholds its taps, the
            // week's first day moves every column, and the glow level is the
            // brightness the marks are rendered at. Only the first had a reload
            // (#134).
            .onChange(of: restDay) { _, _ in WidgetRefresh.invalidate() }
            .onChange(of: firstWeekday) { _, _ in WidgetRefresh.invalidate() }
            .onChange(of: peak) { _, _ in WidgetRefresh.invalidate() }
        }
    }

    private var form: some View {
            Form {
                // The preview is a row of the Form, so it scrolls with
                // everything else (#109). It was pinned above the Form for one
                // release because #91 measured its halo being cut and blamed
                // the row; the row was innocent. See `previewHalo`.
                //
                // `Color.clear`, not black: the Form already runs
                // `.scrollContentBackground(.hidden)` over a black background,
                // so a row background would only put the panel back.
                Section {
                    preview
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                // No section gap under it. The halo's own reservation is
                // already a band of black, and the Form's gap on top of that
                // reads as the first section having drifted down the screen.
                .listSectionSpacing(0)

                // Directly under the thing it explains. It used to sit three
                // sections down, below the Glow slider and the whole "Say well
                // done" cluster, so a dark preview was two unrelated controls
                // away from the one line saying why it is dark.
                //
                // **No `.listSectionSpacing(0)` of its own, and #201 asked for
                // one.** The modifier sets the gap *below* the section it is on,
                // not above it: the preview's own zero already lands on whatever
                // follows, so the banner arrives tight against the reserved band
                // either way. Measured, glow at minimum, both builds — the
                // banner sits at 418–470pt in both; carrying the modifier only
                // pulls the Glow section up from 528pt to 510pt, closing the
                // one gap #201 asked to keep.
                if peak <= GlowSettings.range.lowerBound {
                    Section {
                        Label("Glow off. Today's slot still shows, unlit.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                // Glow leads: it is the one control here that is the product
                // rather than a preference about it.
                Section {
                    // One step per whole multiple of SDR white — eight stops
                    // for an eight-times ceiling (`GlowSettings.range`), not
                    // the fifteen a half-step gave. `readout` already rounds
                    // to `%.0f×`, so nothing downstream expected the half
                    // steps in between.
                    Slider(
                        value: $peak,
                        in: GlowSettings.range,
                        step: 1
                    ) {
                        Text("Glow")
                    } minimumValueLabel: {
                        Image(systemName: "sun.min")
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.secondary)
                    }
                    .tint(GlowPalette.color)

                    // One sentence rather than two labelled rows of jargon.
                    // What the glow aims for and what the panel is granting are
                    // a single fact in two halves; read as a sentence, the gap
                    // between them is obvious instead of arithmetic.
                    Text(readout)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    // "No halo", not "Halo": the row stores the removal, so
                    // the switch reads on when the halo is off and a fresh
                    // install shows it off — the shipped look unchanged
                    // (#313). Explicit `controlTint`, because the root tint
                    // is pure white and a `Toggle` filled with it disappears
                    // (#124).
                    Toggle("No halo", isOn: $haloDisabled)
                        .tint(GlowPalette.controlTint)
                } header: {
                    Text("Glow")
                } footer: {
                    Text("What the screen grants changes with ambient light, brightness and heat. No halo keeps the marks lit and stops them spreading light around themselves.")
                }

                Section {
                    // Three states, so it is a picker rather than a toggle
                    // (#119). Segmented rather than a menu because the three
                    // are a scale — quiet, the rare thing, everything — and a
                    // scale reads better laid out than hidden behind its own
                    // current value.
                    Picker("Say well done", selection: popBinding) {
                        ForEach(Self.popChoices, id: \.0) { level, title in
                            Text(title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    // The label goes in the header, because a segmented picker
                    // in a `Form` drops it — leaving three unlabelled words
                    // where a row used to say what it was for.
                    .labelsHidden()
                } header: {
                    Text("Say well done")
                } footer: {
                    Text(popFooter)
                }

                // One subject, one section: which seven days a week is, and
                // which of them the app stops asking about. They were two
                // sections, and the rest day's had no header at all — so the
                // single most consequential setting in the app read as an
                // afterthought hanging below the week.
                Section {
                    Picker("Week starts on", selection: $firstWeekday) {
                        ForEach(WeekPreferences.pickerOrder, id: \.self) { weekday in
                            Text(weekdayName(weekday)).tag(weekday)
                        }
                    }

                    Toggle("Rest day", isOn: restDayBinding)
                        .tint(GlowPalette.controlTint)
                    if restDay != 0 {
                        Picker("Day", selection: $restDay) {
                            ForEach(WeekPreferences.pickerOrder, id: \.self) { weekday in
                                Text(weekdayName(weekday)).tag(weekday)
                            }
                        }
                    }
                } header: {
                    Text("Week")
                } footer: {
                    Text(weekFooter)
                }

                // Data last: the export, beside the one control that writes
                // something invented into the same store.
                Section {
                    Button {
                        isChoosingFormat = true
                    } label: {
                        Label("Export History", systemImage: "square.and.arrow.up")
                    }
                    .disabled(habits.isEmpty)

                    Toggle("Demo history", isOn: demoBinding)
                        .tint(GlowPalette.controlTint)

                    // The same tier as demo history, and in the same section:
                    // both write real rows into the real store, and this one
                    // decides what day they are dated to. Not `#if DEBUG` —
                    // see `DebugToday` for why a build that compiles it out is
                    // a build where it is missing from the only place it is
                    // needed.
                    Toggle("Debug: Override Today", isOn: overrideBinding)
                        .tint(GlowPalette.controlTint)
                    if overrideDay != nil {
                        Picker("Day", selection: dayBinding) {
                            ForEach(DebugToday.choices(), id: \.self) { day in
                                Text(DebugToday.dayName(day)).tag(day)
                            }
                        }
                    }

                    resetRow
                } header: {
                    Text("Data")
                }
                // No footer, decided on purpose (#317): the section grew a
                // six-paragraph wall of explanation under its last row, and
                // the answer was to remove it rather than trim it.
            }
            .scrollContentBackground(.hidden)
            // A choice of two, rather than a format setting nobody would ever
            // change twice. CSV opens in a spreadsheet; JSON parses.
            .confirmationDialog(
                "Export History",
                isPresented: $isChoosingFormat,
                titleVisibility: .visible
            ) {
                Button("CSV") { export(as: .csv) }
                Button("JSON") { export(as: .json) }
                Button("Cancel", role: .cancel) {}
            }
            // The share sheet is the only way out of the app, and it opens on
            // a tap. Nothing here uploads.
            // `onDismiss` covers sharing and cancelling both, because they are
            // the same event as far as the file is concerned — and treating
            // them as two is how one of them gets missed.
            .sheet(item: $exportFile, onDismiss: { discardExport() }) { file in
                ShareSheet(url: file.url)
            }
            .alert("Reset to Default Habits?", isPresented: $isConfirmingReset) {
                TextField("Type \(ResetConfirmation.word) to confirm", text: $typedConfirmation)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { typedConfirmation = "" }
                Button("Reset", role: .destructive) { performReset() }
                    .disabled(!ResetConfirmation.isConfirmed(typedConfirmation))
            } message: {
                Text(
                    "Deletes every habit and every completion, then installs "
                        + "the current defaults. This cannot be undone."
                )
            }
    }

    /// A live slot, rendered by the same code path the grid uses, so the
    /// slider is judged against the real thing rather than a swatch that
    /// approximates it.
    ///
    /// **Above the form, not inside it.** A `Form` row bounds its content, so a
    /// halo drawn in one is clipped by the row's frame however much padding it
    /// is given — padding only moves the edge. Measured: at exactly the
    /// reserved 34.97pt the column stepped 33 → 0, which is a cut and not a
    /// falloff, and a Gaussian has no end to reserve for anyway. Out here
    /// nothing bounds it. The cost is that it no longer scrolls away, which is
    /// the trade #91 names (#91).
    ///
    /// Which means its halo has to be the real thing too. It used to be cut a
    /// third of the way through its falloff by a hand-typed 22pt of padding
    /// inside a form row — and worst at the top of the slider, which is least
    /// honest exactly where the setting matters most.
    private var preview: some View {
        GlowImageView(size: Self.previewSize)
            .padding(.vertical, Self.previewHalo)
            .frame(maxWidth: .infinity)
            .background(Color.black)
    }

    /// The preview slot, and the room its halo needs.
    ///
    /// **Derived, never typed.** `GlowModifier` casts the halo at
    /// `height * GlowPalette.haloRadius`, multiplied by
    /// `GlowSettings.haloScale(peak)` — which reaches `maxHaloScale` at the
    /// top of the range, well above the shipping default of 2x, and the
    /// reservation has to fit the slider's largest halo rather than the
    /// default's. Reserving anything less cuts the light mid-falloff,
    /// and reserving a constant means it drifts the next time `haloRadius`
    /// moves. This is the same expression the halo is drawn from.
    private static let previewSize = CGSize(width: 120, height: 40)
    private static var previewHalo: CGFloat {
        previewSize.height * GlowPalette.haloRadius
            * CGFloat(GlowSettings.maxHaloScale) * haloReach
    }

    /// How far past its radius a shadow is still visible.
    ///
    /// **This is the number #91 was missing**, and the reason its "correct"
    /// reservation still clipped. `radius` is what `.shadow` blurs by, not how
    /// far the light gets: a Gaussian is still painting well beyond its own
    /// radius, and the row bounded the content at exactly the radius.
    ///
    /// Measured on screen at 12x, from the capsule's edge to the last pixel
    /// above black: 237px at 3.0 px/pt is 79pt, against a 34.97pt radius —
    /// 2.26x. Three is the usual reach quoted for a Gaussian, it is the next
    /// round number above what was measured, and the cost of the margin is
    /// black on black.
    private static let haloReach: CGFloat = 3

    /// How much the Dynamic Island says.
    ///
    /// A binding rather than `@AppStorage`, because the default is
    /// **everything** (#185) and `@AppStorage` hands back `0` for a key nobody
    /// has written — a plain stored default reads as whatever `0` maps to
    /// until it is changed twice. `PopPreferences` keeps the sentinel; this
    /// reflects it.
    ///
    /// **A plain synchronous write, and #203 asked for `withAnimation`.** The
    /// footer under this picker is one sentence, two, or a longer two-clause
    /// one, so it resizes and every section below it moves — and that move
    /// snaps. Wrapping the write does not change it: built with a three-second
    /// linear `withAnimation` around the write, and again with a linear
    /// `animation` modifier keyed to `popLevel` on the `Form` as well, a burst
    /// of screenshots 0.2s apart caught the Week section moving 373pt → 405pt
    /// between two consecutive frames, with no intermediate position in either
    /// build.
    ///
    /// The transaction is not being lost. A control in the same build — the
    /// preview's opacity, driven by the same `popLevel` write — ramped
    /// 254 → 168 across thirteen frames of that same three-second curve while
    /// the sections below still jumped in one. A `Form` section's reflow is
    /// simply not what that animation reaches, so an animated write here would
    /// be a claim the screen does not support. See #203 and #215.
    ///
    /// **The API names are spelled without their parentheses on purpose.**
    /// `ReduceMotionTests` scans source text for the two call shapes and asks
    /// every file that contains one to read the setting; prose naming an API is
    /// indistinguishable from calling it, and this file animates nothing.
    private var popBinding: Binding<PopPreferences.Level> {
        Binding(get: { popLevel }, set: { popLevel = $0; PopPreferences.level = $0 })
    }

    /// The three choices, in the order they escalate.
    private static let popChoices: [(PopPreferences.Level, String)] = [
        (.off, "Never"),
        (.goals, "Goals"),
        (.everything, "Everything"),
    ]

    private var popFooter: String {
        switch popLevel {
        case .off:
            "The Dynamic Island stays quiet."
        case .everything:
            "The Dynamic Island says so for a moment every time you log "
                + "something, and says something different when that finishes "
                + "the day or the week."
        case .goals, .unset:
            "When you finish a habit for the day or the week, the Dynamic "
                + "Island says so for a moment. Not every repetition."
        }
    }

    // MARK: - Export

    /// Writes the file, then hands it to the share sheet — or neither (#282).
    private func export(as format: HistoryExport.Format) {
        guard let url = writeExport(as: format, retry: { export(as: format) })
        else { return }
        exportFile = HistoryFile(url: url)
    }

    /// Writes one export and takes ownership of its lifetime.
    ///
    /// Written at the moment of the tap rather than kept ready: a history file
    /// sitting on disk that nobody asked for is exactly the thing this feature
    /// promises not to make. It goes to the app's own temporary directory,
    /// which the system reclaims.
    ///
    /// **All or nothing** (#282). The snapshots used to come from the
    /// non-throwing helpers, which flatten a failed completion fetch into
    /// empty history — so the one error the share sheet must not paper over
    /// was already erased before the `do` block began, and a person could
    /// share a file silently missing rows. `Habit.fetchedSnapshots` keeps
    /// the failure, and `ExportStore.writeHistory` orders the steps so a
    /// throw anywhere leaves no file: no sheet opens over a partial read,
    /// and the failure is said out loud with a safe retry — an export is a
    /// read, and the caller passes the retry so the way out that failed is
    /// the way that is retried.
    private func writeExport(
        as format: HistoryExport.Format, retry: @escaping @MainActor () -> Void
    ) -> URL? {
        do {
            let url = try exportStore.writeHistory(format: format, exportedAt: Date()) {
                try Habit.fetchedSnapshots(of: habits)
            }
            pendingExport = url
            return url
        } catch {
            HabitStore.report(error, operation: "exportHistory")
            OperationNotices.shared.report(.export, retry: retry)
            return nil
        }
    }

    /// Takes the shared file away once the sheet has gone.
    private func discardExport() {
        guard let url = pendingExport else { return }
        exportStore.discard(url)
        pendingExport = nil
    }

    /// Seeds or removes the invented past. Errors leave the toggle where the
    /// truth is: the state is re-read from the record rather than assumed.
    private var demoBinding: Binding<Bool> {
        Binding(
            get: { isDemoSeeded },
            set: { wantsDemo in
                let demo = DemoHistory(context: context)
                do {
                    if wantsDemo {
                        // The day the app currently believes it is, so a demo
                        // seeded under a debug override leaves *that* day's
                        // slot open rather than the real one (#204).
                        try demo.seed(now: WeekCalendar.today())
                    } else {
                        try demo.remove()
                    }
                } catch {
                    HabitStore.report(error, operation: wantsDemo ? "seedDemo" : "removeDemo")
                    // No retry closure: the toggle below re-reads the record,
                    // so the switch is already showing the truth, and flipping
                    // it again *is* the retry — through the same confirmed
                    // gesture (#282).
                    OperationNotices.shared.report(.demo)
                }
                isDemoSeeded = demo.isSeeded
                // Demo history writes through `DemoHistory` rather than
                // `HabitStore`, so it says so itself. See `WidgetRefresh`.
                WidgetRefresh.invalidate()
            }
        )
    }

    // MARK: - Debug: override today

    /// On means "some day of this week", and the day it starts on is the real
    /// today — the one position that changes nothing until the picker moves.
    ///
    /// Off clears the stored key outright rather than remembering the last day,
    /// because a remembered override is the thing this feature is fenced
    /// against: nothing may survive being switched off.
    private var overrideBinding: Binding<Bool> {
        Binding(
            get: { overrideDay != nil },
            set: { wantsOverride in
                let day = wantsOverride ? WeekCalendar.realToday() : nil
                DebugToday.set(day)
                overrideDay = DebugToday.override()
                // Every surface follows the override, the widget included, and
                // the widget is a second process that is not told when a
                // default moves.
                WidgetRefresh.invalidate()
            }
        )
    }

    private var dayBinding: Binding<Date> {
        Binding(
            get: { overrideDay ?? WeekCalendar.realToday() },
            set: { day in
                DebugToday.set(day)
                overrideDay = DebugToday.override()
                WidgetRefresh.invalidate()
            }
        )
    }

    // MARK: - Reset

    /// The row that opens the confirmation.
    ///
    /// **Red by hand.** `role: .destructive` would colour it for free
    /// everywhere except here: the app sets a pure white tint at the root and
    /// that wins, so a styled destructive control comes back white — the trap
    /// the editor's Delete Habit button and the grid's swipe action both say
    /// out loud, and the one #162 measured at 8077 pixels of a single colour
    /// with no label in it.
    ///
    /// **No "Resetting…" state, and that is not an omission.** #193 allows one
    /// for a slow store, but the reset is a single synchronous `commit()` on
    /// the main actor: nothing can be drawn between the flag going up and
    /// coming down, because the run loop never gets a turn in between. A
    /// spinner that cannot render is a claim about what the app does that is
    /// never true. Measured on a store holding 1,728 completions — it returns
    /// while the alert is still dismissing.
    private var resetRow: some View {
        Button {
            typedConfirmation = ""
            isConfirmingReset = true
        } label: {
            Label("Reset to Default Habits", systemImage: "arrow.counterclockwise")
        }
        .foregroundStyle(.red)
    }

    /// Empties the store and puts the shipped defaults back.
    ///
    /// Synchronously, and #193 says why: this is a rare, explicitly confirmed
    /// action, and a background-context path for something that happens once in
    /// an install's life is machinery nobody would ever get to exercise.
    ///
    /// The order matters at the end. `isDemoSeeded` is state mirroring the
    /// store, and the reset has just deleted every completion the demo
    /// invented — so the toggle is re-read from the record rather than assumed
    /// off, exactly as the toggle's own binding does.
    private func performReset() {
        typedConfirmation = ""
        let demo = DemoHistory(context: context)
        do {
            try HabitStore(context: context).resetToDefaults()
            // The rows the pre-provenance record named are gone with
            // everything else. Dropping the key is tidying, not correctness —
            // see `DemoHistory.discardLegacyRecord`.
            demo.discardLegacyRecord()
        } catch {
            HabitStore.report(error, operation: "resetToDefaults")
            // Destructive, so no retry is offered — `OperationNotices` would
            // drop one anyway. The reset is one transaction, so a failure
            // means the store still holds everything it held, and the message
            // says exactly that; the way to try again is the typed
            // confirmation, again (#282).
            OperationNotices.shared.report(.reset)
        }
        // Whether the reset threw or not: the toggle shows what the store
        // holds, and after a failure that is whatever it held before.
        isDemoSeeded = demo.isSeeded
    }

    /// The toggle turns the sentinel into a real day and back, defaulting to
    /// Sunday because that is the day most people mean by "rest day" — and it
    /// is a default rather than an assumption, since the picker is right there.
    private var restDayBinding: Binding<Bool> {
        Binding(
            get: { restDay != 0 },
            set: { restDay = $0 ? WeekPreferences.sunday : 0 }
        )
    }

    /// Weekday names from the calendar, so a non-English locale gets its own.
    private func weekdayName(_ weekday: Int) -> String {
        let calendar = WeekCalendar.calendar
        let symbols = calendar.standaloneWeekdaySymbols
        guard symbols.count == 7, (1...7).contains(weekday) else { return "" }
        return symbols[weekday - 1]
    }

    /// Both numbers in one sentence.
    ///
    /// They were two labelled rows — "Asking for 12×" and "Screen currently
    /// allows 1.0×" — which is the same information filed as a specification
    /// sheet. Neither number means anything alone: what matters is the gap
    /// between what the app asks for and what the panel is willing to give at
    /// this moment, and a sentence puts the two next to each other where that
    /// gap is legible.
    ///
    /// At the bottom of the range the aim is dropped rather than printed as
    /// "off": the amber notice directly below already says the glow is off, and
    /// what is still worth reading is what the screen could have granted.
    private var readout: String {
        guard peak > GlowSettings.range.lowerBound else {
            return "The screen allows \(ceiling) right now."
        }
        return String(format: "Aiming for %.0f×", peak) + " — the screen allows \(ceiling) right now."
    }

    /// Two controls, one subject, so one footer.
    private var weekFooter: String {
        "Week start also sets which seven days a weekly goal counts over.\n\n"
            + "A rest day is true rest: nothing can be logged on it, nothing "
            + "counts as missed, and the week is not made up around it. "
            + "Anything already on record still counts."
    }

    /// What the display will grant right now — and "now" is load-bearing.
    ///
    /// `potentialEDRHeadroom` moves with ambient light, display brightness and
    /// thermal state, so the same phone reports different numbers indoors and
    /// outdoors, and again once it is warm. Hence "currently": a reading, not a
    /// specification.
    ///
    /// Asking for more than this is not an error and not wasted — it is simply
    /// tone-mapped back down. Showing both numbers is the only honest way to
    /// answer how bright it can get, which depends on the panel and the moment
    /// rather than on the app.
    private var ceiling: String {
        String(format: "%.1f×", UIScreen.main.potentialEDRHeadroom)
    }

}

/// The written file, identified so `sheet(item:)` can present it.
private struct HistoryFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// The system share sheet.
///
/// `ShareLink` would be the SwiftUI way and is not used here: it wants its item
/// at the moment the *view* is built, and this file does not exist until the
/// button is pressed. Writing one eagerly so a `ShareLink` could point at it
/// would leave a history file on disk that nobody asked for, which is the one
/// thing this feature promises not to do.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
