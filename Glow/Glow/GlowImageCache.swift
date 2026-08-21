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

    /// Stroke width of `.ring`. 3pt on a 35pt slot in the design file.
    static let ringWeight: CGFloat = 3.0 / 35.0
    /// Diameter of `.dot`, in points.
    ///
    /// Fixed rather than a fraction of the slot: a day is a day, and the mark
    /// for one should not grow because the grid it sits in got wider. The slot
    /// still sets the pitch and the ring; only the marks inside it are absolute.
    static let dotDiameter: CGFloat = 3
    /// Thickness of `.bar`, in points. A run of days is a line, not a lozenge.
    static let barThickness: CGFloat = 2

    /// The missed ✕: 1pt bars with 9pt arms, crossed. Not a glyph — see
    /// SlotMarkView.
    static let missedThickness: CGFloat = 1.0 / 17.5
    static let missedArm: CGFloat = 9.0 / 17.5

    /// The upcoming day, and an upcoming run of them. The same shapes as a
    /// completion, so the only difference between a day that happened and a day
    /// that has not is whether it is lit.
    static let upcomingDiameter: CGFloat = 3
    static let upcomingThickness: CGFloat = 2
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

    private var haloRadius: CGFloat {
        halo * CGFloat(GlowSettings.haloScale(for: peak))
    }

    @ViewBuilder
    private func caster(_ content: some View) -> some View {
        let base = content.foregroundStyle(GlowPalette.color)
        switch style {
        case .plain:
            base.shadow(color: GlowPalette.color, radius: haloRadius)
        case .ring:
            // Two passes offset up and down rather than one centred: it is what
            // the file specifies, and it reads as a tube of light rather than a
            // disc behind a hole. The offset is its own number, not a fraction
            // of the radius: the file pairs a radius of 5 with an offset of
            // 1.25, so the offset is a quarter of the reach.
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
            let inner = size.height * GlowPalette.ringInnerRadius
            let innerOffset = size.height * GlowPalette.ringHaloOffset
            Capsule(style: .continuous)
                .strokeBorder(
                    GlowPalette.color
                        .shadow(.inner(color: GlowPalette.color, radius: inner, y: innerOffset))
                        .shadow(.inner(color: GlowPalette.color, radius: inner, y: -innerOffset)),
                    lineWidth: ringLineWidth ?? (size.height * GlowShape.ringWeight)
                )
        case .dot:
            // Centred rather than inset, so a dot sits on the column's centre
            // line whatever the slot around it is doing.
            Circle().frame(width: GlowShape.dotDiameter, height: GlowShape.dotDiameter)
        case .bar:
            // Inset to the dot's own margin at each end, so a bar starts where
            // the first day's dot would start and ends where the last one's
            // would — a run of completions, not a shape covering the columns.
            Capsule(style: .continuous)
                .frame(height: GlowShape.barThickness)
                .padding(.horizontal, (size.height - GlowShape.dotDiameter) / 2)
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
