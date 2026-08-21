import SwiftUI

/// One habit's day as a ring of arcs, the open share glowing.
///
/// Drawn with the `glowing` modifier directly rather than through
/// `GlowImageView`: that view exists for the slot marks, whose silhouettes are
/// each one shape at one size, and an arc's geometry depends on its index and
/// its count. The glow itself costs the same either way — the HDR tile is
/// shape-free and cached per intensity, so an arc is a mask like any other,
/// not a new cache entry.
///
/// The open arcs glow as one layer, not one modifier each: one tile and one
/// halo pass for the whole remaining share of the day, instead of a dozen
/// separately composited lights.
struct DayRingView: View {
    /// How many repetitions the day asks for, 1 to 12.
    let target: Int
    /// How many are logged so far today.
    let done: Int
    /// Outer diameter in points. The stroke stays inside it.
    let diameter: CGFloat

    /// The same stroke-to-size ratio as the week grid's open ring, so the two
    /// rings are one drawing at two sizes rather than cousins.
    private var strokeWidth: CGFloat { diameter * GlowShape.ringWeight }

    private var arcs: [DayRing.Arc] {
        DayRing.arcs(
            target: target,
            done: done,
            gap: DayRing.gapFraction(strokeWidth: strokeWidth, diameter: diameter)
        )
    }

    var body: some View {
        let open = arcs.filter(\.isOpen)
        let quiet = arcs.filter { !$0.isOpen }

        ZStack {
            // A logged repetition is a habit already handled today, and takes
            // that grey — present, legible, asking for nothing.
            layer(quiet)
                .foregroundStyle(GlowPalette.labelResting)
            if !open.isEmpty {
                layer(open)
                    .glowing(
                        halo: diameter * GlowPalette.ringHaloRadius,
                        style: .ring
                    )
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func layer(_ set: [DayRing.Arc]) -> some View {
        ZStack {
            ForEach(set) { arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    // Trim starts at three o'clock; the ring starts at twelve.
                    .rotation(.degrees(-90))
                    .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    // Half the stroke, so the stroke's outer edge lands on the
                    // frame instead of spilling past it.
                    .padding(strokeWidth / 2)
            }
        }
    }
}
