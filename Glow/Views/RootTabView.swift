import SwiftUI

/// The app's tabs: This Week and Settings.
///
/// A system `TabView`, so the bar is the platform's — its height, its blur, its
/// behaviour when a keyboard appears, its accessibility.
///
/// The tabs were four, ordered as a zoom — year, week, today — and opening in
/// the middle. That argument stopped holding once Today became the per-day
/// screen with its own habits rather than a filtered view of the week: the
/// tabs were no longer three depths of one thing. The year moved into Settings
/// as History, where the things that are neither today nor this week live.
///
/// **Today's slot holds the Widgets tab** (#210). The per-day screen came out
/// with the kind it drew (#209) and the slot was left empty rather than
/// collapsed, so the bar reflowed once rather than twice: middle position,
/// same neighbours, new content. This Week is still where every launch lands,
/// which is what a cold launch already did.
struct RootTabView: View {
    /// The landing screen. Deep links overwrite it before anything shows.
    @State private var selection: Screen = .week

    /// Not named `Tab`: SwiftUI has its own, and shadowing it makes the builder
    /// below construct this instead, which does not compile and does not say why.
    enum Screen: Hashable {
        case week, widgets, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("This Week", systemImage: "calendar", value: Screen.week) {
                WeeklyGridView()
            }
            // `square.grid.2x2` is the Home Screen's own arrangement — a
            // drawing of where these things go, in the same spirit as the
            // calendar and the cog beside it.
            Tab("Widgets", systemImage: "square.grid.2x2", value: Screen.widgets) {
                WidgetsView()
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
            case .week: selection = .week
            case nil: break
            }
        }
    }
}
