import SwiftUI

/// Draws one slot's mark, in the app and in the widget both.
///
/// Kept out of `SlotView` because the widget cannot use that type — it owns a
/// completion animation driven by `@State`, and a widget is a snapshot with no
/// state to drive. What the two must agree on is what a mark *looks like*, so
/// that is what lives here and nothing else.
struct SlotMarkView: View {
    let mark: SlotMark
    let size: CGSize
    /// Widget slots are distributed by their `HStack` and must not be pinned to
    /// a width; the app's are measured by `SlotLayout` and want one.
    var fillsWidth = false
    /// A span covering several days draws its completion as a bar rather than a
    /// dot — the mark has width to carry, so it does not need weight.
    var spansDays = false
    /// The rest day's column, in this mark's own coordinates, taken out of the
    /// shape. Nil on every mark that does not cross one. See `RestWindow`.
    var restWindow: ClosedRange<CGFloat>?

    var body: some View {
        switch mark {
        case .openToday:
            glow(.ring)
        case .doneToday, .donePast:
            // The same mark either way. A completion does not fade with age:
            // the row is a record of what happened, and Monday happened.
            glow(spansDays ? .bar : .dot)
        case .missed:
            missedMark
        case .upcoming:
            // The same shape and size as a completion, only unlit. A day that
            // has not happened and a day that has differ by exactly one thing —
            // whether there is light in it — which is the whole app stated as a
            // pair of marks.
            upcomingMark
        }
    }

    private func glow(_ shape: GlowShape) -> some View {
        GlowImageView(
            size: size, shape: shape, fillsWidth: fillsWidth, restWindow: restWindow
        )
    }

    @ViewBuilder
    private var upcomingMark: some View {
        if spansDays {
            sized(
                Capsule(style: .continuous)
                    .fill(GlowPalette.upcoming)
                    .frame(height: GlowShape.upcomingThickness)
                    .padding(.horizontal, (size.height - GlowShape.upcomingDiameter) / 2)
            )
            // Safe to mask out here rather than inside the shape: nothing
            // unlit casts a halo, so there is none to cut. The lit marks go
            // through `GlowImageView`, which subtracts the window before the
            // glow is generated from the shape.
            .restWindowRemoved(restWindow)
        } else {
            sized(
                Circle()
                    .fill(GlowPalette.upcoming)
                    .frame(
                        width: GlowShape.upcomingDiameter,
                        height: GlowShape.upcomingDiameter
                    )
            )
        }
    }

    /// The only mark with no glow at all, and the only one that is not a symbol.
    ///
    /// Two 1pt bars with 9pt arms, crossed at 45° — the design builds it that
    /// way, and an SF Symbol `xmark` scaled to the same footprint is visibly
    /// heavier, because its stroke thickens with its size while this one does
    /// not. Nothing carrying grey has an effect: a miss is an absence, and
    /// absence does not light up.
    private var missedMark: some View {
        let arm = size.height * GlowShape.missedArm
        let thickness = size.height * GlowShape.missedThickness
        return sized(
            ZStack {
                Rectangle().frame(width: thickness, height: arm)
                    .rotationEffect(.degrees(45))
                Rectangle().frame(width: thickness, height: arm)
                    .rotationEffect(.degrees(-45))
            }
            .foregroundStyle(GlowPalette.missed)
        )
    }

    @ViewBuilder
    private func sized(_ content: some View) -> some View {
        if fillsWidth {
            content.frame(maxWidth: .infinity).frame(height: size.height)
        } else {
            content.frame(width: size.width, height: size.height)
        }
    }
}
