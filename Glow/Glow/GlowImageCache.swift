import SwiftUI
import UIKit

/// Holds the rendered tiles, one per glow intensity.
///
/// The tile is uniform and shape-free, so unlike the earlier per-size, per-hue
/// cache there is one image per distinct intensity rather than per slot. In
/// practice that is one image, and briefly a handful while a slider moves.
@MainActor
final class GlowImageCache {
    static let shared = GlowImageCache()

    private var tiles: [Int: UIImage] = [:]
    /// Intensities that failed to render, so a broken combination is attempted
    /// once rather than on every layout pass.
    private var failures: Set<Int> = []

    /// Rounded to a tenth: a slider drag would otherwise mint a distinct
    /// encode per pixel of travel.
    private func key(_ peak: Double) -> Int { Int((peak * 10).rounded()) }

    /// The lit tile at a given intensity, or nil if it could not be rendered.
    /// Callers fall back to a flat shape, which is also what a screen with no
    /// headroom shows, so there is no visually broken state either way.
    func litTile(peak: Double) -> UIImage? {
        let k = key(peak)
        if let tile = tiles[k] { return tile }
        if failures.contains(k) { return nil }

        var renderer = GlowRenderer()
        renderer.peakHeadroom = CGFloat(GlowSettings.clamp(peak))

        do {
            let data = try renderer.imageData(color: GlowPalette.components)
            guard let image = UIImage(data: data) else {
                failures.insert(k)
                return nil
            }
            tiles[k] = image
            return image
        } catch {
            failures.insert(k)
            return nil
        }
    }

    func removeAll() {
        tiles.removeAll()
        failures.removeAll()
    }
}

/// The silhouette a glow is cut to.
///
/// The tile itself is a flat square of uniform HDR colour and carries no shape
/// at all, so anything that can be a mask can be a glow. That is the whole
/// reason a glowing checkmark costs no more than a glowing pill.
enum GlowShape: Equatable {
    /// Solid, edge to edge. The middle beat of a completion, and nothing at
    /// rest — for one moment the slot is the brightest thing the screen shows.
    case capsule
    /// A hollow outline: today, still open.
    case ring
    /// A completion. Small and solid, the same mark whatever day it fell on.
    case dot
    /// A completion on a row that spans days rather than filling one — thinner
    /// than a dot, because it is carrying width instead of weight.
    case bar

    // Proportions of the slot's height, measured from the design rather than
    // guessed, so the whole grid scales from one number.

    /// Stroke width of `.ring`: **1pt, flat** (#332, #336).
    ///
    /// Not a fraction of the slot any more. It was `3 / 35`, and the design
    /// file measured at `228:11107` draws the same weight around a 12pt pill
    /// and a 22pt circle — a constant, not a proportion. That `3 / 35 × 12`
    /// lands on 1.03 is a coincidence, and reading a rule out of it would have
    /// given the circle a 2pt stroke it does not have.
    ///
    /// Inside-aligned, so the outer edge is flush with the ring's box.
    static let ringWeight: CGFloat = 1

    /// **A mark is a socket with an inner shape** (#332, §8.3).
    ///
    /// The socket has no fill at all — it is drawn entirely by its bevel. The
    /// inner shape is the socket inset by this on all four sides with its
    /// radius reduced by the same, and it is what carries the state: filled for
    /// a completion, stroked for an open slot, absent for an upcoming pill.
    static let socketInset: CGFloat = 1

    /// The socket's height, as a fraction of the slot: **one height for every
    /// mark**, spanning or not — the slot's own, 24pt at a 24pt slot, with
    /// `socketInset` leaving the 22pt inner every circle already had.
    ///
    /// **It has been three numbers.** An upcoming pill was 12 and a lit one 14,
    /// so the lit ring's inner was exactly the outer of the upcoming track it
    /// replaced; #332 collapsed both to 14, "one constant rather than two that
    /// happen to be equal". #426 takes it to the slot: a pill and a circle are
    /// the same recess with the same inner, so a five-day span carries the same
    /// weight per column as the day marks beside it rather than reading as a
    /// lighter bar.
    ///
    /// It is kept as a named constant at 1 rather than deleted, so that "one
    /// height for every mark" stays something the code says out loud and both
    /// shapes stay derivable from one number.
    ///
    /// **This is a deliberate divergence from the design file.** Node
    /// `248:12822` draws spanning marks visibly thinner than the circles; after
    /// #426 the app does not, and the file is the stale one. See
    /// `docs/decisions.md`.
    static let pillHeight: CGFloat = 1

