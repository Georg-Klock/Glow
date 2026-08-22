import SwiftUI
import UIKit
import WidgetKit

/// Settings, in three clusters: **Glow**, **Week**, **Data**.
///
/// Glow leads because it is the product rather than a preference about it.
/// Week holds both controls that decide what a week is — where it starts and
/// which day the app stops asking about — which were two sections, one of them
/// headerless. Data holds the long view of what is stored beside the one
/// control that writes something invented into it, and is where export lands
/// when it arrives.
///
/// A tab now rather than a sheet, so there is no Done button and nothing to
/// dismiss — the changes are live and the way out is the tab bar.
struct SettingsView: View {
    @Environment(\.modelContext) private var context

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
            Form {
                // Glow leads: it is the one control here that is the product
                // rather than a preference about it.
                Section {
                    // A live slot, rendered by the same code path the grid
                    // uses, so the slider is judged against the real thing
                    // rather than a swatch that approximates it.
                    HStack {
                        Spacer()
                        GlowImageView(size: CGSize(width: 120, height: 40))
                            .padding(.vertical, 22)
                        Spacer()
                    }
                    .listRowBackground(Color.black)
                }

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

                    Toggle("Demo history", isOn: demoBinding)
                } header: {
                    Text("Data")
                } footer: {
                    Text(demoFooter)
                }
            }
            .navigationTitle("Settings")
        }
        .onAppear { isDemoSeeded = DemoHistory(context: context).isSeeded }
        // Covers the toggle and the day picker both: the widget draws the same
        // week and withholds the same taps, and it is not told when the
        // setting moves.
        .onChange(of: restDay) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
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
                // The widgets read the same store and are not told it changed.
                WidgetCenter.shared.reloadAllTimelines()
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
