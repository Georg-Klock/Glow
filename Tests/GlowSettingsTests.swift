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
    @Test("The cross-fade runs 0 to 1, in order, inside its duration")
    func framesCoverTheFade() {
        // The frames are the animation: whatever their count, the first must
        // be the untouched ring, the last the settled dot, and every offset
        // inside the note's expiry so no frame outlives the burst.
        let frames = WidgetBurst.frames
        #expect(frames.first?.progress == 0)
        #expect(frames.last?.progress == 1)
        #expect(frames.map(\.offset) == frames.map(\.offset).sorted())
        #expect(frames.allSatisfy { $0.offset <= WidgetBurst.duration })
    }

    @Test("A handful of stills, not a sampled curve")
    func framesStayFew() {
        // This used to sample the app's closing spring at 40fps — seventeen
        // entries — and the playback stuttered: timeline entries do not
        // arrive at the rate they were sampled at. The cross-fade is a few
        // stills on purpose; a rising count here is the sampling creeping
        // back.
        #expect((2...4).contains(WidgetBurst.frames.count))
    }

    @Test("A stale tap does not replay")
    func burstExpires() {
        // Otherwise a midnight rollover, or an edit made in the app, would
        // re-animate somebody's last tap hours after they made it.
        //
        // **This used to expire against `duration` and now expires against
        // `maximumLag`** (#267). The two were one constant, so widening the
        // window a late reload can still ride widened this guard with it;
        // splitting them is what lets the fade stay 0.3s while the note
        // survives long enough to be read. The guard is unchanged in what it
        // protects — an hour later is still nothing — and `burstLagStaysShort`
        // below is what stops the new constant drifting until it stops
        // mattering.
        let id = UUID()
        let started = Date()
        WidgetBurst.record(habitID: id, at: started, reduceMotion: false)

        #expect(WidgetBurst.pending(now: started.addingTimeInterval(0.1))?.habitID == id)
        // Past the fade and still valid: this is the whole point of the split.
        #expect(WidgetBurst.pending(
            now: started.addingTimeInterval(WidgetBurst.duration + 0.1)
        )?.habitID == id)
        #expect(WidgetBurst.pending(
            now: started.addingTimeInterval(WidgetBurst.maximumLag + 0.1)
        ) == nil)
        #expect(WidgetBurst.pending(now: started.addingTimeInterval(3600)) == nil)
    }

    @Test("The note outlives the fade, and stops short of the next reload wave")
    func burstLagStaysShort() {
        // Both bounds are measured, and the upper one is the point (#267).
        //
        // Below: the note must outlive the fade, or reload latency is
        // subtracted from the animation — the slowest *prompt* reload measured
        // on a device was 427ms.
        //
        // Above: under a flurry the week widget's provider runs again in
        // waves, and the tightest gap measured between waves was 798ms. A note
        // still valid then animates one tap twice. So this constant cannot
        // simply be widened until it stops mattering, and 0.75 is the fence
        // that says so.
        #expect(WidgetBurst.maximumLag > WidgetBurst.duration)
        #expect(WidgetBurst.maximumLag >= 0.45, "under the 427ms fast path")
        #expect(WidgetBurst.maximumLag <= 0.75, "into the 798ms gap between reload waves")
    }

    @Test("However late the provider runs, the whole fade plays")
    func fadeStartsWhenTheProviderRuns() {
        // The frames used to be offset from the tap and the spent ones
        // dropped, so a provider called part-way through the window played
        // part of the fade and one called after it played none (#267). Dated
        // from the render instead, the same frames come out whenever it runs —
        // latency delays the animation rather than being subtracted from it.
        let now = Date()
        let late = now.addingTimeInterval(WidgetBurst.maximumLag - 0.01)

        for moment in [now, late] {
            let steps = WidgetBurst.timeline(renderedAt: moment)
            // Every fade frame, and the settle.
            #expect(steps.count == WidgetBurst.frames.count + 1)
            #expect(steps.first?.progress == 0)
            #expect(steps.first?.date == moment)
            #expect(steps.last?.progress == nil)
            #expect(steps.map(\.date) == steps.map(\.date).sorted())
            // Nothing is scheduled before the moment it was asked for: a
            // timeline entry dated in the past is one WidgetKit has already
            // missed.
            #expect(steps.allSatisfy { $0.date >= moment })
            // And nothing outlives the fade's own length.
            #expect(steps.allSatisfy {
                $0.date <= moment.addingTimeInterval(WidgetBurst.duration)
            })
        }
    }

    @Test("An undo drops its own habit's note, and only its own")
    func undoClearsTheNote() {
        // A note outliving its fade is what makes this necessary (#267):
        // complete, undo before the provider has run, and without this the
        // widget would cross-fade a ring into a dot for a slot the store has
        // just reopened.
        let completed = UUID()
        let other = UUID()

        WidgetBurst.record(habitID: completed, at: Date(), reduceMotion: false)
        WidgetBurst.clear(habitID: other)
        #expect(WidgetBurst.pending()?.habitID == completed, "another habit's undo took this note")

        WidgetBurst.clear(habitID: completed)
        #expect(WidgetBurst.pending() == nil)
    }

    @Test("Reduce Motion travels with the note, so the provider never reads UIKit")
    func burstCarriesReduceMotion() {
        // `UIAccessibility.isReduceMotionEnabled` is main-actor isolated and a
        // `TimelineProvider` is not. The intent that records the note is, so
        // the value is read there and carried — see `WidgetBurst.record`.
        let id = UUID()
        WidgetBurst.record(habitID: id, at: Date(), reduceMotion: true)
        #expect(WidgetBurst.reduceMotion)

        WidgetBurst.record(habitID: id, at: Date(), reduceMotion: false)
        #expect(!WidgetBurst.reduceMotion)
    }

    @Test("The burst fits inside one timeline, so it spends no extra reloads")
    func burstIsCheap() {
        // The whole point: a tap already costs a reload, and the animation rides
        // inside the timeline that reload produces. Entries are free; it is
        // *reloads* that are budgeted, and this spends none. What has to stay
        // small is the duration — a long burst would still be animating when
        // the next tap arrives.
        #expect(WidgetBurst.duration <= 0.75)
    }
}

/// The glow's default, and the one document that publishes it.
///
/// `docs/glow.md` said 6x for long enough that a device found running at 1.5
/// was measured against the wrong number twice in one session. The default is
/// the product's loudest single decision; a document that disagrees with it is
/// not a cosmetic error.
@Suite("Glow default")
struct GlowDefaultTests {
    // `defaultIsTheTop` lived here from #294 until the default moved to 2 on
    // an 8x ceiling. It held the rule "the glow is the product; there is no
    // reason for it to open at half strength", and that rule is what was
    // reversed — the default now opens quiet on purpose — so the test was
    // retired rather than rewritten to assert the new number: the number is
    // an iteration target, not a rule, and `theDocAgrees` below is what keeps
    // the one published copy of it honest. See docs/decisions.md.

    @Test("docs/glow.md publishes the number the code holds")
    func theDocAgrees() throws {
        // The same shape as `WidgetTraceRedactionTests`' source scan: a claim
        // about a file this repository owns, checked against the file.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let doc = try String(
            contentsOf: root.appending(path: "docs/glow.md"), encoding: .utf8
        )
        let value = GlowSettings.defaultValue
        let whole = String(Int(value))
        #expect(doc.contains("| `peakHeadroom` | \(value)"),
                "docs/glow.md's tuning table does not publish \(value)")
        #expect(doc.contains("default is **\(whole)x**"),
                "docs/glow.md does not say the default is \(whole)x")
    }
}
