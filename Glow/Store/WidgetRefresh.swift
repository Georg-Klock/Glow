import Foundation
import WidgetKit

/// Tells the widgets that something they draw has changed.
///
/// **It exists because "call `reloadAllTimelines` at the call site" kept being
/// forgotten** (#134). Swipe-delete and reorder saved without one; so did the
/// week's first day and the glow level, both of which change what a widget
/// draws. The result is a widget showing an order, a row or a set of columns
/// that no longer exists, until something unrelated happens to reload it.
///
/// So the reload moves next to the thing it is about. Every committed write in
/// `HabitStore` goes through `commit()`, which saves and then invalidates —
/// a new write path cannot forget, because forgetting now means not saving.
///
/// **Coalescing is the other half.** One gesture is often several writes: a
/// reorder rewrites `sortOrder` on every row, and a delete-then-refill is two.
/// Requests made in the same turn of the main actor become one reload, which
/// keeps the reload count proportional to *gestures* rather than to rows.
///
/// `sink` is a variable so a test can watch what was asked for without
/// WidgetKit being involved; nothing else should replace it.
@MainActor
enum WidgetRefresh {
    /// Every kind this bundle ships. `WidgetKind` is the single source, and
    /// each widget's own `kind` reads from it — a string spelled out in two
    /// places is a `reloadTimelines(ofKind:)` that silently does nothing the
    /// day one of them changes.
    static var allKinds: Set<String> { WidgetKind.allNames }

    /// What actually happens when a reload is due. Replaced in tests.
    static var sink: (Set<String>) -> Void = { kinds in
        if kinds == allKinds {
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            for kind in kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        }
    }

    private static var pending: Set<String> = []
    private static var scheduled = false

    /// Marks the given kinds — everything, by default — as needing a redraw.
    ///
    /// Returns immediately. The reload happens on the next turn of the main
    /// actor, so several calls inside one gesture cost one reload.
    static func invalidate(_ kinds: Set<String> = allKinds) {
        pending.formUnion(kinds)
        guard !scheduled else { return }
        scheduled = true
        Task { @MainActor in flush() }
    }

    /// Sends whatever is pending now, if anything is.
    ///
    /// Called on the next turn by `invalidate`, and directly by tests that would
    /// rather assert than sleep.
    static func flush() {
        scheduled = false
        guard !pending.isEmpty else { return }
        let due = pending
        pending = []
        sink(due)
    }
}
