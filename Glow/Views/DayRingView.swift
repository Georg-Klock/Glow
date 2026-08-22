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
///
/// **A tap sweeps** (#76): the line grows clockwise out of the run already
/// logged, and the pill retreats ahead of its head. One number drives both.
struct DayRingView: View {
    /// How many repetitions the day asks for, 1 to 12.
    let target: Int
    /// How many are logged so far today.
    let done: Int
    /// Outer diameter in points. Everything the ring draws stays inside it.
    let diameter: CGFloat

    /// Pulsing and sweeping are what Reduce Motion exists to switch off. The
    /// widget's burst already holds this line; so does the app's ring.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The repetition being logged, and where the line's head has reached.
    /// Non-nil only mid-flight — when it is nil the ring draws its settled
    /// truth and nothing else, which is `SlotView`'s shape and the reason no
    /// animating layer is ever left alive behind a still one.
    @State private var sweeping: Int?
    @State private var head: Double = 0

    /// Quick and decelerating: the line arrives and settles. Not a spring — a
    /// sweep has nothing past its end to overshoot into, so `SlotView.close`
    /// does not transfer. The duration is fixed however far the head travels;
    /// what is timed is the arrival, not the speed.
    private static let sweepDuration: Double = 0.35
    private static let sweep = Animation.easeOut(duration: sweepDuration)

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
            loggedLayer(arcs)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
        .onChange(of: done) { previous, next in start(from: previous, to: next) }
        // Any change of target is a different ring, not a repetition being
        // logged. Editing 8x down to 3x mid-sweep would otherwise leave the
        // head somewhere the new arcs do not have.
        .onChange(of: target) { _, _ in settle() }
    }

    // MARK: - The sweep

    /// Sweep only when a repetition was just logged.
    ///
    /// Everything else snaps, and each for its own reason. **The reset is
    /// instant** — a tap on a full ring sends the day back to zero, and
    /// animating a correction dresses a mistake up as an achievement, which is
    /// the rule `SlotView` already states. **Any jump other than +1 is
    /// instant** — a tap arriving from the widget while the app is foregrounded,
    /// a fresh day rolling over, an edit — none of those is a gesture anybody
    /// made on this ring. **Reduce Motion snaps**, because a line travelling
    /// around a circle is exactly what that setting is for.
    private func start(from previous: Int, to next: Int) {
        // The rule itself lives in `MotionPolicy`, with the grid's — one
        // setting, one place, four drawings of the same completion (#137).
        guard MotionPolicy.sweepsRing(
            from: previous, to: next, reduceMotion: reduceMotion
        ) else { return settle() }
        let arcs = self.arcs
        guard let range = DayRing.sweep(arcs: arcs, index: previous) else { return settle() }

        sweeping = previous
        head = range.from
        withAnimation(Self.sweep) { head = range.to }

        // Hand back to the resting drawing once it has settled. That drawing is
        // the same line the sweep ends on, so nothing moves at the handover.
        Task {
            try? await Task.sleep(for: .seconds(Self.sweepDuration))
            if done == next { settle() }
        }
    }

    private func settle() {
        sweeping = nil
    }

    /// Every repetition still open, outlined, as one glowed layer.
    ///
    /// While a sweep is running the repetition being logged is still drawn —
    /// trimmed to whatever the head has not yet reached. Its start angle *is*
    /// the head, so the pill retreats rather than cutting to a new width, and
    /// at the end of the sweep it has no span left and is gone.
    @ViewBuilder
    private func openLayer(_ arcs: [DayRing.Arc]) -> some View {
        let open = arcs.filter(\.isOpen)
        let retreating = sweeping.flatMap { index -> DayRing.Arc? in
            guard arcs.indices.contains(index), head < arcs[index].end else { return nil }
            return arcs[index]
        }
        if !open.isEmpty || retreating != nil {
            ZStack {
                ForEach(open) { arc in
                    DayRingArcShape(start: arc.start, end: arc.end, geometry: geometry)
                        .stroke(lineWidth: geometry.hairline)
                }
                if let arc = retreating {
                    // While the head is still crossing the gap the pill is
                    // untouched at full width; once it passes the pill's own
                    // start, the head is the start.
                    DayRingArcShape(
                        start: max(head, arc.start), end: arc.end, geometry: geometry
                    )
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
    private func loggedLayer(_ arcs: [DayRing.Arc]) -> some View {
        let logged = arcs.filter { !$0.isOpen }
        if let first = arcs.first, let last = logged.last {
            // At the goal it closes into a full circle: no break at twelve
            // o'clock where the first gap was, because when nothing is left
            // there is nothing to divide. That is also exactly what a habit
            // with a target of 1 shows when it is done, so "finished" is one
            // silhouette at every count.
            let closed = logged.count >= arcs.count
            // Mid-sweep the run ends at the head, which is what makes it grow
            // out of the existing line and cross the gap on its way.
            let end = sweeping != nil ? head : (closed ? first.start + 1 : last.end)
            DayRingRunShape(start: first.start, end: end, geometry: geometry)
                .stroke(lineWidth: geometry.hairline)
                .glowing(halo: diameter * GlowPalette.ringHaloRadius, style: .ring)
        }
    }
}
