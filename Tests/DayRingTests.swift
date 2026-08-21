import Foundation
import Testing
@testable import Glow

/// The Today ring's geometry: one arc per repetition, quiet from the top as
/// the day is logged.
@Suite("Day ring")
struct DayRingTests {
    @Test("One arc per repetition, at every selectable target")
    func onePerRepetition() {
        for target in Frequency.selectableDailyCounts {
            #expect(DayRing.arcs(target: target, done: 0).count == target)
        }
    }

    @Test("At a target of 1 the ring is a single unbroken circle, gap or not")
    func singleCircle() {
        let arcs = DayRing.arcs(target: 1, done: 0, gap: 0.1)
        #expect(arcs == [DayRing.Arc(index: 0, start: 0, end: 1, isOpen: true)])

        // Logged, it is the same circle, quiet.
        let done = DayRing.arcs(target: 1, done: 1, gap: 0.1)
        #expect(done == [DayRing.Arc(index: 0, start: 0, end: 1, isOpen: false)])
    }

    @Test("The ring starts full and glowing, and each completion quiets one arc from the top")
    func quietsFromTheTop() {
        for done in 0...4 {
            let arcs = DayRing.arcs(target: 4, done: done)
            #expect(arcs.map(\.isOpen) == (0..<4).map { $0 >= done })
        }
    }

    @Test("At the goal the ring is quiet, and past it stays quiet")
    func quietAtGoal() {
        #expect(DayRing.arcs(target: 3, done: 3).allSatisfy { !$0.isOpen })
        // A count can overshoot its target after an edit from 8x down to 3x.
        #expect(DayRing.arcs(target: 3, done: 7).allSatisfy { !$0.isOpen })
        // And an impossible negative is a full ring, not a crash.
        #expect(DayRing.arcs(target: 3, done: -2).allSatisfy { $0.isOpen })
    }

    @Test("Arcs are equal shares, in order, separated by uniform gaps")
    func equalShares() {
        let gap = 0.02
        let arcs = DayRing.arcs(target: 6, done: 0, gap: gap)
        let slice = 1.0 / 6

        for arc in arcs {
            #expect(abs((arc.end - arc.start) - (slice - gap)) < 1e-9)
            #expect(abs(arc.start - (Double(arc.index) * slice + gap / 2)) < 1e-9)
        }
        // Ordered and non-overlapping: each arc ends before the next begins.
        for (earlier, later) in zip(arcs, arcs.dropFirst()) {
            #expect(earlier.end < later.start)
        }
    }

    @Test("A gap can never eat more than half a slice, so twelve arcs stay twelve arcs")
    func gapIsClamped() {
        let arcs = DayRing.arcs(target: 12, done: 0, gap: 0.5)
        let slice = 1.0 / 12
        for arc in arcs {
            #expect((arc.end - arc.start) >= slice / 2 - 1e-9)
        }
    }

    @Test("A degenerate target is clamped into the selectable range")
    func targetIsClamped() {
        #expect(DayRing.arcs(target: 0, done: 0).count == 1)
        #expect(DayRing.arcs(target: -3, done: 0).count == 1)
        #expect(DayRing.arcs(target: 40, done: 0).count == 12)
    }

    @Test("A tap adds one until the ring is full, and then resets to zero", arguments: [
        // (count, target) -> what the tap leaves the day at
        (0, 3, 1), (1, 3, 2), (2, 3, 3), (3, 3, 0),
        (0, 1, 1), (1, 1, 0),
        (11, 12, 12), (12, 12, 0),
    ])
    func tapRule(count: Int, target: Int, expected: Int) {
        #expect(DayRing.countAfterTap(count: count, target: target) == expected)
    }

    @Test("A count past its target resets like a full ring, not past it")
    func overshootResets() {
        // Reachable by editing a habit from 8x down to 3x with five logged.
        #expect(DayRing.countAfterTap(count: 5, target: 3) == 0)
        // And degenerate inputs stay in range rather than crashing.
        #expect(DayRing.countAfterTap(count: -2, target: 3) == 1)
        #expect(DayRing.countAfterTap(count: 0, target: -1) == 1)
        #expect(DayRing.countAfterTap(count: 1, target: -1) == 0)
    }

    @Test("The gap for a stroke is measured along its centreline")
    func gapFraction() {
        // A 4pt stroke kept inside a 40pt circle runs along a 36pt centreline:
        // two stroke-widths of trim over a circumference of 36π.
        let fraction = DayRing.gapFraction(strokeWidth: 4, diameter: 40)
        #expect(abs(fraction - 8 / (36 * Double.pi)) < 1e-9)

        // A stroke as wide as its circle has nowhere to run.
        #expect(DayRing.gapFraction(strokeWidth: 40, diameter: 40) == 0)
    }
}
