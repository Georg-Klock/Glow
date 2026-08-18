import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
@testable import Glow

/// The glow is the one part of this app that could look fine in code and do
/// nothing on screen. These tests assert the encoded bytes really carry a gain
/// map, which is the difference between an HDR glow and a bright teal capsule.
///
/// What they cannot assert is how bright it looks: that depends on ambient
/// light, display brightness, thermal state and Low Power Mode, and only a real
/// EDR screen can answer it. See docs/glow.md.
@Suite("HDR glow rendering")
struct GlowRendererTests {
    private let renderer = GlowRenderer()

    private func gainMapInfo(_ data: Data) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let iso = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source, 0, kCGImageAuxiliaryDataTypeISOGainMap
        ) as? [CFString: Any]
        let legacy = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source, 0, kCGImageAuxiliaryDataTypeHDRGainMap
        ) as? [CFString: Any]
        return iso ?? legacy
    }

    @Test("A rendered slot carries a gain map")
    func gainMapIsPresent() throws {
        let data = try renderer.imageData(
            pixelSize: CGSize(width: 96, height: 96),
            color: HabitAccent.teal.components
        )
        #expect(gainMapInfo(data) != nil, "no gain map: the glow would render as flat SDR colour")
    }

    @Test("Every accent renders with a gain map", arguments: HabitAccent.allCases)
    func everyAccentRenders(accent: HabitAccent) throws {
        let data = try renderer.imageData(
            pixelSize: CGSize(width: 72, height: 72),
            color: accent.components
        )
        #expect(gainMapInfo(data) != nil)
    }

    /// The gain map's own metadata, flattened to a dictionary of tag paths.
    ///
    /// This is what the OS reads to decide how far above SDR white to push the
    /// image, so it is the honest thing to assert on. The two obvious
    /// alternatives both ask the *display* rather than the file:
    /// `CIImage(data:options: [.expandToHDR: true]).contentHeadroom` and
    /// `applyingGainMap(_:headroom:)` each collapse to SDR on a simulator, so a
    /// test built on either would fail on CI and pass on a phone, which is
    /// worse than no test.
    private func gainMapMetadata(_ data: Data) throws -> [String: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        // Which auxiliary entry carries the metadata differs by platform: on
        // macOS it hangs off the ISO gain map, on iOS off the legacy one. Read
        // whichever has it rather than assuming.
        let candidates = [kCGImageAuxiliaryDataTypeISOGainMap, kCGImageAuxiliaryDataTypeHDRGainMap]
        let metadataValue = candidates.lazy.compactMap { type -> Any? in
            let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) as? [CFString: Any]
            return info?[kCGImageAuxiliaryDataInfoMetadata]
        }.first
        let metadata = try #require(metadataValue, "gain map carries no metadata") as! CGImageMetadata

        var tags: [String: Any] = [:]
        CGImageMetadataEnumerateTagsUsingBlock(
            metadata,
            nil,
            [kCGImageMetadataEnumerateRecursively: true] as CFDictionary
        ) { path, tag in
            tags[path as String] = CGImageMetadataTagCopyValue(tag)
            return true
        }
        return tags
    }

    /// `AlternateHeadroom` is stored in stops, so a 6x glow reads as log2(6).
    private func alternateHeadroomStops(_ data: Data) throws -> Double {
        let tags = try gainMapMetadata(data)
        let value = try #require(
            tags["HDRToneMap:AlternateHeadroom"],
            "gain map carries no headroom metadata"
        )
        return try #require(Double(String(describing: value)))
    }

    @Test("The encoded glow really reaches the requested headroom")
    func headroomRoundTrips() throws {
        // Core Image infers headroom from the brightest pixel, so an accent
        // whose brightest channel is 0.85 would otherwise encode 0.85x the
        // requested peak. GlowRenderer pre-scales to compensate, and this is
        // what proves the compensation is right rather than plausible.
        for peak in [2.0, 4.0, 6.0] as [CGFloat] {
            var renderer = GlowRenderer()
            renderer.peakHeadroom = peak
            let data = try renderer.imageData(
                pixelSize: CGSize(width: 64, height: 64),
                color: HabitAccent.teal.components
            )
            let stops = try alternateHeadroomStops(data)
            let measured = pow(2.0, stops)
            #expect(
                abs(measured - Double(peak)) < 0.15,
                "requested \(peak)x, encoded \(measured)x (\(stops) stops)"
            )
        }
    }

    @Test("The glow is brighter than SDR white, which is the entire point")
    func glowExceedsSDRWhite() throws {
        // If this ever reaches zero stops, the app is drawing a bright capsule
        // and the HDR pipeline has silently fallen back to plain colour.
        let data = try renderer.imageData(
            pixelSize: CGSize(width: 64, height: 64),
            color: HabitAccent.teal.components
        )
        let stops = try alternateHeadroomStops(data)
        #expect(stops > 1.0, "the glow only reaches \(stops) stops above SDR white")
    }

    @Test("Pill and circle aspect ratios both render")
    func pillAndCircle() throws {
        let sizes = [
            CGSize(width: 96, height: 96),    // daily circle
            CGSize(width: 300, height: 96),   // 2x per week pill
            CGSize(width: 130, height: 96)    // 5x per week pill
        ]
        for size in sizes {
            let data = try renderer.imageData(pixelSize: size, color: HabitAccent.rose.components)
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == Int(size.width))
            #expect(image.height == Int(size.height))
            #expect(gainMapInfo(data) != nil)
        }
    }

    /// The centre pixel as a screen with no EDR headroom would show it.
    private func sdrCentrePixel(_ data: Data, size: Int) throws -> [UInt8] {
        let image = try #require(CIImage(data: data))
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            image,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: size / 2, y: size / 2, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return pixel
    }

    @Test("On a screen with no headroom the slot is a dim version of the accent")
    func sdrFallbackIsADimAccent() throws {
        let data = try renderer.imageData(
            pixelSize: CGSize(width: 64, height: 64),
            color: HabitAccent.rose.components
        )
        let pixel = try sdrCentrePixel(data, size: 64)

        // Rose is (1.00, 0.40, 0.56): red-dominant, clearly visible, and
        // clearly not a solid completed slot.
        #expect(pixel[0] > 60, "centre pixel is too dark to see")
        #expect(pixel[0] > pixel[1], "centre pixel does not look like the accent colour")
    }

    @Test("An open slot never renders as bright as a completed one without EDR")
    func sdrFallbackIsDimmerThanFilled() throws {
        // This is the whole reason the base is dimmed: on a non-EDR screen the
        // open and filled states have to stay tellable apart, and the glow
        // cannot do that job because there is no headroom to do it with.
        var undimmed = GlowRenderer()
        undimmed.sdrDimming = 1.0

        let dim = try sdrCentrePixel(
            renderer.imageData(pixelSize: CGSize(width: 64, height: 64), color: HabitAccent.teal.components),
            size: 64
        )
        let solid = try sdrCentrePixel(
            undimmed.imageData(pixelSize: CGSize(width: 64, height: 64), color: HabitAccent.teal.components),
            size: 64
        )
        #expect(dim[1] < solid[1] - 20, "dim \(dim[1]) is not visibly darker than solid \(solid[1])")
    }

    @Test("A zero-sized slot is refused rather than encoded")
    func emptySizeThrows() {
        #expect(throws: GlowRenderer.RenderError.emptySize) {
            try renderer.imageData(pixelSize: .zero, color: HabitAccent.teal.components)
        }
    }

    @Test("Rendering is deterministic, so the cache key is honest")
    func deterministicOutput() throws {
        let size = CGSize(width: 80, height: 80)
        let first = try renderer.imageData(pixelSize: size, color: HabitAccent.sky.components)
        let second = try renderer.imageData(pixelSize: size, color: HabitAccent.sky.components)
        #expect(first == second)
    }
}
