import SwiftUI
import UIKit

/// Holds the one rendered tile.
///
/// The tile is uniform and shape-free, so unlike the earlier per-size, per-hue
/// cache there is exactly one image for the whole app. It is rendered on first
/// use and kept.
@MainActor
final class GlowImageCache {
    static let shared = GlowImageCache()

    private let renderer: GlowRenderer
    private var tile: UIImage?
    /// Set when rendering fails, so a broken build attempts it once rather than
    /// on every layout pass.
    private var didFail = false

    init(renderer: GlowRenderer = GlowRenderer()) {
        self.renderer = renderer
    }

    /// The lit tile, or nil if it could not be rendered. Callers fall back to a
    /// flat shape, which is also what a screen with no headroom shows, so there
    /// is no visually broken state either way.
    func litTile() -> UIImage? {
        if let tile { return tile }
        if didFail { return nil }

        do {
            let data = try renderer.imageData(color: GlowPalette.components)
            guard let image = UIImage(data: data) else {
                didFail = true
                return nil
            }
            tile = image
            return image
        } catch {
            didFail = true
            return nil
        }
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

    private var shape: Capsule { Capsule(style: .continuous) }
    private var haloRadius: CGFloat { size.height * GlowPalette.haloRadius }

    var body: some View {
        ZStack {
            // The shadow caster sits under the core and is never seen directly.
            // Three passes at increasing radius: one shadow falls off far too
            // fast to read as a bloom, and stacking them approximates the long
            // tail a real light source has.
            shape
                .fill(GlowPalette.color)
                .frame(width: size.width, height: size.height)
                .shadow(color: GlowPalette.color.opacity(0.55), radius: haloRadius * 0.35)
                .shadow(color: GlowPalette.color.opacity(0.35), radius: haloRadius * 0.8)
                .shadow(color: GlowPalette.color.opacity(0.22), radius: haloRadius * 1.6)

            core
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var core: some View {
        if let tile = GlowImageCache.shared.litTile() {
            Image(uiImage: tile)
                .resizable()
                // Without this the image is tone-mapped to SDR and the whole
                // exercise is a slightly bright capsule.
                .allowedDynamicRange(.high)
                .frame(width: size.width, height: size.height)
                // The tile is a plain square, so the slot's shape comes from
                // here rather than from anything baked into the image.
                .clipShape(shape)
        } else {
            shape
                .fill(GlowPalette.color)
                .frame(width: size.width, height: size.height)
        }
    }
}
