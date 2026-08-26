import SwiftUI

/// The app's tabs: Widgets, This Week and Settings.
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
/// **The Widgets tab took Today's slot** (#210) and then moved out of it
/// (#238). The per-day screen came out with the kind it drew (#209) and the
/// slot was left empty rather than collapsed, so the bar reflowed once rather
/// than twice. That was a transitional shape: Widgets inherited a position
/// chosen for a screen about today, and kept it only until the order was
/// looked at on its own terms.
///
/// It now leads, with This Week centred. `docs/vision.md` says the widget is
/// the product and the app is where you go when the widget is not enough —
/// leading with the widgets is that sentence in the tab bar. Centring This
/// Week puts the screen people actually work in under the thumb.
///
/// **This Week is still where every launch lands.** That is `selection`'s
/// default below, not a consequence of declaration order, so the two can
/// disagree on purpose: the first tab is what the app says it is about, the
/// landing tab is what it opens to.
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
            // `square.grid.2x2` is the Home Screen's own arrangement — a
            // drawing of where these things go, in the same spirit as the
            // calendar and the cog beside it.
            Tab("Widgets", systemImage: "square.grid.2x2", value: Screen.widgets) {
                WidgetsView()
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
        // A failed operation's one visible surface (#282); the editor sheet
        // carries the same modifier, because an alert attached under an active
        // sheet cannot present. See `operationNoticeAlert()`.
        .operationNoticeAlert()
        .onOpenURL { url in
            switch DeepLink.destination(for: url) {
            case .week: selection = .week
            case nil: break
            }
        }
    }
}
