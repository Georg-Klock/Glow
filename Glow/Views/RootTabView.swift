import SwiftUI

/// The app's four tabs.
///
/// A system `TabView`, so the bar is the platform's — its height, its blur, its
/// behaviour when a keyboard appears, its accessibility. Three ways of looking
/// at the same completions, widest to narrowest, and then settings.
///
/// The order is deliberate. Left to right is a zoom: the year, the week, today.
/// The screen that opens is the middle one, because the week is the app — the
/// year is context and today is a shortcut.
struct RootTabView: View {
    @State private var selection: Screen = .week

    /// Not named `Tab`: SwiftUI has its own, and shadowing it makes the builder
    /// below construct this instead, which does not compile and does not say why.
    enum Screen: Hashable {
        case year, week, today, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("This Year", systemImage: "square.grid.3x3", value: Screen.year) {
                YearView()
            }
            Tab("This Week", systemImage: "calendar", value: Screen.week) {
                WeeklyGridView()
            }
            Tab("Today", systemImage: "circle.dotted", value: Screen.today) {
                TodayView()
            }
            Tab("Settings", systemImage: "gearshape", value: Screen.settings) {
                SettingsView()
            }
        }
        .tint(GlowPalette.color)
    }
}
