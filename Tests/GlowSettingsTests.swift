import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Glow

@Suite("Glow intensity setting")
struct GlowSettingsTests {
    @Test("Out-of-range values clamp instead of being encoded")
    func clamping() {
        // A headroom of 400 is not a brighter glow, it is an encode no display
        // can tone-map sensibly. Values can arrive from a future build, a
        // synced default or a hand-edited plist, so the floor and ceiling are
        // enforced on read rather than trusted at the slider.
        #expect(GlowSettings.clamp(-5) == GlowSettings.range.lowerBound)
        #expect(GlowSettings.clamp(0) == GlowSettings.range.lowerBound)
        #expect(GlowSettings.clamp(400) == GlowSettings.range.upperBound)
        #expect(GlowSettings.clamp(6) == 6)
    }

    @Test("The default sits inside the range")
    func defaultIsValid() {
        #expect(GlowSettings.range.contains(GlowSettings.defaultValue))
    }

    @Test("The halo vanishes at the bottom of the range and grows with intensity")
    func haloScaling() {
        // Without this the slider would do nothing visible on a screen with no
        // headroom, and nothing at all in a screenshot.
        #expect(GlowSettings.haloScale(for: GlowSettings.range.lowerBound) == 0)
        #expect(GlowSettings.haloScale(for: GlowSettings.defaultValue) == 1)
        #expect(GlowSettings.haloScale(for: 12) > 1)
        #expect(GlowSettings.haloScale(for: 12) <= 1.7)
    }

    @Test("Intensity drives the encoded headroom", arguments: [2.0, 4.0, 8.0])
    func intensityReachesTheEncoder(peak: Double) throws {
        // The setting is only meaningful if it survives all the way into the
        // file the display reads.
        var renderer = GlowRenderer()
        renderer.peakHeadroom = CGFloat(peak)
        let data = try renderer.imageData(color: GlowPalette.components)

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let headroom = try #require(props["Headroom" as CFString] as? Double)

        #expect(abs(headroom - peak) < 0.2, "asked for \(peak)x, encoded \(headroom)x")
    }

    @Test("At the bottom of the range the glow stops exceeding SDR white")
    func offMeansOff() throws {
        var renderer = GlowRenderer()
        renderer.peakHeadroom = CGFloat(GlowSettings.range.lowerBound)
        let data = try renderer.imageData(color: GlowPalette.components)

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let headroom = (props["Headroom" as CFString] as? Double) ?? 1.0

        #expect(headroom <= 1.05, "\"off\" still encodes \(headroom)x of headroom")
    }
}
