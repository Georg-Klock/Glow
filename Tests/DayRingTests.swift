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

    @Test("A run of logged repetitions is one line, and it closes at the goal")
    func loggedRunMergesAndCloses() {
        // The endpoints the view draws the merged run between. One line for the
        // whole run rather than one per repetition: it crosses the gaps, so the
        // divisions only survive between repetitions still open.
        let gap = 3 / (32 * Double.pi)
        let arcs = DayRing.arcs(target: 6, done: 4, gap: gap)
        let logged = arcs.filter { !$0.isOpen }
        let open = arcs.filter(\.isOpen)

        #expect(logged.count == 4)
        #expect(open.count == 2)
        // The run spans from the first logged repetition's start to the fourth's
        // end, which is past the three gaps inside it.
        #expect(logged.first?.start == arcs[0].start)
        #expect(logged.last?.end == arcs[3].end)
        // And the division against the first still-open repetition survives.
        #expect((open[0].start - (logged.last?.end ?? 0)) > 0)

        // 6/6 closes and 5/6 does not.
        #expect(DayRing.arcs(target: 6, done: 6, gap: gap).allSatisfy { !$0.isOpen })
        #expect(DayRing.arcs(target: 6, done: 5, gap: gap).contains { $0.isOpen })
    }

    @Test("The gap is one band width, measured along the centreline")
    func gapFraction() {
        // A 4pt band inside a 40pt circle runs along a 36pt centreline: one
        // band width of trim over a circumference of 36π. It was two until
        // #75 — one width for round caps that no longer exist, plus one of
        // air — and a pill is bounded exactly by its own angles, so only the
        // air is left to pay for.
        let fraction = DayRing.gapFraction(strokeWidth: 4, diameter: 40)
        #expect(abs(fraction - 4 / (36 * Double.pi)) < 1e-9)

        // A band as wide as its circle has nowhere to run.
        #expect(DayRing.gapFraction(strokeWidth: 40, diameter: 40) == 0)
    }

    @Test("The gap is the same angle at every ring size")
    func gapIsAConstantAngle() {
        // Both the band and the gap scale with the diameter, so the gap is a
        // constant 3/(32π) of the circle — 10.74° — on the app's 92pt ring and
        // on both widget rings alike.
        for diameter in [92.0, 96.0, 76.0, 40.0] {
            let band = diameter * Double(GlowShape.ringWeight)
            let fraction = DayRing.gapFraction(strokeWidth: band, diameter: diameter)
            #expect(abs(fraction - 3 / (32 * Double.pi)) < 1e-9, "at \(diameter)pt")
            #expect(abs(fraction * 360 - 10.7429) < 0.001, "at \(diameter)pt")
        }
    }

    @Test("The half-slice clamp is dormant at every supported count")
    func clampNoLongerBinds() {
        // Twelve repetitions is the worst supported case: 30° of slice against
        // a 10.74° gap. The clamp stays as a guard against an unsupported
        // input, and this is the assertion that it is not silently doing the
        // work — if the gap ever grows past a half-slice again, the arcs stop
        // being what `gapFraction` says they are.
        let gap = 3 / (32 * Double.pi)
        for target in 1...12 {
            let slice = 1.0 / Double(target)
            #expect(gap <= slice / 2, "the clamp binds at a target of \(target)")
        }
    }

    @Test("Segment spans, at the counts the app offers")
    func segmentSpans() {
        // The issue's own table, in degrees, as the record of what the halved
        // gap draws.
        let gap = 3 / (32 * Double.pi)
        for (target, expected) in [(2, 169.26), (3, 109.26), (6, 49.26), (12, 19.26)] {
            let arcs = DayRing.arcs(target: target, done: 0, gap: gap)
            let span = (arcs[0].end - arcs[0].start) * 360
            #expect(abs(span - expected) < 0.01, "target \(target) spans \(span)°")
        }
    }
}
