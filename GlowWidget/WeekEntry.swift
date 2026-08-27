import Foundation
import WidgetKit

/// One rendered moment of the week widget.
///
/// Its own file rather than a corner of GlowWidget.swift, because the render
/// harness (`GlowRenderTests`) compiles the widget's view sources without the
/// `@main` bundle, and the entry is the view's input — see docs/ARCHITECTURE.md.
struct WeekEntry: TimelineEntry {
    let date: Date
    let week: Week
    /// What the store said, kept as it said it (#282): a failed container or
    /// fetch arrives here as `.unavailable` and renders as such, never as the
    /// new-user empty state.
    let habits: StoreRead<[HabitSnapshot]>
    /// The habit whose completion is mid-animation, if any.
    var burstHabit: UUID?
    /// How far through the completion cross-fade this frame is, 0 through 1:
    /// the dot's opacity, and the ring's complement.
    var progress: Double = 1
    /// The small family's content (#322): one habit's month, loaded only when
    /// the provider was asked for `.systemSmall`, nil at every other family.
    /// The week halves above stay non-optional — the entry's shape does not
    /// fork by family, only which halves are filled.
    var month: StoreRead<HabitSnapshot>?
}
