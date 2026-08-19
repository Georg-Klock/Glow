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

/// A lit slot: the HDR core, and the halo around it.
///
/// The halo is an ordinary SwiftUI shadow rather than part of the image. Two
/// reasons. The image is opaque, because the PQ encoder drops alpha, so a halo
/// baked into it would arrive as a black square covering its neighbours. And a
/// shadow composites against whatever is behind it, which an opaque tile
/// cannot. The core is what has to be HDR; a halo is dimmer than its source by
/// definition, so nothing is lost by drawing it in SDR.
struct GlowImageView: View {
    let size: CGSize
    /// When true the tile takes whatever width the layout offers and
    /// `size.width` is ignored; only the height is honoured. The app's slots
    /// are measured by `SlotLayout` and want a fixed width, but the widget's
    /// are distributed by an HStack and must not be pinned.
    var fillsWidth = false
    /// When set, the caller drives the breath instead of the view animating
    /// itself. A widget cannot run a continuous animation — it renders a
    /// snapshot per timeline entry — so the widget supplies a phase per entry
    /// and gets its breathing that way.
    var phase: Double?

    @AppStorage(GlowSettings.key, store: GlowSettings.store)
    private var peak: Double = GlowSettings.defaultValue

    /// Pulsing content is exactly what Reduce Motion exists to switch off.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    /// The lit slot breathes: opacity easing between these, forever, on the
    /// glowing layer only. Slow and shallow on purpose — the point is to catch
    /// the eye in peripheral vision, not to blink at someone.
    static let breathLow = 0.85
    /// Half a breath: in and out is twice this.
    private static let breathPeriod: Double = 1.2

    private var shape: Capsule { Capsule(style: .continuous) }
    private var haloRadius: CGFloat {
        size.height * GlowPalette.haloRadius * CGFloat(GlowSettings.haloScale(for: peak))
    }

    var body: some View {
        ZStack {
            // The shadow caster sits under the core and is never seen directly.
            // Three passes at increasing radius: one shadow falls off far too
            // fast to read as a bloom, and stacking them approximates the long
            // tail a real light source has.
            sized(shape.fill(GlowPalette.color))
                .shadow(color: GlowPalette.color.opacity(0.55), radius: haloRadius * 0.35)
                .shadow(color: GlowPalette.color.opacity(0.35), radius: haloRadius * 0.8)
                .shadow(color: GlowPalette.color.opacity(0.22), radius: haloRadius * 1.6)

            core
        }
        // The whole glowing layer breathes together, so the halo and the core
        // never drift out of step.
        .opacity(phase ?? (isBreathing ? 1.0 : Self.breathLow))
        .animation(
            (reduceMotion || phase != nil)
                ? nil
                : .easeInOut(duration: Self.breathPeriod).repeatForever(autoreverses: true),
            value: isBreathing
        )
        .onAppear { if !reduceMotion && phase == nil { isBreathing = true } }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var core: some View {
        if let tile = GlowImageCache.shared.litTile(peak: peak) {
            sized(
                Image(uiImage: tile)
                    .resizable()
                    // Without this the image is tone-mapped to SDR and the
                    // whole exercise is a slightly bright capsule.
                    .allowedDynamicRange(.high)
            )
            // The tile is a plain square, so the slot's shape comes from here
            // rather than from anything baked into the image.
            .clipShape(shape)
        } else {
            sized(shape.fill(GlowPalette.color))
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
