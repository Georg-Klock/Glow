import CoreGraphics

/// The row geometry, as one formula rather than two.
///
/// A daily row is 7 circles and an N-times row is N pills, but both divide the
/// same track width by the same rule, so a pill row and a circle row always
/// start and end on the same pixels.
enum SlotLayout {
    /// The gap between slots, shared by every row so the columns line up.
    static let gap: CGFloat = 6

    /// Width of one slot when `slotCount` of them share `trackWidth`.
    ///
    ///     dailyCircleWidth = (W - 6 * G) / 7
    ///     pillWidth(N)     = (W - (N - 1) * G) / N
    static func slotWidth(
        trackWidth: CGFloat,
        slotCount: Int,
        gap: CGFloat = SlotLayout.gap
    ) -> CGFloat {
        guard slotCount > 0 else { return 0 }
        let available = trackWidth - CGFloat(slotCount - 1) * gap
        return max(0, available / CGFloat(slotCount))
    }

    /// Every slot is as tall as a daily circle is wide, which is what makes a
    /// daily circle round and a pill exactly as tall as it.
    static func slotHeight(trackWidth: CGFloat, gap: CGFloat = SlotLayout.gap) -> CGFloat {
        slotWidth(trackWidth: trackWidth, slotCount: 7, gap: gap)
    }

    static func slotSize(
        trackWidth: CGFloat,
        slotCount: Int,
        gap: CGFloat = SlotLayout.gap
    ) -> CGSize {
        CGSize(
            width: slotWidth(trackWidth: trackWidth, slotCount: slotCount, gap: gap),
            height: slotHeight(trackWidth: trackWidth, gap: gap)
        )
    }
}
