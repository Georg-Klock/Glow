import Foundation

/// Which rows a week widget draws.
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
/// every other one. The view supplies only the family's spacer policy; this
/// returns the whole eligible order and the view cuts it (#496).
enum WidgetRows {
    /// Whether an automatic, unconfigured layout includes the app's spacer
    /// rows. A configured selection always honours a spacer that was chosen.
    enum AutomaticSpacers {
        case include
        case exclude
    }

    /// The rows to draw, given the app's own order and a widget's own choice.
    ///
    /// `chosen` is the configured selection — `SelectWeekLayoutIntent.rows`
    /// mapped to ids. Nil or empty is a widget nobody has configured. Its
    /// family supplies `automaticSpacers`: large keeps the whole app list,
    /// while medium skips blank rows before the view applies its measured cut
    /// (#496).
    ///
    /// **The order is the app's, and the choice is only which** — which is a
    /// decision rather than a limitation, because the array does arrive
    /// ordered.
    ///
    /// #188 asked for "which habits and in what order", and #191 established on
    /// an iPhone 14 Pro that WidgetKit hands an array-of-entity parameter to
    /// the provider **in the order the rows were tapped**: selecting the last
    /// row first put the app's own first habit second in the resolved array.
    /// So the ordering half was available and is deliberately not used.
    ///
    /// The reason is that the control cannot express it. The system's picker
    /// draws **checkmarks, not positions** — no handles, no numbers, no edit
    /// mode, on hardware as in the simulator. So an order carried out of it is
    /// a side effect of the sequence somebody happened to tap in: invisible
    /// while choosing, unexplained afterwards, and unfixable without clearing
    /// every row and re-tapping in the right sequence. A widget that quietly
    /// reorders itself by gesture history is worse than one that matches the
    /// app, and #172's actual complaint — a blank row landing on the medium
    /// widget's cut — is answered by *which* rows alone.
    ///
    /// If a real ordering surface is ever wanted, it is the in-app screen #188
    /// names as its fallback, where the order would be visible while being
    /// chosen. This function takes `[UUID]?` and does not care which surface
    /// supplies it.
    ///
    /// Two other things the configured path does, both about a choice
    /// outliving the store it was made against:
    ///
    /// * **An id that no longer exists is dropped**, not held as a gap. A
    ///   deleted habit is not a blank row — the person who wants a gap has a
    ///   real one to pick.
    /// * **A repeated id appears once.** The view's `ForEach` is keyed by
    ///   `id`, so a duplicate would be a duplicate SwiftUI identity in a list
    ///   that also carries the rest-day cut's row indices. Ordering by the
    ///   app's list makes this structural rather than guarded — `all` holds
    ///   each row once — but the filter is written as a set membership test
    ///   rather than relying on that.
    ///
    /// A configured spacer needs no special case: it is a `Habit` with
    /// `isSpacer` and its own stable `id`, so a selection honours it exactly
    /// like a habit. The policy applies only to the automatic nil/empty path.
    static func rows(
        from all: [HabitSnapshot],
        chosen: [UUID]?,
        automaticSpacers: AutomaticSpacers
    ) -> [HabitSnapshot] {
        guard let chosen, !chosen.isEmpty else {
            switch automaticSpacers {
            case .include: return all
            case .exclude: return all.filter { !$0.isSpacer }
            }
        }
        // Walking `all` rather than `chosen` is the whole of it: the result is
        // in the app's order by construction, and an id the store no longer
        // holds cannot appear because it was never walked.
        let wanted = Set(chosen)
        return all.filter { wanted.contains($0.id) }
    }
}
