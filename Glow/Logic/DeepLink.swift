import Foundation

/// The widget chooses the screen.
///
/// A widget's surface divides in two, and the division is deliberate. The marks
/// act in place — a week slot toggles, through its intent, opening nothing.
/// Everything else carries one of these URLs and opens the app on that widget's
/// screen.
///
/// **`glow://today` was the other one and is gone** (#209). It opened the
/// per-day screen, which the two Today widget families carried you to and which
/// no longer exists. It is deliberately not mapped to This Week instead: an
/// unrecognised link changes nothing, and silently landing somebody on a screen
/// they did not ask for is worse than doing nothing when nothing can be done.
enum DeepLink {
    /// Where a URL lands. A separate type rather than the tab view's own
    /// `Screen`, so the mapping stays in Logic and testable without a view.
    ///
    /// One case, and still an enum with an optional in front of it: the
    /// distinction that matters is "a screen was asked for" against "this URL
    /// means nothing here", and that survives having one screen to ask for.
    enum Destination: Equatable, Sendable {
        case week
    }

    static let scheme = "glow"

    /// The URL each widget carries on its non-acting surface.
    static let week = URL(string: "glow://week")!

    /// The screen a URL asks for, or nil for anything unrecognised — an
    /// unknown link changes nothing rather than guessing a tab.
    static func destination(for url: URL) -> Destination? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        switch url.host?.lowercased() {
        case "week": return .week
        default: return nil
        }
    }
}
