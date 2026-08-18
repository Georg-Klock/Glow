import CoreGraphics
import Testing
@testable import Glow

@Suite("Row geometry")
struct SlotLayoutTests {
    private let trackWidth: CGFloat = 220
    private let gap: CGFloat = 6

    @Test("Daily circles divide the track by seven")
    func dailyWidth() {
        let width = SlotLayout.slotWidth(trackWidth: trackWidth, slotCount: 7, gap: gap)
        #expect(abs(width - (trackWidth - 6 * gap) / 7) < 0.0001)
    }

    @Test("N pills divide the same track by N", arguments: 2...6)
    func pillWidth(count: Int) {
        let width = SlotLayout.slotWidth(trackWidth: trackWidth, slotCount: count, gap: gap)
        let expected = (trackWidth - CGFloat(count - 1) * gap) / CGFloat(count)
        #expect(abs(width - expected) < 0.0001)
    }

    @Test("Every row spans exactly the same track", arguments: [2, 3, 4, 5, 6, 7])
    func rowsShareTheSameSpan(count: Int) {
        // This is what makes a pill row start and end on the same pixels as the
        // circle row above it. If it drifts, the grid stops reading as a grid.
        let width = SlotLayout.slotWidth(trackWidth: trackWidth, slotCount: count, gap: gap)
        let span = CGFloat(count) * width + CGFloat(count - 1) * gap
        #expect(abs(span - trackWidth) < 0.0001)
    }

    @Test("Pills are exactly as tall as a daily circle")
    func pillsMatchCircleHeight() {
        let circle = SlotLayout.slotWidth(trackWidth: trackWidth, slotCount: 7, gap: gap)
        for count in 2...6 {
            let size = SlotLayout.slotSize(trackWidth: trackWidth, slotCount: count, gap: gap)
            #expect(abs(size.height - circle) < 0.0001)
        }
    }

    @Test("A daily slot is square, so it renders as a circle")
    func dailySlotIsSquare() {
        let size = SlotLayout.slotSize(trackWidth: trackWidth, slotCount: 7, gap: gap)
        #expect(abs(size.width - size.height) < 0.0001)
    }

    @Test("Degenerate widths clamp instead of going negative")
    func degenerateWidths() {
        #expect(SlotLayout.slotWidth(trackWidth: 0, slotCount: 7, gap: gap) == 0)
        #expect(SlotLayout.slotWidth(trackWidth: 10, slotCount: 7, gap: gap) == 0)
        #expect(SlotLayout.slotWidth(trackWidth: 100, slotCount: 0, gap: gap) == 0)
    }
}

@Suite("Frequency normalization")
struct FrequencyTests {
    @Test("Seven times a week is daily")
    func sevenIsDaily() {
        #expect(Frequency(timesPerWeek: 7) == .daily)
        #expect(Frequency(timesPerWeek: 9) == .daily)
    }

    @Test("Counts below the selectable range clamp up")
    func lowCountsClamp() {
        #expect(Frequency(timesPerWeek: 1) == .timesPerWeek(2))
        #expect(Frequency(timesPerWeek: 0) == .timesPerWeek(2))
        #expect(Frequency(timesPerWeek: -3) == .timesPerWeek(2))
    }

    @Test("Slot count matches the cadence")
    func slotCounts() {
        #expect(Frequency.daily.slotCount == 7)
        for count in 2...6 {
            #expect(Frequency(timesPerWeek: count).slotCount == count)
        }
    }
}
