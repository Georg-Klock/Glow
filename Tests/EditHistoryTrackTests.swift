import CoreGraphics
import Testing

@testable import Glow

/// Correct History's circles keep their phone size and grow with the grid at
/// regular width (#664).
struct EditHistoryTrackTests {
    @Test("Every phone draws the circle exactly as before")
    func phonesAreUnchanged() {
        for width in [300, 335, 350, 353, 400] as [CGFloat] {
            let g = RowGeometry(totalWidth: width)
            #expect(EditHistoryTrack.circleDiameter(for: g) == min(18, g.slotHeight))
            #expect(EditHistoryTrack.strokeWidth(for: g) == 1.5)
        }
    }

    @Test("At regular width the circle keeps its share of the slot")
    func regularWidthGrowsWithTheGrid() {
        let phone = RowGeometry(totalWidth: WidgetMetrics.largeWidth)
        let pad = RowGeometry(totalWidth: 780, maximumPanelWidth: PanelCeiling.regularWidth)
        #expect(pad.scale > 1.9)
        let phoneShare = EditHistoryTrack.circleDiameter(for: phone) / phone.slotHeight
        let padShare = EditHistoryTrack.circleDiameter(for: pad) / pad.slotHeight
        #expect(abs(phoneShare - padShare) < 1e-9)
        #expect(EditHistoryTrack.circleDiameter(for: pad) <= pad.slotHeight)
        #expect(abs(EditHistoryTrack.strokeWidth(for: pad) - 1.5 * pad.scale) < 1e-9)
    }
}
