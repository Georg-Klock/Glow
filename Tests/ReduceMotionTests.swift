import Foundation
import Testing
@testable import Glow

/// #137: Reduce Motion was honoured on one animated surface out of four.
///
/// SPEC §3 said "Reduce Motion snaps" in the Today ring's section, and it was
/// true there and in the widget's burst, which records the setting at the tap
/// (`WidgetBurst`, #107). The week grid — the screen the app *is* — read the
/// setting nowhere: a completion closed on a spring, the row's label dimmed on
/// the same spring, and a press grew 32% and sprang back, whatever the person
/// had asked for.
///
/// The ring is gone with the per-day kind (#209) and `sweepsRing` with it, so
/// the surfaces are three and every one of them is asserted here.
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

    // `@MainActor` because `SlotView.pressScale` is: `View` carries the
    // isolation, and reading it from a nonisolated test is a warning today and
    // an error under a future language mode.
    @Test("A press does not grow when growth was declined")
    @MainActor
    func pressDoesNotGrow() {
        #expect(MotionPolicy.pressScale(SlotView.pressScale, reduceMotion: false) == SlotView.pressScale)
        #expect(MotionPolicy.pressScale(SlotView.pressScale, reduceMotion: true) == 1)
    }

    /// #398: the second kind of motion the app has.
    @Test("A removed row collapses, unless motion was declined")
    func removalCollapses() {
        #expect(MotionPolicy.collapsesRemoval(reduceMotion: false))
        #expect(!MotionPolicy.collapsesRemoval(reduceMotion: true))
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
            // ...or it *is* that one place. `MotionPolicy` cannot read
            // `MotionPolicy.`, and it names the calls it decides about in its
            // own documentation, which is enough to make this scan see it as a
            // file that animates. Matched on the declaration rather than the
            // file name so a second copy of the enum would not slip through.
            let guarded = text.contains("accessibilityReduceMotion")
                || text.contains("MotionPolicy.")
                || text.contains("enum MotionPolicy")
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