    /// The missed ✕, as fractions of the slot — **not** of 17.5.
    ///
    /// Those denominators were the old slot width, and the ✕ was the one mark
    /// #331 did not rescale when the grid went to 24: it stayed a hairline
    /// where the file draws a bar a quarter of the slot thick. Measured off the
    /// cross path in node `234:11216`, whose 16pt cell carries a 4.0 bar on a
    /// 12.73 span — a quarter and seven eighths, which is what these are.
    ///
    /// `missedLength` is the bar *before* it is crossed: two of them at ±45°,
    /// and `(length + thickness) / √2` is the span they occupy, so 7/8 and 1/4
    /// give 0.795 of the slot exactly as the file does.
    static let missedThickness: CGFloat = 1.0 / 4.0
    static let missedLength: CGFloat = 7.0 / 8.0
    static let missedCorner: CGFloat = 1.0 / 32.0

    /// The ✕'s own bevel, half the socket's. It is **pressed in like a socket,
    /// not painted like a glyph**: the file gives it no fill and two inner
    /// shadows — black at full strength below, white at 25% above — where the
    /// code drew a flat grey cross.
    static let missedBevel: CGFloat = 1.0 / 32.0

    /// **No longer the grid's marks** (#332). Both were: a completion was a 3pt
    /// dot and a run of them a 2pt line, floating in a 17.455pt socket. A
    /// completion fills its slot now.
    ///
    /// They survive because they were doing a second job all along, and only
    /// that job is left:
    ///
    ///  - `barThickness` is the weight of a *hairline* — the rest day's cut
    ///    down a column, and the border on the Widgets tab's preview cards.
    ///    Those are not marks and never scaled with the slot.
    ///  - `dotDiameter` is the pop's own dot, in the Island and in the app's
    ///    acknowledgement, and the size `SlotView` animates a closing
    ///    completion down to.
    ///
    /// Kept under their old names rather than renamed, because renaming them
    /// would touch nine call sites to say the same thing; what changed is what
    /// they are *not* used for.
    static let dotDiameter: CGFloat = 3
    static let barThickness: CGFloat = 2
}

/// The HDR tile itself, sized by whatever it is put inside.
///
/// Falls back to flat colour when the tile cannot be rendered, which is also
/// what a screen with no headroom shows — so there is no visually broken state
/// either way.
private struct GlowTile: View {
    let peak: Double

    var body: some View {
        if let tile = GlowImageCache.shared.litTile(peak: peak) {
            Image(uiImage: tile)
                .resizable()
                // Without this the image is tone-mapped to SDR and the whole
                // exercise is a slightly bright rectangle.
                .allowedDynamicRange(.high)
                // And without this, a widget on a Tinted or Clear home screen
                // renders in accented mode, which tints an opaque image to a
                // single flat white — discarding the headroom that is the entire
                // point of this file. Apple reserves `.fullColor` for media like
                // album art; the argument for it here is that the light *is* the
                // content, not a decoration applied to it.
                //
                // Whether it is honoured there is still unmeasured, and the
                // simulator cannot settle it: with no EDR headroom the tile is
                // tone-mapped anyway, and against glass a flattened white and a
                // lit white are the same pixels. What the simulator does show is
                // that the *halo* does not survive — see GlowModifier — so a
                // mark on a Tinted or Clear home screen reads as a flat shape
                // whatever this line does for the core. #53.
                .widgetAccentedRenderingMode(.fullColor)
        } else {
            GlowPalette.color
        }
    }
}

/// Renders anything as a real glow: the HDR tile masked to its shape, with the
/// halo cast underneath.
///
/// Applies to *any* view, not just the slot shapes, because the rule it serves
/// is a rule about the design file rather than about geometry: full white plus a
/// drop shadow means headroom. That covers the marks, and it also covers the
/// label of a habit still due and today's letter in the header, both of which
/// are drawn exactly that way and were rendering as merely bright text.
///
/// The halo is an ordinary SwiftUI shadow rather than part of the image. Two
/// reasons. The image is opaque, because the PQ encoder drops alpha, so a halo
/// baked into it would arrive as a black square covering its neighbours. And a
/// shadow composites against whatever is behind it, which an opaque tile cannot.
/// The core is what has to be HDR; a halo is dimmer than its source by
/// definition, so nothing is lost by drawing it in SDR.
///
/// It is lost on a Tinted or Clear home screen, though: the same widget renders
/// today's ring with a halo under Default and as a bare white circle under both
/// of the others. Measured in the simulator, 2026-08-21. Nothing here can put
/// it back — see #53 — so a widget on those appearances shows the marks without
/// the light around them.
///
/// The caster is the same view as the mask, which matters for a hollow shape: a
/// solid caster under a ring shows through the hole as a grey lozenge, and the
/// slot stops reading as an outline.
struct GlowModifier: ViewModifier {
    /// Halo reach in points before the intensity setting scales it.
    let halo: CGFloat
    /// The design draws the ring's halo softer, offset above and below, and at
    /// half strength; every other glow is one plain shadow at full strength.
    var style: Style = .plain

    enum Style: Equatable {
        case plain
        case ring
    }

