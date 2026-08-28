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
        content.background { socketForMark }
    }

    /// The socket sits behind every mark that has one. A rest day has none —
    /// nothing is coming, so there is nothing for a socket to say (#72) — and
    /// a ✕ has none either: it is a claim about a day, not a slot waiting on
    /// one.
    @ViewBuilder
    private var socketForMark: some View {
        switch mark {
        case .rest, .missed:
            EmptyView()
        case .upcoming:
            // The upcoming pill *is* the socket, at 12pt with no inner shape,
            // so it draws its own bevel at its own height rather than taking
            // the 14pt one a lit mark grows into.
            sized(socket(size.height * GlowShape.upcomingPillHeight, circle: !spansDays))
                .restWindowRemoved(restWindow)
        case .openToday, .doneToday, .donePast:
            sized(socket(size.height * GlowShape.litPillHeight, circle: !spansDays))
                .restWindowRemoved(restWindow)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mark {
        case .openToday:
            glow(.ring)
        case .doneToday, .donePast:
            // The same mark either way. A completion does not fade with age:
            // the row is a record of what happened, and Monday happened.
            //
            // **Lit, not emitting** (#334, #332). This used to go through
            // `GlowImageView` and take the HDR tile, which is the emitting
            // tier. Under two tiers a completion is an object catching light
            // rather than a source of it, so it is a flat `#D9D9D9` fill with
            // the lit bevel — and §8.4 says the same thing from the other end:
            // it gives "lit fill" and "emitting" separate recipes, and the
            // emitting one is the open ring's.
            doneMark
        case .missed:
            missedMark.offset(x: restOffset(fillsSpan: false))
        case .upcoming:
            // The same shape and size as a completion, only unlit. A day that
            // has not happened and a day that has differ by exactly one thing —
            // whether there is light in it — which is the whole app stated as a
            // pair of marks.
            upcomingMark.offset(x: restOffset(fillsSpan: spansDays))
        case .rest:
            // Nothing at all — but at the slot's own size, so the column keeps
            // its width and the other six do not move. A socket here would say
            // *one is coming*, and on a rest day none is.
            sized(Color.clear)
        }
    }

    private func glow(_ shape: GlowShape) -> some View {
        GlowImageView(
            size: size, shape: shape, fillsWidth: fillsWidth, restWindow: restWindow
        )
    }

    /// A completion: the socket's inner shape, filled at the reflecting tier.
    ///
    /// §8.4's **lit fill** recipe — an inner white above and an inner black
    /// below, which is the socket's bevel inverted. A socket is pressed in; a
    /// completion stands proud of it.
    @ViewBuilder
    private var doneMark: some View {
        let fill = GlowPalette.lit
            .shadow(.inner(color: .white, radius: 1, y: 1))
            .shadow(.inner(color: .black.opacity(0.3), radius: 1, y: -1))
        if spansDays {
            sized(
                Capsule(style: .continuous)
                    .fill(fill)
                    .frame(
                        height: size.height * GlowShape.litPillHeight
                            - GlowShape.socketInset * 2
                    )
            )
            .restWindowRemoved(restWindow)
        } else {
            sized(Circle().fill(fill).padding(GlowShape.socketInset))
        }
    }

    /// The socket every mark sits in: **no fill at all, drawn entirely by its
    /// bevel** (#332, §8.3–8.4).
    ///
    /// An inner white above at 13% and an inner black below at full strength,
    /// which reads as a shape pressed into the surface. The design file gave it
    /// a `#D9D9D9 @ 1%` fill and §8.6 drops that as a slip — a socket is its
    /// bevel and nothing else.
    ///
    /// **`.shadow(.inner(_:))` cannot draw this, and that is measured.** An
    /// inner shadow on a `ShapeStyle` is modulated by the fill it decorates, so
    /// over `Color.clear` it paints nothing — probed by setting the light half
    /// to full-strength red and rendering, which produced no red pixel
    /// anywhere. Hence the older recipe below: a blurred stroke pushed
    /// off-centre and clipped to the shape, so only the part falling inside its
    /// edge survives.
    ///
    /// **Its weight is a device question.** The bevel was drawn against a 7–10%
    /// white ground, and #333 replaces that with a dark glass material, so the
    /// black half will read heavier than the file shows. Against today's pure
    /// black ground it is nearly invisible — the black half by definition, the
    /// white half at 13% — which is expected and is not evidence that it works.
    /// The simulator can say the geometry is right; it cannot say the depth is.
    @ViewBuilder
    private func socket(_ height: CGFloat, circle: Bool) -> some View {
        let shape = circle ? AnyShape(Circle()) : AnyShape(Capsule(style: .continuous))
        let bevel = ZStack {
            bevelEdge(shape, color: .white.opacity(0.13), y: -1.5)
            bevelEdge(shape, color: .black, y: 1.5)
        }
        if circle {
            bevel
        } else {
            bevel.frame(height: height)
        }
    }

    /// One half of a bevel, through the shared recipe below.
    private func bevelEdge(_ shape: AnyShape, color: Color, y: CGFloat) -> some View {
        InnerShadow(shape: shape, color: color, radius: 1.5, y: y)
    }

    /// A day, or a run of days, with nothing asked of it yet.
    ///
    /// **The socket's own shape, filled at the resting step** (#332). It was a
    /// 3pt dot and a 2pt line floating in the slot; it is a 22pt disc and a
    /// 12pt track now, so an upcoming day occupies its column instead of
    /// marking a point in it.
    ///
    /// An upcoming pill has **no inner shape** — the 12pt track *is* the
    /// socket, where a lit or open pill is a 14pt socket holding a 12pt inner.
    /// That is what makes a lit pill 2pt taller than the one it replaces: the
    /// light fills the track and the socket grows around it to hold the bevel.
    @ViewBuilder
    private var upcomingMark: some View {
        if spansDays {
            sized(
                Capsule(style: .continuous)
                    .fill(GlowPalette.grey)
                    .frame(height: size.height * GlowShape.upcomingPillHeight)
            )
            // Safe to mask out here rather than inside the shape: nothing
            // unlit casts a halo, so there is none to cut. The lit marks go
            // through `GlowImageView`, which subtracts the window before the
            // glow is generated from the shape.
            .restWindowRemoved(restWindow)
        } else {
            sized(
                Circle()
                    .fill(GlowPalette.grey)
                    .padding(GlowShape.socketInset)
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
            .foregroundStyle(GlowPalette.grey)
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

    /// Where a small mark sits when the rest day has taken part of its span.
    ///
    /// A ✕ and a socket are centred in their frame, and a span whose frame is
    /// partly removed would centre them into the removed part — drawn, and
    /// invisible. So they move to the middle of what is left (#100).
    ///
    /// Nothing for a bar or a lozenge: those fill their span and are cut by the
    /// window itself, which is the point of #73. This is only for the marks
    /// that are smaller than the shape they sit in.
    ///
    /// **A ✕ is one of those at any width.** `spansDays` decides bar-versus-dot
    /// and capsule-versus-circle; it does not reach `missedMark`, which is a
    /// fixed cross centred in whatever frame it is given. Guarding this on
    /// `!spansDays` therefore skipped exactly the case #100 is about — the
    /// two-column lost span — and the cross measured at its frame's centre,
    /// inside the removed window, rather than in the column left over.
    private func restOffset(fillsSpan: Bool) -> CGFloat {
        guard let restWindow, !fillsSpan else { return 0 }
        let low = max(restWindow.lowerBound, 0)
        let high = min(restWindow.upperBound, size.width)
        guard high > low else { return 0 }
        // Whichever side of the window has more room left.
        let leftRoom = low
        let rightRoom = size.width - high
        guard max(leftRoom, rightRoom) > 0 else { return 0 }
        let centre = leftRoom >= rightRoom ? leftRoom / 2 : high + rightRoom / 2
        return centre - size.width / 2
    }
}


/// An inner shadow, drawn the only way that works here.
///
/// **`.shadow(.inner(_:))` is not an option, and that is measured** (#332). An
/// inner shadow on a `ShapeStyle` is modulated by the fill it decorates, so
/// over a shape with no fill — which is what both callers have — it paints
/// nothing at all. Probed by setting a socket's light half to full-strength red
/// and rendering: zero red pixels, against 11,458 for this.
///
/// So: a stroke twice the blur radius wide, blurred, pushed off-centre, and
/// clipped back to the shape, leaving only the part that falls inside its edge.
///
/// Two callers, one recipe. `SlotMarkView` presses a socket into the surface
/// with a pair of these; `WeekWidgetView` lays one over the track. They are the
/// same effect at different scales, and a second implementation would be a
/// second thing to keep in step.
struct InnerShadow: View {
    let shape: AnyShape
    let color: Color
    let radius: CGFloat
    var x: CGFloat = 0
    var y: CGFloat = 0

    var body: some View {
        shape
            .stroke(color, lineWidth: radius * 2)
            .blur(radius: radius)
            .offset(x: x, y: y)
            .clipShape(shape)
            .allowsHitTesting(false)
    }
}
