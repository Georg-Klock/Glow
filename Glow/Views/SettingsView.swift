import SwiftUI

/// Settings: how hard the glow pushes, and what shape a week is.
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

                    LabeledContent("Brightness", value: label)
                } header: {
                    Text("Glow")
                } footer: {
                    Text(footer)
                }

                if peak <= GlowSettings.range.lowerBound {
                    Section {
                        Label("The glow is off. Today's slot still shows, just without any light.", systemImage: "info.circle")
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
                    Text("Which day the grid starts on. It also decides which seven days a weekly goal is counted over, so changing it can move a habit's progress between weeks.")
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
                    Text("A rest day is never counted as missed and never asks for anything. Logging a habit on one still counts — it is permission, not a rule.")
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
        peak <= GlowSettings.range.lowerBound
            ? "Off"
            : String(format: "%.1f× brighter than white", peak)
    }

    private var footer: String {
        """
        Today's unfinished slot is drawn as an HDR image, so it can be brighter \
        than the white the screen normally allows. This sets how far above that \
        it aims for.

        How bright it actually gets is not up to the app: it depends on ambient \
        light, display brightness, thermal state, and whether Low Power Mode is \
        on. Expect it to be dramatic outdoors and subtle in a dim room. On a \
        screen without extended dynamic range, and in the widget, the slot \
        falls back to flat colour with a soft halo.
        """
    }
}
