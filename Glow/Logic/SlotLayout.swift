import CoreGraphics

/// The row geometry, as one formula rather than two.
///
/// A daily row is 7 circles and an N-times row is N pills, but both divide the
/// same track width by the same rule, so a pill row and a circle row always
/// start and end on the same pixels.
enum SlotLayout {
    /// The gap between slots, as a fraction of one daily slot.
    ///
    /// Derived rather than fixed, because the grid is mostly air by design: at
    /// this ratio the marks read as a constellation rather than a progress bar,
    /// and a fixed gap in points loses that the moment the track width changes
    /// between the phone and a large widget.
    ///
    /// The design file lays a large widget out as seven 35pt slots on a 59pt
    /// pitch, so the gap is 24 on 35. Taken from the frame's own numbers rather
    /// than measured off a render, which is where an earlier 0.735 came from.
    static let gapRatio: CGFloat = 24.0 / 35.0

    /// The gap for a given track, shared by every row so the columns line up.
    static func gap(trackWidth: CGFloat) -> CGFloat {
        gapRatio * dailySlot(trackWidth: trackWidth)
    }

    /// One daily slot: seven of them and six gaps fill the track exactly.
    ///
    ///     7s + 6 * (ratio * s) = W
    static func dailySlot(trackWidth: CGFloat) -> CGFloat {
        max(0, trackWidth / (7 + 6 * gapRatio))
    }

    /// Width of one slot when `slotCount` of them share `trackWidth`.
    ///
    ///     dailyCircleWidth = (W - 6 * G) / 7
    ///     pillWidth(N)     = (W - (N - 1) * G) / N
    static func slotWidth(trackWidth: CGFloat, slotCount: Int) -> CGFloat {
        guard slotCount > 0 else { return 0 }
        let available = trackWidth - CGFloat(slotCount - 1) * gap(trackWidth: trackWidth)
        return max(0, available / CGFloat(slotCount))
    }

    /// Every slot is as tall as a daily one is wide, which is what makes a daily
    /// slot round and everything else exactly as tall as it.
    static func slotHeight(trackWidth: CGFloat) -> CGFloat {
        dailySlot(trackWidth: trackWidth)
    }

    static func slotSize(trackWidth: CGFloat, slotCount: Int) -> CGSize {
        CGSize(
            width: slotWidth(trackWidth: trackWidth, slotCount: slotCount),
            height: slotHeight(trackWidth: trackWidth)
        )
    }

    /// The centre of one weekday's column, measured from the track's leading
    /// edge.
    ///
    /// Every mark that has to sit *on a weekday* asks this: the rest day's cut,
    /// and the dots a weekly row now puts on the days it was logged. One
    /// formula, so a dot and the line behind it cannot land a point apart.
    static func columnCentre(trackWidth: CGFloat, index: Int) -> CGFloat {
        let slot = dailySlot(trackWidth: trackWidth)
        return CGFloat(index) * (slot + gap(trackWidth: trackWidth)) + slot / 2
    }

    /// The leading edge of one weekday's column, from the track's leading edge.
    ///
    /// Also where a span starting at that column begins, because the spans sit
    /// in a stack whose spacing is exactly the gap.
    static func columnStart(trackWidth: CGFloat, index: Int) -> CGFloat {
        CGFloat(index) * (dailySlot(trackWidth: trackWidth) + gap(trackWidth: trackWidth))
    }

    /// The weekday column a touch at `x` lands on, `x` measured from the
    /// track's leading edge.
    ///
    /// **The inverse of `columnCentre`, and the reason it exists**: a habit due
    /// a number of times a week is drawn as spans, and a span covers several
    /// columns while carrying one nominal day. Tapping one has to write the
    /// weekday actually touched, so the view needs to run the row geometry
    /// backwards — and that arithmetic belongs beside the forward direction,
    /// where it is tested, rather than inside `SpanView` (#116).
    ///
    /// Nearest centre rather than containment, because the gaps are two thirds
    /// of a slot wide and a finger that lands in one meant the column it is
    /// closest to. Clamped to the week: a touch that slides off either end of
    /// the track belongs to the column it left. Nil only for a track that
    /// cannot be divided at all, or a non-finite `x` — both of which arrive
    /// through layout often enough not to be theoretical.
    static func column(atX x: CGFloat, trackWidth: CGFloat) -> Int? {
        let slot = dailySlot(trackWidth: trackWidth)
        let pitch = slot + gap(trackWidth: trackWidth)
        guard pitch > 0, x.isFinite else { return nil }
        // Clamped as a `CGFloat` and converted afterwards: `Int(_:)` traps on a
        // value past `Int.max`, and a very large `x` is a layout artifact
        // rather than something worth crashing over.
        let raw = ((x - slot / 2) / pitch).rounded()
        return Int(min(6, max(0, raw)))
    }

    /// Width of a shape covering `dayCount` whole columns and the gaps between
    /// them — the unit a habit due a number of times a week is drawn in.
    static func spanWidth(trackWidth: CGFloat, dayCount: Int) -> CGFloat {
        guard dayCount > 0 else { return 0 }
        let slot = dailySlot(trackWidth: trackWidth)
        return CGFloat(dayCount) * slot + CGFloat(dayCount - 1) * gap(trackWidth: trackWidth)
    }
}
