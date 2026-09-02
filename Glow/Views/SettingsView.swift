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

    /// The power-state notification does not arrive while the app is
    /// suspended, so the flag is re-read when the scene comes back — the same
    /// pairing `WeeklyGridView` uses.
    @Environment(\.scenePhase) private var scenePhase

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

    /// Low Power Mode switches the glow off, and this screen is where the glow
    /// is demonstrated — so the preview has to be able to say so (#396). Its
    /// own monitor: the grid holds one too, and an `@Observable` watching a
    /// process-wide notification is cheap enough that a shared one would only
    /// add a lifetime to reason about.
    @State private var lowPower = LowPowerMonitor()

    /// The two EDR values Settings names: what iOS is granting now, and what
    /// the current display configuration could grant at most. A view-bound
    /// task refreshes the snapshot while this tab is visible (#422).
    @State private var headroom = EDRHeadroomSnapshot.mainScreen

    /// Whether the explanation sheet is up. The grid announces the condition
    /// once, unprompted; this screen never does — here the notice is something
    /// the person tapped the preview to ask for.
    @State private var isShowingLowPowerNotice = false

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

    var body: some View {
        NavigationStack {
            form
            // True black under the whole screen rather than the grouped
            // background, so the preview sits on the same black the grid uses
            // and there is no seam where the row would have been.
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
            // The notification the monitor watches is not delivered while the
            // app is suspended, so coming back to the foreground is its own
            // read. `WeeklyGridView` pairs the two the same way.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { lowPower.refresh() }
            }
            // `currentEDRHeadroom` has no change notification. A task is tied
            // to this screen's visibility, so polling stops when Settings
            // disappears; changing scene phase cancels and restarts it too.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await refreshHeadroomWhileVisible()
            }
            // Both of these change what a widget draws: the week's first day
            // moves every column, and the glow level is the brightness the
            // marks are rendered at. The widget is not told when either moves,
            // so Settings tells it (#134).
            //
            // There were three. The rest day emptied a column and withheld its
            // taps, and it had the only reload of the three until #134 added
            // the others; it is gone from this screen entirely (#390).
            .onChange(of: firstWeekday) { _, _ in WidgetRefresh.invalidate() }
            .onChange(of: peak) { _, _ in WidgetRefresh.invalidate() }
        }
    }

    private var form: some View {
            Form {
                // The preview is a row of the Form, so it scrolls with
                // everything else (#109). It was pinned above the Form for one
                // release because #91 measured its halo being cut and blamed
                // the row; the row was innocent, and there is no halo to cut
                // any more (#394).
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
                // No section gap under it. The preview's own padding is
                // already a band of black, and the Form's gap on top of that
                // reads as the first section having drifted down the screen.
                .listSectionSpacing(0)

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

                } header: {
                    Text("Glow")
                } footer: {
                    // Outside the platter again (#474). The compact wording
                    // from #395 stays: moving the explainer does not restore
                    // the repetition that was removed with it.
                    Text(Self.glowNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    // The explainer belongs outside the control's platter
                    // again; all three shortened variants remain (#474).
                    Text(popNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // One row now. This section held the rest day too — a toggle
                // and, when it was on, a day picker — and it was built as one
                // section on purpose, so that "which seven days a week is" and
                // "which of them the app stops asking about" read as one
                // subject. The second half is retired for MVP scope (#390);
                // what is left is the week's first day.
                Section {
                    Picker("Week starts on", selection: $firstWeekday) {
                        ForEach(WeekPreferences.pickerOrder, id: \.self) { weekday in
                            Text(weekdayName(weekday)).tag(weekday)
                        }
                    }
                } header: {
                    Text("Week")
                } footer: {
                    // The shortened sentence stays, outside the platter
                    // whose picker it explains (#474).
                    Text(Self.weekNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            // The same sheet the grid's strip opens, reached from the same
            // condition — one explanation of why the glow is off, not two.
            .sheet(isPresented: $isShowingLowPowerNotice) {
                LowPowerNoticeView(headroom: lowPower.currentHeadroom)
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
    /// **The band of black around it is now plain spacing** (#394). It used to
    /// be a reservation, derived from the halo's own radius times the largest
    /// scale the slider could ask for times a measured Gaussian reach — three
    /// terms, none of them a spacing decision, all of them there because a
    /// shadow painted well past the radius it was blurred by and #91 measured
    /// the column stepping 33 → 0 where the row cut it. With no shadow to cut,
    /// nothing derives this: a lit mark ends at its own silhouette, and what is
    /// left is how much black the preview wants around it.
    ///
    /// The footprint always stays occupied (#396, #497). Low Power Mode takes
    /// priority because it is the condition the person cannot leave from this
    /// screen; otherwise 1× puts a neutral "Glow off" capsule where the live
    /// tile stood. Both alternatives have the tile's exact size, so moving the
    /// slider never inserts a Form section or moves anything below it.
    private var preview: some View {
        previewContent
            .padding(.vertical, Self.previewPadding)
            .frame(maxWidth: .infinity)
            .background(Color.black)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch GlowSettings.previewState(peak: peak, lowPower: lowPower.isLowPowerMode) {
        case .lowPower:
            LowPowerPreviewNotice(size: Self.previewSize) {
                isShowingLowPowerNotice = true
            }
        case .off:
            GlowOffPreviewNotice(size: Self.previewSize)
        case .glow:
            GlowImageView(size: Self.previewSize)
        }
    }

    private static let previewSize = CGSize(width: 120, height: 40)
    /// Chosen by eye against the Form's own rhythm, not derived from anything.
    private static let previewPadding: CGFloat = 24

    /// How much the Dynamic Island says.
    ///
    /// A binding rather than `@AppStorage`, because the default is
    /// **everything** (#185) and `@AppStorage` hands back `0` for a key nobody
    /// has written — a plain stored default reads as whatever `0` maps to
    /// until it is changed twice. `PopPreferences` keeps the sentinel; this
    /// reflects it.
    ///
    /// **A plain synchronous write, and #203 asked for `withAnimation`.** The
    /// line under this picker is a section footer again (#474), so a change in
    /// its line count would resize the section and move everything below it.
    /// That move snaps. Wrapping the write does not change it: built with a
    /// three-second
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

    /// What the current choice does, in one short line per choice.
    ///
    /// Three sentences that were 5, 25 and 21 words are 5, 5 and 9 (#395).
    /// The cut is the same in all three: the Dynamic Island is named once, and
    /// what it responds to is named once, because the picker directly above
    /// has already said which of the three this is. "for a moment" went
    /// everywhere — the Island is not a place anything stays.
    ///
    /// **Everything lost a clause because the clause stopped being true**
    /// (#420). It read that the Island "says something different when that
    /// finishes the day or the week", which described the two vocabularies
    /// `GoalPop` used to hold. There is one pool of phrases now, so a goal
    /// completion no longer says *more* than a routine one — it says one line,
    /// the same as every other log. What Everything means is the frequency,
    /// and that is the whole sentence.
    private var popNote: String {
        switch popLevel {
        case .off:
            "The Dynamic Island stays quiet."
        case .everything:
            "The Dynamic Island answers every log."
        case .goals, .unset:
            "The Dynamic Island answers a finished day or week."
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

    /// Weekday names from the calendar, so a non-English locale gets its own.
    private func weekdayName(_ weekday: Int) -> String {
        let calendar = WeekCalendar.calendar
        let symbols = calendar.standaloneWeekdaySymbols
        guard symbols.count == 7, (1...7).contains(weekday) else { return "" }
        return symbols[weekday - 1]
    }

    /// The requested brightness and both meanings of display headroom in one
    /// sentence.
    ///
    /// `currentEDRHeadroom` is the live grant; `potentialEDRHeadroom` is the
    /// display configuration's ceiling. Calling the latter what the screen
    /// allows "right now" was the bug in #422. The fixed labels keep the
    /// distinction beside the slider instead of making either value explain
    /// itself elsewhere.
    ///
    /// At the bottom of the range the aim is dropped rather than printed as
    /// "off": the amber notice directly below already says the glow is off, and
    /// what is still worth reading is what the screen grants and could grant.
    private var readout: String {
        guard peak > GlowSettings.range.lowerBound else {
            return headroom.summary
        }
        return String(format: "Aiming for %.0f×", peak) + " — " + headroom.summary
    }

    /// Samples immediately and then once a second until SwiftUI cancels the
    /// task. One second keeps "right now" current without running a display
    /// poll anywhere except the visible Settings screen.
    @MainActor
    private func refreshHeadroomWhileVisible() async {
        while !Task.isCancelled {
            headroom = .mainScreen
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

    /// Why the week's first day is more than a column order.
    ///
    /// One control, one line. The paragraph that described the rest day went
    /// with the rows that set it (#390), and what was left — "Week start also
    /// sets which seven days a weekly goal counts over" — spends half its
    /// words restating the row it now sits directly under (#395).
    private static let weekNote = "Weekly goals count from this day."

    /// What the slider trades, which is the one thing it never said (#424).
    ///
    /// This row used to carry the headroom claim — that what the screen grants
    /// "changes with ambient light, brightness and heat" — and #422 is open on
    /// whether that is true: `UIScreen.h` attributes `potentialEDRHeadroom`'s
    /// variation to display *configuration* and `referenceDisplayModeStatus`,
    /// and settling it needs a device. The sentence goes rather than gets
    /// corrected, which is what #424 decided independently: the number it
    /// annotated is already on the row above, and the one thing this section
    /// never said is what the slider costs. #422 now settles the two values in
    /// the readout itself.
    ///
    /// **"Open habits" is the exact set, not a loose phrase.** The slider
    /// drives the HDR tile, and the tile only ever reaches what is still
    /// actionable — `SlotMarkView` routes `.openToday` through `GlowImageView`,
    /// while `.doneToday` and `.donePast` take a flat fill and no tile at all.
    /// A completion genuinely does not brighten with this slider.
    private static let glowNote =
        "A brighter glow makes the open habits stand out. Your eye adapts to "
            + "it, so everything else reads duller in exchange."

}

/// The neutral state that replaces the preview at 1× (#497).
///
/// It is deliberately not the amber Low Power surface: this is a slider
/// position somebody chose, not a condition imposed by iOS. The visible copy
/// fits the preview's capsule; the complete reassurance remains available to
/// VoiceOver without making the fixed footprint grow.
private struct GlowOffPreviewNotice: View {
    let size: CGSize

    var body: some View {
        Label("Glow off", systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(width: size.width, height: size.height)
            .background {
                Capsule(style: .continuous).fill(Color.white.opacity(0.08))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Glow off. Today's slot still shows, unlit.")
    }
}

/// A named pair because UIKit's two headroom properties answer different
/// questions and putting either in an unlabelled `Double` caused #422.
struct EDRHeadroomSnapshot: Equatable, Sendable {
    let current: Double
    let maximum: Double

    @MainActor
    static var mainScreen: Self {
        Self(
            current: Double(UIScreen.main.currentEDRHeadroom),
            maximum: Double(UIScreen.main.potentialEDRHeadroom)
        )
    }

    var summary: String {
        String(format: "%.1f× right now · %.1f× maximum", current, maximum)
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
