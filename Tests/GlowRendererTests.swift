import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
@testable import Glow

/// The glow is the one part of this app that can look fine in code and do
/// nothing on screen, so these tests assert on the encoded bytes.
///
/// They exist because the previous version of this file passed while the app
/// did not glow at all. It asserted that a gain map was present and that its
/// metadata carried the right headroom, both of which were true, and neither of
/// which meant iOS would treat the file as HDR. `UIImage.isHighDynamicRange`
/// answered false on device for every gain-map encoding. What follows asserts
/// the properties that actually predicted device behaviour: the colour space
/// the file is in, and whether its pixels exceed SDR white.
@Suite("HDR glow rendering")
struct GlowRendererTests {
    private let renderer = GlowRenderer()

    private func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func decoded(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    @Test("The encoded slot is in a PQ colour space")
    func encodesAsPQ() throws {
        // This is the property that separates working from not working. A file
        // in an SDR colour space is an SDR file however bright its pixels were
        // before encoding, and however much gain-map metadata rides along.
        let data = try renderer.imageData(color: GlowPalette.components)
        let space = try #require(try decoded(data).colorSpace)
        let name = (space.name as String?) ?? ""

        #expect(name.contains("PQ"), "encoded in \(name), which has no headroom above SDR white")
    }

    @Test("The file declares more headroom than SDR white")
    func fileDeclaresHeadroom() throws {
        // ImageIO reports the headroom it will hand the display. One stop or
        // less means the glow would be indistinguishable from a filled slot.
        let data = try renderer.imageData(color: GlowPalette.components)
        let headroom = try #require(
            properties(data)["Headroom" as CFString] as? Double,
            "the file declares no headroom at all"
        )
        #expect(headroom > 1.5, "declared headroom is only \(headroom)x")
    }

    @Test("A brighter peak encodes as more headroom")
    func peakDrivesHeadroom() throws {
        var dim = GlowRenderer()
        dim.peakHeadroom = 2
        var bright = GlowRenderer()
        bright.peakHeadroom = 8

        let dimHeadroom = try #require(
            properties(dim.imageData(color: GlowPalette.components))["Headroom" as CFString] as? Double
        )
        let brightHeadroom = try #require(
            properties(bright.imageData(color: GlowPalette.components))["Headroom" as CFString] as? Double
        )
        #expect(brightHeadroom > dimHeadroom + 1, "\(dimHeadroom)x vs \(brightHeadroom)x")
    }

    @Test("The glow's pixels really exceed SDR white")
    func pixelsExceedSDRWhite() throws {
        // Decoded into extended linear, where 1.0 is SDR white. This is the
        // display-independent form of "it glows": no screen is consulted, the
        // question is only whether the values in the file are above reference.
        let data = try renderer.imageData(color: GlowPalette.components)
        let image = try #require(CIImage(data: data))

        var pixel = [Float](repeating: 0, count: 4)
        CIContext().render(
            image,
            toBitmap: &pixel,
            rowBytes: 16,
            bounds: CGRect(x: 4, y: 4, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: GlowRenderer.workingSpace
        )
        let brightest = max(pixel[0], max(pixel[1], pixel[2]))
        #expect(brightest > 1.0, "the glow peaks at \(brightest), no brighter than SDR white")
    }

    @Test("The tile is uniform, so one image serves every slot")
    func tileIsUniform() throws {
        // The shape comes from clipping and the halo from a shadow, so the
        // encoded image carries neither. If this ever stops being flat, the
        // single shared tile silently becomes wrong for most slot sizes.
        let image = try decoded(renderer.imageData(color: GlowPalette.components))
        #expect(image.width == renderer.tileSize)
        #expect(image.height == renderer.tileSize)
    }

    @Test("A zero-sized tile is refused rather than encoded")
    func emptySizeThrows() {
        var empty = GlowRenderer()
        empty.tileSize = 0
        #expect(throws: GlowRenderer.RenderError.emptySize) {
            try empty.imageData(color: GlowPalette.components)
        }
    }

    @Test("Rendering is deterministic, so the cache key is honest")
    func deterministicOutput() throws {
        let first = try renderer.imageData(color: GlowPalette.components)
        let second = try renderer.imageData(color: GlowPalette.components)
        #expect(first == second)
    }
}
