import Foundation

/// Which rows a week widget draws, and in what order.
///
/// The week widget mirrored the app's own order and had no way not to. #172
/// found the cost: the app's clustering puts a blank row where a medium
/// widget's cut falls, so medium shows four habits instead of five, and the
/// only way to ask for a different five was to reorder the whole app. The
/// decision there was to leave the clustering alone and let a *widget* deviate
/// instead (#188). This is the function that deviates.
///
/// Here rather than in the provider because it is a decision — which rows, in
/// what order — and decisions in this project are pure and tested (`WeekGrid`,
/// `WeekSpans`, `RestCut`). The provider reads the store, this decides, the
/// view measures.
///
/// **No capacity argument, deliberately.** How many rows fit is a question
/// about a rendered frame, and only the view has one: `WeekWidgetView` measures
/// its own `proxy.size` and applies `WidgetMetrics.rowCapacity` to it. A
/// capacity computed here would have to guess the family's point size, which
/// differs by phone — right on the 6.1" the design is authored for and wrong on
/// every other one. So this returns the whole chosen order and the view cuts
/// it, which is the same hard cut an unconfigured widget has always made.
enum WidgetRows {
    /// The rows to draw, given the app's own order and a widget's own choice.
    ///
    /// `chosen` is the configured order — `SelectWeekLayoutIntent.rows` mapped
    /// to ids. Nil or empty is a widget nobody has configured, and it keeps the
    /// app's order exactly: that is the requirement, because every widget
    /// already on a home screen arrives here with nil the first time this ships
    /// and must not move under anyone.
    ///
    /// Three things the configured path does, all of them about a choice
    /// outliving the store it was made against:
    ///
    /// * **An id that no longer exists is dropped**, not held as a gap. A
    ///   deleted habit is not a blank row — the person who wants a gap has a
    ///   real one to pick.
    /// * **A repeated id appears once.** The view's `ForEach` is keyed by
    ///   `id`, so a duplicate would be a duplicate SwiftUI identity in a list
    ///   that also carries the rest-day cut's row indices. Whether the system's
    ///   picker can even produce one is unconfirmed; this makes it not matter.
    /// * **Order is the configuration's, not the store's.** The app's list is
    ///   only consulted for what a row *is*.
    ///
    /// Spacers need no special case at either end. A blank row is a `Habit`
    /// with `isSpacer` and its own stable `id`, so it is chosen, ordered and
    /// dropped by exactly the same rules as a habit.
    static func rows(from all: [HabitSnapshot], chosen: [UUID]?) -> [HabitSnapshot] {
        guard let chosen, !chosen.isEmpty else { return all }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        return chosen.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        }
    }
}
