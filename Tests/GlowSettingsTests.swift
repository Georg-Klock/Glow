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
        // Pinned to 6x, not to the default. The halo is drawn in SDR and stops
        // gaining anything long before the encode does, so when the default
        // moved to the top of the range this had to stay where it was — tying
        // it to the default would have shrunk every halo to a quarter.
        #expect(GlowSettings.haloScale(for: GlowSettings.haloReference) == 1)
        #expect(GlowSettings.haloScale(for: 12) > 1)
        #expect(GlowSettings.haloScale(for: GlowSettings.range.upperBound) <= 1.7)
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

@Suite("Widget tap burst")
struct WidgetBurstTests {
    @Test("The glow is held before the fill starts rising")
    func holdBeforeFade() {
        // Completion should read as an event, not as the light going out, so
        // coverage stays at zero through the hold.
        #expect(WidgetBurst.coverage(at: 0) == 0)
        #expect(WidgetBurst.coverage(at: WidgetBurst.hold - 0.01) == 0)
        #expect(WidgetBurst.coverage(at: WidgetBurst.hold + 0.01) > 0)
    }

    @Test("Coverage rises to fully covered and never past it")
    func coverageRange() {
        #expect(WidgetBurst.coverage(at: WidgetBurst.duration) == 1)
        #expect(WidgetBurst.coverage(at: WidgetBurst.duration * 5) == 1)
        for step in stride(from: 0.0, through: WidgetBurst.duration, by: 0.05) {
            let c = WidgetBurst.coverage(at: step)
            #expect(c >= 0 && c <= 1, "coverage \(c) out of range at \(step)")
        }
    }

    @Test("Coverage only ever increases")
    func monotonic() {
        var previous = -1.0
        for step in stride(from: 0.0, through: WidgetBurst.duration, by: 0.05) {
            let c = WidgetBurst.coverage(at: step)
            #expect(c >= previous, "coverage went backwards at \(step)")
            previous = c
        }
    }

    @Test("A stale tap does not replay")
    func burstExpires() {
        // Otherwise a midnight rollover, or an edit made in the app, would
        // re-animate somebody's last tap hours after they made it.
        let id = UUID()
        let started = Date()
        WidgetBurst.record(habitID: id, at: started)

        #expect(WidgetBurst.pending(now: started.addingTimeInterval(0.1))?.habitID == id)
        #expect(WidgetBurst.pending(now: started.addingTimeInterval(WidgetBurst.duration + 1)) == nil)
        #expect(WidgetBurst.pending(now: started.addingTimeInterval(3600)) == nil)
    }

    @Test("The burst fits inside one timeline, so it spends no extra reloads")
    func burstIsCheap() {
        // The whole point: a tap already costs a reload, and the animation
        // rides inside the timeline that reload produces.
        let frames = Int(WidgetBurst.duration / WidgetBurst.step)
        #expect(frames <= 15, "\(frames) frames is more timeline than a second of animation needs")
        #expect(WidgetBurst.duration <= 1.5)
    }
}
