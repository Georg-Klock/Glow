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

    /// Width of a shape covering `dayCount` whole columns and the gaps between
    /// them — the unit a habit due a number of times a week is drawn in.
    static func spanWidth(trackWidth: CGFloat, dayCount: Int) -> CGFloat {
        guard dayCount > 0 else { return 0 }
        let slot = dailySlot(trackWidth: trackWidth)
        return CGFloat(dayCount) * slot + CGFloat(dayCount - 1) * gap(trackWidth: trackWidth)
    }
}
