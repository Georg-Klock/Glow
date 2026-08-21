import CoreGraphics

/// The slice of a span that the rest day takes out of it.
///
/// A habit due a number of times a week is drawn as shapes stretching across
/// the week, and those shapes crossed the one column nothing can happen in — so
/// a met goal drew a single lit bar straight through the rest day. The mockup
/// stops them at the column before.
///
/// **The arithmetic does not change.** `WeekSpans` keeps its seven-column
/// division, its span count, its packing rule and its tests; the *shape* is
/// drawn with this window subtracted from it. Re-dividing six columns instead
/// would have to answer what a 2×/week habit does when the rest day splits the
/// week unevenly, and would rewrite span arithmetic that #4 is already open
/// against.
enum RestWindow {
    /// The window in the span's own coordinates — 0 at the span's leading edge
    /// — or nil when the rest day falls outside this span.
    ///
    /// It is the rest column's slot **plus the gap on each side**, so its edges
    /// land exactly on the neighbouring columns' slot edges. Without the gaps a
    /// met-goal bar with Sunday as the rest day would end a gap's width short
    /// of Saturday's column and leave a stub hanging in the air.
    ///
    /// The range may run past either end of the span; whatever draws it clamps.
    /// That is deliberate — at the ends of a span the window is not a hole but
    /// a shortening, and clamping is how the same number expresses both.
    static func inSpan(
        firstDay: Int,
        lastDay: Int,
        restIndex: Int?,
        trackWidth: CGFloat
    ) -> ClosedRange<CGFloat>? {
        guard let restIndex, restIndex >= firstDay, restIndex <= lastDay else { return nil }
        let slot = SlotLayout.dailySlot(trackWidth: trackWidth)
        let gap = SlotLayout.gap(trackWidth: trackWidth)
        // A span covering columns `firstDay...lastDay` starts at
        // `firstDay * (slot + gap)` in the track, because the spans sit in a
        // stack whose spacing is exactly `gap`. So the column's offset inside
        // the span is the difference of the two indices.
        let offset = CGFloat(restIndex - firstDay) * (slot + gap)
        return (offset - gap)...(offset + slot + gap)
    }
}
