import SwiftUI

/// The app's three tabs: Today, This Week, Settings.
///
/// A system `TabView`, so the bar is the platform's — its height, its blur, its
/// behaviour when a keyboard appears, its accessibility.
///
/// The tabs were four, ordered as a zoom — year, week, today — and opening in
/// the middle. That argument stopped holding once Today became the per-day
/// screen with its own habits rather than a filtered view of the week: the
/// tabs are no longer three depths of one thing. The year moved into Settings
/// as History, where the things that are neither today nor this week live.
///
/// There is no fixed landing tab. A widget opens its own screen — the daily
/// rings land on Today, the week grid lands on This Week — so you arrive at
/// the bigger version of what you were just looking at. Only a cold launch
/// has no widget to ask, and it opens This Week: the denser screen, with
/// Today one tap away.
struct RootTabView: View {
    /// The cold-launch screen. Deep links overwrite it before anything shows.
    @State private var selection: Screen = .week

    /// Not named `Tab`: SwiftUI has its own, and shadowing it makes the builder
    /// below construct this instead, which does not compile and does not say why.
    enum Screen: Hashable {
        case today, week, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "circle.dotted", value: Screen.today) {
                TodayView()
            }
            Tab("This Week", systemImage: "calendar", value: Screen.week) {
                WeeklyGridView()
            }
            // `gear` rather than `gearshape`: the cog with teeth and a hole,
            // not the rounded outline. Every other tab icon here is a drawing
            // of a thing rather than a stylised glyph.
            Tab("Settings", systemImage: "gear", value: Screen.settings) {
                SettingsView()
            }
        }
        .tint(GlowPalette.color)
        .onOpenURL { url in
            switch DeepLink.destination(for: url) {
            case .today: selection = .today
            case .week: selection = .week
            case nil: break
            }
        }
    }
}
