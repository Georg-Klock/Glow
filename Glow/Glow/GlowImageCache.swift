import SwiftUI
import UIKit

/// Caches rendered glows so a scroll does not re-encode a JPEG per frame.
///
/// Keyed on pixel size and colour, which is everything the render depends on.
@MainActor
final class GlowImageCache {
    static let shared = GlowImageCache()

    private let renderer: GlowRenderer
    private var cache: [Key: UIImage] = [:]
    /// Sizes that failed to render, so a broken combination is attempted once
    /// rather than on every layout pass.
    private var failures: Set<Key> = []

    private struct Key: Hashable {
        let width: Int
        let height: Int
        let accent: HabitAccent
    }

    init(renderer: GlowRenderer = GlowRenderer()) {
        self.renderer = renderer
    }

    /// The glow for one slot, or nil if it could not be rendered. Callers fall
    /// back to a flat SDR shape, which is also what a non-EDR screen shows, so
    /// there is no visually broken state either way.
    func image(size: CGSize, accent: HabitAccent, scale: CGFloat) -> UIImage? {
        let pixelSize = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
        let key = Key(width: Int(pixelSize.width), height: Int(pixelSize.height), accent: accent)

        if let cached = cache[key] { return cached }
        if failures.contains(key) { return nil }

        do {
            let data = try renderer.imageData(pixelSize: pixelSize, color: accent.components)
            guard let image = UIImage(data: data, scale: scale) else {
                failures.insert(key)
                return nil
            }
            cache[key] = image
            return image
        } catch {
            failures.insert(key)
            return nil
        }
    }

    func removeAll() {
        cache.removeAll()
        failures.removeAll()
    }
}

/// The HDR layer of a slot.
struct GlowImageView: View {
    let size: CGSize
    let accent: HabitAccent

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = GlowImageCache.shared.image(size: size, accent: accent, scale: displayScale) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                // Without this the image is tone-mapped to SDR and the whole
                // exercise is a slightly bright capsule.
                .allowedDynamicRange(.high)
                .frame(width: size.width, height: size.height)
                .accessibilityHidden(true)
        } else {
            Capsule()
                .fill(accent.color)
                .frame(width: size.width, height: size.height)
                .accessibilityHidden(true)
        }
    }
}
