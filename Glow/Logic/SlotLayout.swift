import CoreGraphics

/// The row geometry, as one formula rather than two.
///
/// A daily row is 7 circles and an N-times row is N pills, but both divide the
/// same track width by the same rule, so a pill row and a circle row always
/// start and end on the same pixels.
enum SlotLayout {
    /// The gap between slots, as a fraction of one daily slot.
    ///
    /// Derived rather than fixed, so a fixed gap in points cannot lose the
    /// proportion the moment the track width changes between the phone and a
    /// large widget. That much is unchanged.
    ///
    /// **The proportion itself is not** (#331). It was 24 on 35 — the old
    /// file's seven 35pt slots on a 59pt pitch — and the reasoning attached to
    /// it was that the grid is mostly air by design, so the marks read as a
    /// constellation rather than a progress bar.
    ///
    /// **The air did not go; the marks grew into it** (#332). This ratio alone
    /// makes the grid *sparser*, not denser — the pitch goes from 29.4 to 32,
    /// so a 3pt dot in a 24pt slot sits further from its neighbour than it did
    /// in a 17.455pt one. Looked at on a render, and it is the opposite of what
    /// the numbers suggest at a glance. What changes the reading is the mark
    /// filling its slot: a 22pt disc where a 3pt dot was.
    ///
    /// So the constellation argument is the one that gave way, and it gave way
    /// to #332 rather than to this number. Recorded rather than silently
    /// replaced, because it was a real argument and someone will wonder where
    /// it went.
    ///
    /// 8 / 24 = 1/3, from `docs/week-marks.md` §8.2: seven 24pt slots on a 32pt
    /// pitch, which is 216 of track.
    static let gapRatio: CGFloat = 8.0 / 24.0

    /// The month grid's own ratio, which is **not** the week's.
    ///
    /// A week row and a month cell are different grids that happen to share a
    /// column count, and the design file gives them different rhythms: the week
    /// is seven 24pt slots on a 32pt pitch (8 on 24), the month is seven 16pt
    /// cells on a 19pt pitch (3 on 16). Node `234:11216`, `Frame 14` at
    /// 130 × 111 — `7 * 16 + 6 * 3 = 130`, exactly.
    ///
    /// It reads much tighter than the week's, and that is the point: a month is
    /// thirty-odd marks in a small widget's frame, so the air between them has
    /// to give before the marks do. Deriving it from `gapRatio` spread the
    /// cells 70% further apart than the file and shrank them by 4%.
    static let monthGapRatio: CGFloat = 3.0 / 16.0

    /// The gap for a given track, shared by every row so the columns line up.
    static func gap(trackWidth: CGFloat) -> CGFloat {
        gapRatio * dailySlot(trackWidth: trackWidth)
    }

    /// One month cell: seven of them and six gaps fill the track exactly, by
    /// the same algebra as `dailySlot` at the month's own ratio.
    static func monthCell(trackWidth: CGFloat) -> CGFloat {
        max(0, trackWidth / (7 + 6 * monthGapRatio))
    }

    /// The gap between month cells.
    static func monthGap(trackWidth: CGFloat) -> CGFloat {
        monthGapRatio * monthCell(trackWidth: trackWidth)
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

    /// The track a given daily slot fills exactly — `dailySlot` run backwards.
    ///
    /// **The widget asks this when the height overrules the width** (#410). A
    /// slot is as tall as a daily mark is wide, so a row block's height is the
    /// frame's *width* by another name, and on a frame proportionally wider
    /// than the design's the block outgrows the height it has to fit in. The
    /// large family's fix is to take the smaller slot — and a smaller slot has
    /// to bring its own column rhythm with it, or the marks would keep the
    /// track's pitch and stop being round.
    ///
    /// So the widget re-derives one narrower track from the slot it settled on
    /// and hands *that* to everything downstream: the gap, the column centres,
    /// the spans and the rest day's line all divide the same number, and the
    /// difference between it and the frame's own track lands at the trailing
    /// edge. Written here beside its inverse so the two cannot drift.
    static func trackWidth(dailySlot slot: CGFloat) -> CGFloat {
        max(0, slot * (7 + 6 * gapRatio))
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

    /// How far the **last** column of a span sits from that span's own centre.
    ///
    /// A dead mark is a claim about one day — its anchor — and a mark ends on
    /// its anchor, so the ✕ belongs on the span's last column rather than in
    /// the middle of the run of days it swallowed (`docs/week-marks.md` §4,
    /// #389). A cross is drawn centred in whatever frame it is given, so this
    /// is what it has to move.
    ///
    /// Half the distance from the first column's centre to the last's, which
    /// falls out of `columnCentre`: the span's centre is the midpoint of those
    /// two, so half the span between them reaches either end of it. Zero for a
    /// one-column mark, where the two are the same column.
    static func anchorOffset(trackWidth: CGFloat, dayCount: Int) -> CGFloat {
        guard dayCount > 1 else { return 0 }
        let pitch = dailySlot(trackWidth: trackWidth) + gap(trackWidth: trackWidth)
        return CGFloat(dayCount - 1) / 2 * pitch
    }

    /// Width of a shape covering `dayCount` whole columns and the gaps between
    /// them — the unit a habit due a number of times a week is drawn in.
    static func spanWidth(trackWidth: CGFloat, dayCount: Int) -> CGFloat {
        guard dayCount > 0 else { return 0 }
        let slot = dailySlot(trackWidth: trackWidth)
        return CGFloat(dayCount) * slot + CGFloat(dayCount - 1) * gap(trackWidth: trackWidth)
    }
}
