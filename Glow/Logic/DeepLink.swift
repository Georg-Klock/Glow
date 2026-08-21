import Foundation

/// The widget chooses the screen.
///
/// There is no fixed landing tab: a daily widget opens Today, a weekly widget
/// opens This Week — you arrive at the bigger version of the thing you were
/// just looking at. Only a cold launch has no widget to ask, and that case is
/// not decided here: it is the tab view's initial selection.
///
/// A widget's surface divides in two, and the division is deliberate. The
/// marks act in place — a ring arc takes +1, a week slot toggles, through
/// their intents, opening nothing. Everything else carries one of these URLs
/// and opens the app on that widget's screen.
enum DeepLink {
    /// Where a URL lands. A separate type rather than the tab view's own
    /// `Screen`, so the mapping stays in Logic and testable without a view.
    enum Destination: Equatable, Sendable {
        case today
        case week
    }

    static let scheme = "glow"

    /// The URL each widget carries on its non-acting surface.
    static let today = URL(string: "glow://today")!
    static let week = URL(string: "glow://week")!

    /// The screen a URL asks for, or nil for anything unrecognised — an
    /// unknown link changes nothing rather than guessing a tab.
    static func destination(for url: URL) -> Destination? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        switch url.host?.lowercased() {
        case "today": return .today
        case "week": return .week
        default: return nil
        }
    }
}
