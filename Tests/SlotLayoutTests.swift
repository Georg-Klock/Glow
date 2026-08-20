import CoreGraphics
import Testing
@testable import Glow

@Suite("Row geometry")
struct SlotLayoutTests {
    private let trackWidth: CGFloat = 220
    private var gap: CGFloat { SlotLayout.gap(trackWidth: trackWidth) }

    @Test("Daily slots divide the track by seven")
    func dailyWidth() {
        let width = SlotLayout.slotWidth(trackWidth: trackWidth, slotCount: 7)
        #expect(abs(width - (trackWidth - 6 * gap) / 7) < 0.0001)
    }

    @Test("N slots divide the same track by N", arguments: 2...6)
    func multiSlotWidth(count: Int) {
        let width = SlotLayout.slotWidth(trackWidth: trackWidth, slotCount: count)
        let expected = (trackWidth - CGFloat(count - 1) * gap) / CGFloat(count)
        #expect(abs(width - expected) < 0.0001)
    }

    @Test("Every row spans exactly the same track", arguments: [2, 3, 4, 5, 6, 7])
    func rowsShareTheSameSpan(count: Int) {
        // This is what makes one row start and end on the same pixels as the row
        // above it. If it drifts, the grid stops reading as a grid.
        let width = SlotLayout.slotWidth(trackWidth: trackWidth, slotCount: count)
        let span = CGFloat(count) * width + CGFloat(count - 1) * gap
        #expect(abs(span - trackWidth) < 0.0001)
    }

    @Test("The gap is a fixed share of a slot, at any track width")
    func gapScales() {
        // Fixed in points, the grid would lose its airiness the moment the track
        // changed between the phone and a large widget.
        for width in [120.0, 220.0, 400.0] as [CGFloat] {
            let slot = SlotLayout.dailySlot(trackWidth: width)
            #expect(abs(SlotLayout.gap(trackWidth: width) / slot - SlotLayout.gapRatio) < 0.0001)
        }
    }

    @Test("Every slot is exactly as tall as a daily one")
    func slotsShareHeight() {
        let daily = SlotLayout.slotWidth(trackWidth: trackWidth, slotCount: 7)
        for count in 2...6 {
            let size = SlotLayout.slotSize(trackWidth: trackWidth, slotCount: count)
            #expect(abs(size.height - daily) < 0.0001)
        }
    }

    @Test("A daily slot is square, so it renders as a circle")
    func dailySlotIsSquare() {
        let size = SlotLayout.slotSize(trackWidth: trackWidth, slotCount: 7)
        #expect(abs(size.width - size.height) < 0.0001)
    }

    @Test("A span covering the whole week is exactly the track")
    func fullWeekSpan() {
        let span = SlotLayout.spanWidth(trackWidth: trackWidth, dayCount: 7)
        #expect(abs(span - trackWidth) < 0.0001)
    }

    @Test("Spans covering the week end to end fill it exactly", arguments: [[4, 3], [5, 2], [1, 6], [2, 2, 3]])
    func spansTile(parts: [Int]) {
        // A row of spans is laid out in an HStack with one gap between each, so
        // the widths plus those gaps have to come back to the track or the row
        // will not line up with the daily row above it.
        let widths = parts.map { SlotLayout.spanWidth(trackWidth: trackWidth, dayCount: $0) }
        let total = widths.reduce(0, +) + CGFloat(parts.count - 1) * gap
        #expect(abs(total - trackWidth) < 0.0001)
    }

    @Test("Degenerate widths clamp instead of going negative")
    func degenerateWidths() {
        #expect(SlotLayout.slotWidth(trackWidth: 0, slotCount: 7) == 0)
        #expect(SlotLayout.slotWidth(trackWidth: 100, slotCount: 0) == 0)
        #expect(SlotLayout.spanWidth(trackWidth: 220, dayCount: 0) == 0)
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
