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
    /// The inner shape is the socket inset by this on all four sides with its
    /// radius reduced by the same, and it is what carries the state: filled for
    /// a completion, stroked for an open slot, absent for an upcoming pill.
    ///
    /// The socket itself is a 15% black fill under its bevel since #427; §8.3's
    /// "no fill at all" is superseded and `SlotMarkView.socket(_:circle:)`
    /// carries the reasoning.
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

    /// The missed ✕, as fractions of the slot, measured off the cross path in
    /// node `260:2819` (#427).
    ///
    /// **`missedSpan` is the ✕'s bounding box, not a bar length** — the number
    /// the design file can be measured for directly. Flattening that node's
    /// path to 100 samples per curve gives `22.0007 × 22.0006` centred dead in
    /// the 24pt slot, which is `11/12`: **the same 22pt inner every other mark
    /// takes** since #426, so the ✕ is not an exception to that rule but an
    /// instance of it. It replaces a `missedLength` of `7/8` that described the
    /// bar *before* it was crossed, and which the two `CrossShape` bars turned
    /// into a span of 0.77 rather than the 0.795 its comment claimed — a
    /// quantity nothing in the file could be held against.
    ///
    /// `missedThickness` is `6.7592` in the file: the straight end-cap
    /// (`5.0692`, between the two corner arcs at a tip) plus both corner radii.
    /// `9/32` fits that to 0.009pt and is taken as the intent.
    static let missedSpan: CGFloat = 11.0 / 12.0
    static let missedThickness: CGFloat = 9.0 / 32.0

    /// **The corner radius and the bevel offset are one number, used twice.**
    /// The file's corner radius computes to `0.8450` and its inner-shadow
    /// offset and blur are `0.844815`, which is a coincidence only if you
    /// expect two independent values to agree to four figures. Held as one
    /// constant so they cannot drift apart; `0.0352` of the slot is `0.8448` at
    /// 24 and was `1/32` — `0.75` — before #427.
    ///
    /// The ✕ is **pressed in like a socket, not painted like a glyph**: no
    /// stroke, no grey, a 15% black fill and three inner shadows.
    static let missedCorner: CGFloat = 0.0352

    /// The ✕'s deep well — black at 48%, `dy 4` and `blur 3` at a 24pt slot
    /// (#427). The open socket's well *left* in the same pass; this one
    /// arrived, and at nearly twice the strength. That asymmetry is what the
    /// file draws and is deliberate: see `docs/decisions.md` before unifying
    /// the two back into one number.
    static let missedWellOffset: CGFloat = 1.0 / 6.0
    static let missedWellBlur: CGFloat = 1.0 / 8.0

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
                // lit white are the same pixels. #53.
                .widgetAccentedRenderingMode(.fullColor)
        } else {
            GlowPalette.color
        }
    }
}

/// Renders anything as a real glow: the HDR tile masked to its shape.
///
/// Applies to *any* view, not just the slot shapes, because the rule it serves
/// is a rule about the design file rather than about geometry: full white means
/// headroom. That covers the marks, and it also covers the label of a habit
/// still due and today's letter in the header, both of which are drawn exactly
/// that way and were rendering as merely bright text.
///
/// **Nothing spreads.** A lit mark used to cast an SDR drop shadow underneath
/// the tile — the halo — sized from `GlowPalette`'s reach constants and scaled
/// by the intensity setting. It is gone (#394): a mark is lit exactly as far as
/// its own silhouette reaches and no further. The HDR tile is untouched by that
/// removal, which is the whole point — the emitting layer is the image, the
/// halo was only the light it threw on the ground, and SPEC §1's rule is about
/// the mark being lit.
///
/// One consequence worth keeping: on a Tinted or Clear home screen the widget
/// renders in accented mode, which cannot show the tile's headroom (#53). That
/// used to leave the halo as the only light there. Now those appearances draw
/// the marks as flat white shapes, which is what the halo-off build already
/// looked like.
struct GlowModifier: ViewModifier {
    @AppStorage(GlowSettings.key, store: GlowSettings.store)
    private var peak: Double = GlowSettings.defaultValue

    func body(content: Content) -> some View {
        // An overlay rather than a ZStack, and that is load-bearing: the tile is
        // a `resizable()` image, so inside a ZStack it expands to whatever space
        // is going and drags the layout with it. Text glowed that way stops
        // hugging its leading edge and drifts to the middle of whatever it is
        // in. An overlay takes the base view's size and cannot do that.
        //
        // Nothing here animates on its own. A lit mark is lit and holds still:
        // the glow's one signal is brightness, and the breath that used to
        // pulse this layer said the same thing a second time, in a register
        // nothing else in the app uses. Removed 2026-08-21; docs/glow.md keeps
        // the history, including the measurement that the compositor does not
        // flatten an animated HDR layer.
        //
        // `geometryGroup()` is a guard now, not a fix. The content was measured
        // twice while the caster existed — once for the caster, once for the
        // mask — and while a repeating animation lived here, the second
        // measurement became something to interpolate: the breath walked
        // Today's rings ~15pt sideways (#45). With the breath gone and the
        // caster gone nothing animates this geometry, but the pin stays for the
        // next caller who animates anything here — and it belongs exactly at
        // this line. Written above `.opacity`, where it reads just as sensibly,
        // it was built and measured *still drifting*: by that point both
        // measurements have already happened.
        let settled = content.geometryGroup()
        return settled
            .foregroundStyle(GlowPalette.color)
            .overlay { GlowTile(peak: peak).mask { settled } }
    }
}

extension View {
    /// Draw this view as a real glow rather than as bright colour.
    func glowing() -> some View {
        modifier(GlowModifier())
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
        // Subtracted from the *silhouette*, before `glowing` sees it, so the
        // tile's mask is the shortened shape rather than the full one. It
        // mattered more while the halo existed — a halo generated from the full
        // silhouette and then masked would have been sliced flat at the
        // window's edges instead of wrapping the new open ends — but the order
        // is still the correct one, and reversing it would mask a rendered
        // result rather than the shape that produced it.
        sized(silhouette)
            .restWindowRemoved(restWindow)
            .glowing()
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
