import SwiftUI

/// One habit's day as a ring: an outlined pill per repetition still open, and
/// one line for the run already logged.
///
/// **Both are lit.** This view used to paint a logged repetition
/// `GlowPalette.labelResting` grey, which made it the one surface in the app
/// where a completion went quiet — everywhere else `SlotMarkView` sends a
/// completion straight to `GlowImageView`. What separates open from done here
/// is *shape*, not light: a band against a line (#75).
///
/// Drawn with the `glowing` modifier directly rather than through
/// `GlowImageView`: that view exists for the slot marks, whose silhouettes are
/// each one shape at one size, and an arc's geometry depends on its index and
/// its count. The glow itself costs the same either way — the HDR tile is
/// shape-free and cached per intensity, so an arc is a mask like any other, not
/// a new cache entry.
///
/// Two glowed layers, not one per mark: one tile and one halo pass for the
/// whole open share, and one for the logged run.
struct DayRingView: View {
    /// How many repetitions the day asks for, 1 to 12.
    let target: Int
    /// How many are logged so far today.
    let done: Int
    /// Outer diameter in points. Everything the ring draws stays inside it.
    let diameter: CGFloat

    private var geometry: DayRingGeometry { DayRingGeometry(diameter: diameter) }

    private var arcs: [DayRing.Arc] {
        DayRing.arcs(
            target: target,
            done: done,
            gap: DayRing.gapFraction(
                strokeWidth: geometry.band, diameter: diameter
            )
        )
    }

    var body: some View {
        let arcs = self.arcs
        let logged = arcs.filter { !$0.isOpen }

        ZStack {
            // The pills' interiors are left clear rather than filled black.
            //
            // Two reasons, and the first is fatal rather than stylistic:
            // `glowing` masks its HDR tile with the view it wraps, and a mask
            // reads *alpha*. An opaque black fill inside the glowed layer has
            // alpha 1 and would light the whole pill solid — the exact opposite
            // of an outline. The second is the widget: a Clear or Tinted Home
            // Screen renders it accented, which discards colour and keeps
            // alpha, so a black fill would come back as a solid white pill
            // there. Clear stays clear on both.
            openLayer(arcs)
            loggedLayer(logged, count: arcs.count)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    /// Every repetition still open, outlined, as one glowed layer.
    @ViewBuilder
    private func openLayer(_ arcs: [DayRing.Arc]) -> some View {
        let open = arcs.filter(\.isOpen)
        if !open.isEmpty {
            ZStack {
                ForEach(open) { arc in
                    DayRingArcShape(start: arc.start, end: arc.end, geometry: geometry)
                        .stroke(lineWidth: geometry.hairline)
                }
            }
            .glowing(halo: diameter * GlowPalette.ringHaloRadius, style: .ring)
        }
    }

    /// The run already logged, as one line.
    ///
    /// One line for the whole run rather than one per repetition: consecutive
    /// completions merge and the line crosses the gaps between them, so the
    /// divisions only survive between repetitions still open. Same rule as a
    /// run of days in the week grid, which is one bar and not a row of dots.
    @ViewBuilder
    private func loggedLayer(_ logged: [DayRing.Arc], count: Int) -> some View {
        if let first = logged.first, let last = logged.last {
            // At the goal it closes into a full circle: no break at twelve
            // o'clock where the first gap was, because when nothing is left
            // there is nothing to divide. That is also exactly what a habit
            // with a target of 1 shows when it is done, so "finished" is one
            // silhouette at every count.
            let closed = logged.count >= count
            DayRingRunShape(
                start: closed ? 0 : first.start,
                end: closed ? 1 : last.end,
                geometry: geometry
            )
            .stroke(lineWidth: geometry.hairline)
            .glowing(halo: diameter * GlowPalette.ringHaloRadius, style: .ring)
        }
    }
}
