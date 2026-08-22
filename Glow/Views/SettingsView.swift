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
/// headerless. Data holds the long view of what is stored beside the one
/// control that writes something invented into it, and where the export lives.
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

    /// Mirrors `DemoHistory.isSeeded`. State rather than a computed binding so
    /// the toggle animates the flip it caused instead of waiting on a re-read.
    @State private var isDemoSeeded = false

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
            .toolbarBackground(.visible, for: .navigationBar)

            .onAppear { isDemoSeeded = DemoHistory(context: context).isSeeded }
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

                // Glow leads: it is the one control here that is the product
                // rather than a preference about it.
                Section {
                    Slider(
                        value: $peak,
                        in: GlowSettings.range,
                        step: 0.5
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
                    Text("What the screen grants changes with ambient light, brightness and heat.")
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

                if peak <= GlowSettings.range.lowerBound {
                    Section {
                        Label("Glow off. Today's slot still shows, unlit.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
                        .tint(GlowPalette.grey)
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

                // Data last, and History belongs in it: the long view of what
                // is stored, beside the one control that writes something
                // invented into the same store. When export arrives it lands
                // here too, which is the quiet argument for the section.
                Section {
                    NavigationLink {
                        YearView()
                    } label: {
                        Label("History", systemImage: "square.grid.3x3")
                    }

                    Button {
                        isChoosingFormat = true
                    } label: {
                        Label("Export History", systemImage: "square.and.arrow.up")
                    }
                    .disabled(habits.isEmpty)

                    Toggle("Demo history", isOn: demoBinding)
                        .tint(GlowPalette.grey)
                } header: {
                    Text("Data")
                } footer: {
                    Text(exportFooter)
                    Text(demoFooter)
                }
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
    /// shipping default. Reserving anything less cuts the light mid-falloff,
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
    /// A binding rather than `@AppStorage`, because the default is **goals**
    /// and `@AppStorage` hands back `0` for a key nobody has written — a plain
    /// stored default reads as whatever `0` maps to until it is changed twice.
    /// `PopPreferences` keeps the sentinel; this reflects it.
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

    enum ExportFormat { case csv, json }

    /// Writes the file, then hands it to the share sheet.
    ///
    /// Written at the moment of the tap rather than kept ready: a history file
    /// sitting on disk that nobody asked for is exactly the thing this feature
    /// promises not to make. It goes to the app's own temporary directory,
    /// which the system reclaims.
    private func export(as format: ExportFormat) {
        let now = Date()
        let snapshots = habits.map { $0.snapshot() }
        do {
            let text: String
            let name: String
            switch format {
            case .csv:
                text = HistoryExport.csv(habits: snapshots)
                name = HistoryExport.filename(on: now, extension: "csv")
            case .json:
                text = try HistoryExport.json(habits: snapshots, exportedAt: now)
                name = HistoryExport.filename(on: now, extension: "json")
            }
            // Written through `ExportStore` rather than straight into the
            // temporary directory: the file has a lifetime now, and something
            // has to own it. See #142.
            let url = try exportStore.write(text, named: name)
            pendingExport = url
            exportFile = HistoryFile(url: url)
        } catch {
            HabitStore.report(error, operation: "exportHistory")
        }
    }

    /// Takes the shared file away once the sheet has gone.
    private func discardExport() {
        guard let url = pendingExport else { return }
        exportStore.discard(url)
        pendingExport = nil
    }

    private var exportFooter: String {
        "Every habit and every day you logged it, as a file. It leaves this "
            + "phone only when you send it somewhere — nothing is uploaded."
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
                        try demo.seed()
                    } else {
                        try demo.remove()
                    }
                } catch {
                    HabitStore.report(error, operation: wantsDemo ? "seedDemo" : "removeDemo")
                }
                isDemoSeeded = demo.isSeeded
                // Demo history writes through `DemoHistory` rather than
                // `HabitStore`, so it says so itself. See `WidgetRefresh`.
                WidgetRefresh.invalidate()
            }
        )
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

    /// Names the control it explains, because the section holds two rows and
    /// only one of them invents anything.
    private var demoFooter: String {
        "Demo history fills the past ten weeks with an invented past, so the "
            + "app can be seen with something in it. Today is never touched, "
            + "and switching it off removes exactly what it added — nothing "
            + "you logged yourself."
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
