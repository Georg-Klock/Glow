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
    /// How far this mark's anchor column sits from the centre of its own
    /// frame. Only the ✕ reads it — every other mark either fills its span or
    /// is one column wide. See `SlotLayout.anchorOffset(trackWidth:dayCount:)`.
    var anchorOffset: CGFloat = 0

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
        // **One socket, at one height.** These were two branches: an upcoming
        // pill stood 2pt shorter so a lit ring's inner matched its outer
        // exactly, and the light filled the track while the socket grew around
        // it. Both are 14 now — the recess is the same whatever the day says,
        // and only what sits inside it differs. An upcoming pill still has no
        // inner shape at all: it *is* the socket, and its bevel is the mark.
        // See `GlowShape.pillHeight`.
        case .upcoming, .openToday, .doneToday, .donePast:
            sized(socket(size.height * GlowShape.pillHeight, circle: !spansDays))
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
            // **The ✕ sits on its anchor day** (#389) — the span's last column,
            // because a mark ends on its anchor and the columns before it are
            // the days it swallowed (`docs/week-marks.md` §4).
            //
            // It used to be centred in the span's frame, so every dead mark
            // wider than one column drew its cross on a day it had nothing to
            // do with, and an even-width one drew it in the gap *between* two
            // columns — a ✕ with no day to its name. Reported off a device as
            // a `WeekSpans` fault, which it was not: the arithmetic said one
            // thing and the drawing said another.
            //
            // A span crossing the rest day keeps #100's fallback instead. A
            // pinned ✕ never anchors on one — `WeekSpans.deadDays` excludes it
            // from the candidates — but a floating one (§5.1) has no anchor to
            // sit on, and then the window is all there is to place it by. The
            // rest day is retired (#390) and comes back with its own design
            // work in #391 and #392.
            missedMark.offset(
                x: restWindow == nil ? anchorOffset : restOffset(fillsSpan: false)
            )
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
            size: size, shape: shape, fillsWidth: fillsWidth,
            spansDays: spansDays, restWindow: restWindow
        )
    }

    /// A completion: the socket's inner shape, filled at the reflecting tier.
    ///
    /// §8.4's **lit fill** recipe — an inner white above and an inner black
    /// below, which is the socket's bevel inverted. A socket is pressed in; a
    /// completion stands proud of it.
    @ViewBuilder
    private var doneMark: some View {
        // The lit fill's own pair does *not* scale — the file draws it at 1 on
        // the 24pt slot and at 1 on the 16pt cell both — but the track's shade
        // does, and it lands on a completion exactly as it lands on a socket.
        let fill = GlowPalette.lit
            .shadow(.inner(color: .white, radius: 1, y: 1))
            .shadow(.inner(color: .black.opacity(0.3), radius: 1, y: -1))
            .shadow(.inner(
                color: .black.opacity(0.25),
                radius: Self.well(size.height),
                y: Self.well(size.height)
            ))
        if spansDays {
            sized(
                Capsule(style: .continuous)
                    .fill(fill)
                    .frame(
                        height: size.height * GlowShape.pillHeight
                            - GlowShape.socketInset * 2
                    )
                    // Both axes, like `.dot`'s `.padding(socketInset)`. The
                    // height is spelled out because it comes off the pill
                    // rather than off the slot; the width was simply missing.
                    .padding(.horizontal, GlowShape.socketInset)
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
            bevelEdge(shape, color: .white.opacity(0.13), y: -Self.bevel(size.height))
            bevelEdge(shape, color: .black, y: Self.bevel(size.height))
            wellShadow(shape)
        }
        if circle {
            bevel
        } else {
            bevel.frame(height: height)
        }
    }

    /// One half of a bevel, at the size the slot asks for.
    private func bevelEdge(_ shape: AnyShape, color: Color, y: CGFloat) -> some View {
        InnerShadow(shape: shape, color: color, radius: Self.bevel(size.height), y: y)
    }

    /// **The grid's own shade, on the mark rather than behind it.**
    ///
    /// §8.4's fourth recipe belongs to `Frame 14`, the track — and in the
    /// design file that frame has *no fill*, so its inner shadow falls on the
    /// union of the marks' own alpha and not on a panel. The small widget's
    /// export is where that is unambiguous: every socket and every lit fill
    /// carries `inset 0 4px 4px rgba(0,0,0,0.25)` of its own, which is this
    /// shadow already composited onto each shape.
    ///
    /// It shipped as a `Rectangle` overlaid across the track, which is a shape
    /// the file does not contain and read as a box drawn around the grid.
    private func wellShadow(_ shape: AnyShape) -> some View {
        InnerShadow(
            shape: shape,
            color: .black.opacity(0.25),
            radius: Self.well(size.height),
            y: Self.well(size.height)
        )
    }

    /// The bevel's offset and blur, as a fraction of the slot.
    ///
    /// 1.5 on the week grid's 24pt slot and 1.0 on the month's 16pt cell —
    /// nodes `228:10690` and `234:11216` — which is one sixteenth of the slot
    /// at both. It shipped hard-coded at 1.5, so the month's cells wore the
    /// week's bevel at 150% of the size the file draws.
    static func bevel(_ slot: CGFloat) -> CGFloat { slot / 16 }

    /// The track's shade, likewise: 6 on 24 and 4 on 16, a quarter of the slot.
    static func well(_ slot: CGFloat) -> CGFloat { slot / 4 }

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
    /// **Nothing.** The socket behind it is the whole mark.
    ///
    /// §8.3: "the socket has no fill at all — it is drawn entirely by its
    /// bevel", and the upcoming row of its table gives `Inner: none`. §8.6
    /// drops the design file's `#D9D9D9 @ 1%` as a slip for the same reason.
    ///
    /// It shipped filled at the resting step, which made a day still to come
    /// the brightest thing on an untouched row and put the grid back on a grey
    /// ramp — three strengths of the same disc, which is what #111 collapsed.
    /// It also contradicted the line `CLAUDE.md` opens with: *what stays dark
    /// is absence — a missed day, a day still to come, a rep that ran out of
    /// days*.
    ///
    /// **An empty slot is not asked to meet contrast.** It is the ground the
    /// lit marks are read against, and being hard to see is the whole of its
    /// job.
    private var upcomingMark: some View {
        sized(Color.clear)
    }

    /// The only mark with no glow at all, and the only one that is not a symbol.
    ///
    /// Two 1pt bars with 9pt arms, crossed at 45° — the design builds it that
    /// way, and an SF Symbol `xmark` scaled to the same footprint is visibly
    /// heavier, because its stroke thickens with its size while this one does
    /// not. Nothing carrying grey has an effect: a miss is an absence, and
    /// absence does not light up.
    private var missedMark: some View {
        let shape = AnyShape(CrossShape())
        let bevel = size.height * GlowShape.missedBevel
        return sized(
            ZStack {
                InnerShadow(shape: shape, color: .black, radius: bevel, y: bevel)
                InnerShadow(
                    shape: shape, color: .white.opacity(0.25), radius: bevel, y: -bevel
                )
            }
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

    /// **The shape's alpha, minus an offset blurred copy of itself.** That is
    /// what an inner shadow *is*, in Figma and in CSS both, and it is why this
    /// is a mask rather than a stroke.
    ///
    /// It used to be `shape.stroke(lineWidth: radius * 2).blur(radius:)`
    /// clipped to the shape, and the geometry of that is right but the opacity
    /// is not: a stroke of width `2r` blurred by `r` spreads over roughly `4r`,
    /// so the peak drops well under the colour it was given, and then half of
    /// what is left falls outside the clip. A `#000000` at full strength landed
    /// nowhere near it — measured at 27 levels of depth against a ground of 31
    /// where the design file gets 78 against 86, and no ground fixed it: at a
    /// lighter ground the dark half improved and the *white* half fell away,
    /// 17 down to 10, where the file holds 78 and 20 at once.
    ///
    /// `.shadow(.inner(_:))` is not the answer either, and that is measured too
    /// — an inner shadow on a `ShapeStyle` is modulated by the fill it
    /// decorates, so over a socket's no-fill it paints nothing.
    var body: some View {
        color
            .mask {
                shape
                    .fill(.black)
                    .overlay {
                        shape
                            .fill(.black)
                            .offset(x: x, y: y)
                            .blur(radius: radius)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .clipShape(shape)
            .allowsHitTesting(false)
    }
}

/// The missed ✕, as the file draws it: two rounded bars crossed at ±45°.
///
/// A `Shape` rather than two rotated rectangles, because the mark is *pressed
/// into* the surface (§8.4's socket recipe at half weight) and an inner shadow
/// needs one silhouette to subtract from — two rectangles would each get their
/// own bevel and show the seam where they cross. Both bars go into one `Path`,
/// so the non-zero fill rule unions them and the bevel sees a single cross.
///
/// The proportions come off the cross path in node `234:11216`: a bar a quarter
/// of the cell thick and seven eighths long, which at ±45° occupies
/// `(7/8 + 1/4) / √2` — 0.795 of the cell, matching the file's 12.73 in 16.
struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let length = side * GlowShape.missedLength
        let thickness = side * GlowShape.missedThickness
        let corner = side * GlowShape.missedCorner
        var path = Path()
        for degrees in [45.0, -45.0] {
            var bar = Path()
            bar.addRoundedRect(
                in: CGRect(x: -length / 2, y: -thickness / 2,
                           width: length, height: thickness),
                cornerSize: CGSize(width: corner, height: corner)
            )
            path.addPath(bar, transform:
                CGAffineTransform(rotationAngle: degrees * .pi / 180)
                    .concatenating(CGAffineTransform(
                        translationX: rect.midX, y: rect.midY)))
        }
        return path
    }
}