    @AppStorage(GlowSettings.key, store: GlowSettings.store)
    private var peak: Double = GlowSettings.defaultValue

    // The toggle removes the caster's drop shadows and nothing else (#313):
    // the tile overlay below draws regardless, so a mark keeps its HDR fill
    // with no light spread onto the ground. The ring's inner shadow pair is
    // deliberately not behind this — it is baked into the stroke in
    // `GlowImageView` as the ring's own thickness, light in the tube rather
    // than light on the ground, and a build with the pair removed rendered a
    // ring near-identical at slot size, so gating it would change the mark's
    // silhouette for nothing.
    @AppStorage(GlowSettings.haloDisabledKey, store: GlowSettings.store)
    private var haloDisabled: Bool = false

    private var haloRadius: CGFloat {
        halo * CGFloat(GlowSettings.haloScale(for: peak))
    }

    @ViewBuilder
    private func caster(_ content: some View) -> some View {
        let base = content.foregroundStyle(GlowPalette.color)
        if haloDisabled {
            base
        } else {
            switch style {
            case .plain:
                base.shadow(color: GlowPalette.color, radius: haloRadius)
            case .ring:
                // Two passes offset up and down rather than one centred: it is
                // what the file specifies, and it reads as a tube of light
                // rather than a disc behind a hole. The offset is its own
                // number, not a fraction of the radius: the file pairs a
                // radius of 5 with an offset of 1.25, so the offset is a
                // quarter of the reach.
                let offset = haloRadius * GlowPalette.ringHaloOffsetRatio
                base
                    .shadow(
                        color: GlowPalette.color.opacity(GlowPalette.ringHaloOpacity),
                        radius: haloRadius, y: offset
                    )
                    .shadow(
                        color: GlowPalette.color.opacity(GlowPalette.ringHaloOpacity),
                        radius: haloRadius, y: -offset
                    )
            }
        }
    }

    func body(content: Content) -> some View {
        // An overlay rather than a ZStack, and that is load-bearing: the tile is
        // a `resizable()` image, so inside a ZStack it expands to whatever space
        // is going and drags the layout with it. Text glowed that way stops
        // hugging its leading edge and drifts to the middle of whatever it is
        // in. An overlay takes the base view's size and cannot do that.
        //
        // The caster is one shadow, not the three this used to stack: the design
        // specifies a single blur per mark, and three passes were an invention
        // approximating a long tail the file never asked for.
        // Nothing here animates on its own. A lit mark is lit and holds still:
        // the glow's one signal is brightness, and the breath that used to
        // pulse this layer said the same thing a second time, in a register
        // nothing else in the app uses. Removed 2026-08-21; docs/glow.md keeps
        // the history, including the measurement that the compositor does not
        // flatten an animated HDR layer.
        //
        // `geometryGroup()` is a guard now, not a fix. The content is measured
        // twice — once for the caster, once for the mask — and while a
        // repeating animation lived here, the second measurement became
        // something to interpolate: the breath walked Today's rings ~15pt
        // sideways (#45). With the breath gone nothing animates this geometry,
        // but the pin stays for the next caller who animates anything here —
        // and it belongs exactly at this line. Written above `.opacity`, where
        // it reads just as sensibly, it was built and measured *still
        // drifting*: by that point both measurements have already happened.
        let settled = content.geometryGroup()
        return caster(settled)
            .overlay { GlowTile(peak: peak).mask { settled } }
    }
}

extension View {
    /// Draw this view as a real glow rather than as bright colour.
    func glowing(
        halo: CGFloat,
        style: GlowModifier.Style = .plain
    ) -> some View {
        modifier(GlowModifier(halo: halo, style: style))
    }
}

/// Everything except one vertical window: the mask that takes the rest day's
/// column out of a span.
///
/// A `Shape` rather than a stack of rectangles, because the window is given in
/// points and the thing being masked may be sized by its container — a shape is
/// handed the resolved rect and can clamp against it. Clamping is what makes
/// one number cover both cases: a window in the middle of a span is a hole, and
/// a window at either end is a shortening.
struct RestWindowMask: Shape {
    let window: ClosedRange<CGFloat>

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let low = min(max(window.lowerBound, rect.minX), rect.maxX)
        let high = min(max(window.upperBound, rect.minX), rect.maxX)
        if low > rect.minX {
            path.addRect(CGRect(
                x: rect.minX, y: rect.minY, width: low - rect.minX, height: rect.height
            ))
        }
        if high < rect.maxX {
            path.addRect(CGRect(
                x: high, y: rect.minY, width: rect.maxX - high, height: rect.height
            ))
        }
        return path
    }
}

extension View {
    /// Take the rest day's column out of this view. A no-op when there is none,
    /// so the common case adds no layer.
    @ViewBuilder
    func restWindowRemoved(_ window: ClosedRange<CGFloat>?) -> some View {
        if let window {
            mask { RestWindowMask(window: window).fill(.black) }
        } else {
            self
        }
    }
}

