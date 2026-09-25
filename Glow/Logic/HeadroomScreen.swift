/// Which screen answers "how much EDR headroom is there" (#642).
///
/// Headroom is a property of a display, and the app is shown on exactly one:
/// the screen of the window scene it is drawing into. `UIScreen.main` answered
/// a different question — the built-in screen, whatever the app is on — which
/// on iPadOS with Stage Manager and an external display is the wrong one, and
/// it is deprecated there.
///
/// The readers that need the value are not all views with a window in reach
/// (`LowPowerMonitor` is an object; `EDRHeadroomSnapshot` is sampled from a
/// task), so they ask the application's connected scenes instead, and this is
/// the rule that picks one. Generic over the screen, so the rule is testable
/// without a `UIScreen`, and free of UIKit because `Glow/Logic` is.
///
/// On iPhone there is one scene, so every rule here picks it; the ranking only
/// matters where there can be more than one.
enum HeadroomScreen {
    /// `UIScene.ActivationState`, restated so this file does not import UIKit.
    /// Declared in preference order: the scene the person is using, then one
    /// on screen but not taking input — which is what a scene still launching
    /// reports — then the rest.
    enum Activation: Int, Comparable, Sendable {
        case foregroundActive
        case foregroundInactive
        case background
        case unattached

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Candidate<Screen> {
        let activation: Activation
        /// Whether the scene holds the key window: the tie-breaker between two
        /// scenes in the same state, since the key window is the one in use.
        let hasKeyWindow: Bool
        let screen: Screen
    }

    /// The screen of the most-foreground scene, the key window's breaking a
    /// tie; the first candidate among exact equals. `nil` only when there is
    /// no scene at all, which a caller answers with its own fallback.
    static func pick<Screen>(from candidates: [Candidate<Screen>]) -> Screen? {
        var best: Candidate<Screen>?
        for candidate in candidates {
            guard let current = best else { best = candidate; continue }
            if rank(candidate) < rank(current) { best = candidate }
        }
        return best?.screen
    }

    private static func rank<Screen>(_ candidate: Candidate<Screen>) -> (Int, Int) {
        (candidate.activation.rawValue, candidate.hasKeyWindow ? 0 : 1)
    }
}
