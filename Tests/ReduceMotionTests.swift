import Foundation
import Testing
@testable import Glow

/// #137: Reduce Motion was honoured on one animated surface out of four.
///
/// SPEC §3 says "Reduce Motion snaps" in the `DayRing` section, and it was true
/// there and in the widget's burst, which records the setting at the tap
/// (`WidgetBurst`, #107). The week grid — the screen the app *is* — read the
/// setting nowhere: a completion closed on a spring, the row's label dimmed on
/// the same spring, and a press grew 32% and sprang back, whatever the person
/// had asked for.
@Suite("Reduce Motion")
struct MotionPolicyTests {
    @Test("A completion closes only when it was just made")
    func completionAnimatesOnce() {
        // The rule that was already there: un-completing is a correction, and
        // animating a correction dresses a mistake up as an achievement.
        #expect(MotionPolicy.closesCompletion(from: .open, to: .filled, reduceMotion: false))
        #expect(!MotionPolicy.closesCompletion(from: .filled, to: .open, reduceMotion: false))
        #expect(!MotionPolicy.closesCompletion(from: .missed, to: .filled, reduceMotion: false))
        #expect(!MotionPolicy.closesCompletion(from: .inactive, to: .filled, reduceMotion: false))
        #expect(!MotionPolicy.closesCompletion(from: .open, to: .rest, reduceMotion: false))
    }

    @Test("Reduce Motion snaps every completion, on every surface")
    func nothingClosesWhenReduced() {
        for from in [SlotState.open, .filled, .missed, .inactive, .rest] {
            for to in [SlotState.open, .filled, .missed, .inactive, .rest] {
                #expect(!MotionPolicy.closesCompletion(from: from, to: to, reduceMotion: true))
            }
        }
    }

    @Test("The ring sweeps one repetition, and only by hand")
    func ringSweepsOnce() {
        #expect(MotionPolicy.sweepsRing(from: 0, to: 1, reduceMotion: false))
        #expect(MotionPolicy.sweepsRing(from: 4, to: 5, reduceMotion: false))
        // A reset, an edit, a day rolling over, a tap arriving from the widget:
        // none of those is a gesture anybody made on this ring.
        #expect(!MotionPolicy.sweepsRing(from: 3, to: 0, reduceMotion: false))
        #expect(!MotionPolicy.sweepsRing(from: 1, to: 3, reduceMotion: false))
        #expect(!MotionPolicy.sweepsRing(from: 1, to: 1, reduceMotion: false))
        #expect(!MotionPolicy.sweepsRing(from: 0, to: 1, reduceMotion: true))
    }

    // `@MainActor` because `SlotView.pressScale` is: `View` carries the
    // isolation, and reading it from a nonisolated test is a warning today and
    // an error under a future language mode.
    @Test("A press does not grow when growth was declined")
    @MainActor
    func pressDoesNotGrow() {
        #expect(MotionPolicy.pressScale(SlotView.pressScale, reduceMotion: false) == SlotView.pressScale)
        #expect(MotionPolicy.pressScale(SlotView.pressScale, reduceMotion: true) == 1)
    }

    /// The claim no unit test can make on its own.
    ///
    /// Reduce Motion is an environment value; a suite cannot set it and watch a
    /// view snap, and the simulator will not turn VoiceOver or Reduce Motion on
    /// under automation. What *can* be asserted is the declaration — the same
    /// technique #141 used to cover `.privacySensitive()` — and here the
    /// declaration is a property of every animating file at once: if it
    /// animates, it reads the setting.
    @Test("Every file that animates reads the setting")
    func animationIsAlwaysGuarded() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // the checkout
        let targets = ["Glow", "GlowWidget"].map {
            root.appendingPathComponent($0, isDirectory: true)
        }
        let files = targets.flatMap { directory -> [URL] in
            let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil
            )
            let all = (walker?.allObjects as? [URL]) ?? []
            return all.filter { $0.pathExtension == "swift" }
        }
        #expect(!files.isEmpty, "no sources found; the scan would pass vacuously")

        var animating: [String] = []
        var offenders: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            guard text.contains("withAnimation(") || text.contains(".animation(") else { continue }
            animating.append(file.lastPathComponent)
            // Either the view reads the environment itself, or it takes the
            // decision from the one place that owns it. The widget's burst is
            // the third shape: it reads the setting at the tap and leaves a
            // still timeline, so its file names `WidgetBurst.reduceMotion`.
            let guarded = text.contains("accessibilityReduceMotion")
                || text.contains("MotionPolicy.")
                || text.contains("WidgetBurst.reduceMotion")
            if !guarded { offenders.append(file.lastPathComponent) }
        }

        // Four files animate today: the slot, the span, the row's label and the
        // ring. If that number drops to nothing the scan has stopped finding
        // the sources rather than the app having stopped moving.
        #expect(animating.count >= 4, "found \(animating.count) animating file(s)")
        #expect(offenders.isEmpty, "animates without reading Reduce Motion: \(offenders)")
    }
}
