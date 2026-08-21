import SwiftUI
import UIKit

/// Settings: how hard the glow pushes, what shape a week is — and History,
/// the long view, which is neither today nor this week and so lives here
/// rather than spending a tab.
///
/// A tab now rather than a sheet, so there is no Done button and nothing to
/// dismiss — the changes are live and the way out is the tab bar.
struct SettingsView: View {
    @AppStorage(GlowSettings.key, store: GlowSettings.store)
    private var peak: Double = GlowSettings.defaultValue

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
                // The long view. First because it is the one row here that is
                // not configuration — it is the rest of the app's story, filed
                // where the things that are neither today nor this week live.
                Section {
                    NavigationLink {
                        YearView()
                    } label: {
                        Label("History", systemImage: "square.grid.3x3")
                    }
                }

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

                    LabeledContent("Asking for", value: label)
                    LabeledContent("Screen currently allows", value: ceiling)
                } header: {
                    Text("Glow")
                } footer: {
                    Text(footer)
                }

                if peak <= GlowSettings.range.lowerBound {
                    Section {
                        Label("Glow off. Today's slot still shows, unlit.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Week starts on", selection: $firstWeekday) {
                        ForEach(WeekPreferences.pickerOrder, id: \.self) { weekday in
                            Text(weekdayName(weekday)).tag(weekday)
                        }
                    }
                } header: {
                    Text("Week")
                } footer: {
                    Text("Also sets which seven days a weekly goal counts over.")
                }

                Section {
                    Toggle("Rest day", isOn: restDayBinding)
                    if restDay != 0 {
                        Picker("Day", selection: $restDay) {
                            ForEach(WeekPreferences.pickerOrder, id: \.self) { weekday in
                                Text(weekdayName(weekday)).tag(weekday)
                            }
                        }
                    }
                } footer: {
                    Text("Never counted as missed. Anything logged on one still counts.")
                }
            }
            .navigationTitle("Settings")
        }
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

    private var label: String {
        peak <= GlowSettings.range.lowerBound ? "Off" : String(format: "%.0f×", peak)
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

    private var footer: String {
        "How far above normal white the glow aims. What the screen grants "
            + "changes with ambient light, brightness and heat."
    }
}