/// A lit slot: one of the mark silhouettes, glowing.
struct GlowImageView: View {
    let size: CGSize
    var shape: GlowShape = .capsule
    /// Overrides the ring's stroke, which is otherwise a fraction of the height.
    ///
    /// Exists so a ring can shrink without its stroke shrinking with it. Hold
    /// the stroke at 1.5 and close the diameter, and the hole — diameter minus
    /// twice the stroke — reaches zero at exactly 3pt: the ring *becomes* the
    /// dot. No cross-fade, no second layer, one shape and one number.
    var ringLineWidth: CGFloat?
    /// When true the tile takes whatever width the layout offers and
    /// `size.width` is ignored; only the height is honoured. The app's slots are
    /// measured by `SlotLayout` and want a fixed width, but the widget's are
    /// distributed by an HStack and must not be pinned.
    var fillsWidth = false
    /// Whether this mark runs across several days, which is what decides its
    /// *shape* — a capsule rather than a circle.
    ///
    /// It used to decide its height as well: a spanning socket was `pillHeight`
    /// of the slot where a single day's was all of it, so a spanning inner had
    /// to come off the pill rather than off the slot. `pillHeight` is 1 since
    /// #426 and both sockets are the slot, so the two branches below now differ
    /// only in which axes the inset is spelled out on — kept apart because the
    /// capsule's height is stated explicitly and the circle's comes from
    /// `.padding` alone.
    var spansDays = false
    /// The rest day's column, in this view's own coordinates, taken out of the
    /// shape. See `RestWindow`.
    var restWindow: ClosedRange<CGFloat>?

    var body: some View {
        // Subtracted from the *silhouette*, before `glowing` sees it — which is
        // the whole trap. The halo is generated from whatever shape is handed
        // in, so masking the rendered result instead would slice the glow flat
        // at the window's edges rather than letting it wrap the new open ends.
        // The halo reaches `slotHeight * GlowPalette.haloRadius`, far wider
        // than the gap being punched, so the difference is not subtle.
        sized(silhouette)
            .restWindowRemoved(restWindow)
            .glowing(
                halo: size.height * (shape == .ring
                    ? GlowPalette.ringHaloRadius
                    : GlowPalette.haloRadius),
                style: shape == .ring ? .ring : .plain
            )
            .accessibilityHidden(true)
    }

    /// The shape, as a view that serves as both mask and shadow caster.
    @ViewBuilder
    private var silhouette: some View {
        switch shape {
        case .capsule:
            Capsule(style: .continuous)
        case .ring:
            // The stroke carries an inner pair as well as the outer one: white
            // at full strength, offset up and down, which is what gives the ring
            // its thickness at top and bottom rather than a flat hairline.
            // **1pt, inside-aligned** (#332). The inner pair that used to
            // thicken it is gone with the fraction it was scaled by: a
            // constant-weight ring needs no help reading at the small end,
            // because it no longer gets thinner there.
            // Inset from the socket by `socketInset` on all four sides. Both
            // sockets are the slot now (#426), so both branches resolve to the
            // same 22pt inner in a 24pt recess. They are kept apart so the
            // spanning height stays *derived from* `pillHeight` rather than
            // falling out of the padding — which is what makes the height one
            // constant to move, in either direction.
            Group {
                if spansDays {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            GlowPalette.color, lineWidth: ringLineWidth ?? GlowShape.ringWeight
                        )
                        .frame(
                            height: size.height * GlowShape.pillHeight
                                - GlowShape.socketInset * 2
                        )
                        .padding(.horizontal, GlowShape.socketInset)
                } else {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            GlowPalette.color, lineWidth: ringLineWidth ?? GlowShape.ringWeight
                        )
                        .padding(GlowShape.socketInset)
                }
            }
        case .dot:
            // **The socket's inner shape, filled** (#332). It was a 3pt dot
            // floating in the slot; it is the slot inset by 1 on every side, so
            // a completion fills its day rather than marking a point in it.
            Circle().padding(GlowShape.socketInset)
        case .bar:
            // The same shape stretched: a lit pill's inner.
            //
            // **Inset on all four sides, not two.** The height came off the
            // socket and the width did not, so a spanning mark's inner was 2pt
            // shorter than its recess and exactly as wide — it ran to the
            // socket's ends where a ring or a dot stands 1pt clear of them.
            // `.ring` and `.dot` were already right, because a single
            // `.padding(socketInset)` does both axes at once and only the
            // pill's height had to be spelled out.
            Capsule(style: .continuous)
                .frame(height: size.height * GlowShape.pillHeight - GlowShape.socketInset * 2)
                .padding(.horizontal, GlowShape.socketInset)
        }
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
