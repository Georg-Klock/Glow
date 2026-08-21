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
    let habits: [HabitSnapshot]
    /// The habit whose completion is mid-animation, if any.
    var burstHabit: UUID?
    /// How far through the completion cross-fade this frame is, 0 through 1:
    /// the dot's opacity, and the ring's complement.
    var progress: Double = 1
}
