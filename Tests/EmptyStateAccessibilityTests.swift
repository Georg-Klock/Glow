import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import Glow

/// What the empty state says to a screen reader, and what it does when one
/// activates it — read out of the real accessibility tree rather than out of
/// the source (#243).
///
/// The empty state used to be a `ContentUnavailableView`, and dropping its
/// icon, title and description raised the one question a layout change usually
/// does not: whether the screen still explains itself to somebody who cannot
/// see it. The answer is measured here rather than argued. The view is hosted
/// in a real window over an empty store, and the elements UIKit hands the
/// accessibility server are walked in order — which is what VoiceOver reads.
///
/// **The claim these tests hold to is parity.** Two buttons is what the screen
/// shows and two buttons is what it says; the icon never carried a label, so
/// the title and the description were the whole of the spoken difference and
/// they left the screen and the announcement together. If a later change adds
/// an invisible third thing — an `.accessibilityLabel` with no visible text
/// behind it — this suite is where that shows up, so that adding one is a
/// decision rather than a side effect.
///
/// **Activation is the same path, not a stand-in for it.**
/// `accessibilityActivate()` is what VoiceOver's double tap calls, so the two
/// tests that press the buttons press them the way a screen reader user does,
/// and they answer the other half of #243 — that both actions still do what
/// #228 built them to do.
///
/// The navigation bar is walked past on purpose: the week readout and the plus
/// button are `WeeklyGridView`'s toolbar, present with habits and without, and
/// what is under test is the screen's own content.
///
/// **This is the only suite in the repository that hosts a live view, and it is
/// the only one with a requirement on the simulator** (#245). Read this before
/// suspecting your own change.
///
/// UIKit loads the accessibility bundles into an app only when the device says
/// accessibility is enabled, and a fresh simulator does not say that. In a
/// process without them *nothing* vends an element — not the buttons, not the
/// navigation bar, not the hosting view — so the walk below finds an empty tree
/// and every assertion here fails on a screen that is perfectly correct. That
/// is what an absent runtime looks like: empty, rather than wrong, which is why
/// it reads as a layout problem and is not one. Measured on an erased device:
/// `_AXSApplicationAccessibilityEnabled` false, the root's element count zero,
/// every node `isAccessibilityElement = false`. With the preference set, on the
/// same binary and the same machine, the two `AccessibilityNode`s appear.
///
/// `Tools/test.sh` writes `AccessibilityEnabled` and
/// `ApplicationAccessibilityEnabled` into the device's `com.apple.Accessibility`
/// domain before it hands the simulator to `xcodebuild`, which is why the
/// command in CLAUDE.md is the one to run. **A hand-typed `xcodebuild test` on a
/// simulator that has never had accessibility switched on will fail these four
/// and nothing else** — that shape of failure is the diagnosis.
///
/// The preference cannot be set from in here: it is read as the test host
/// launches, long before any test runs.
/// **Every container this suite builds is held for the life of the test host**
/// (#357), on `Screen.kept` below. The flake that closes was the host
/// *dying*, not a test failing an expectation, which is why it arrived as a
/// bare `[Failed]` with nothing in it to read.
@MainActor
struct EmptyStateAccessibilityTests {
    @Test func theEmptyStateSpeaksItsTwoButtonsAndNothingElse() throws {
        let screen = try Screen()
        defer { screen.tearDown() }
        let spoken = screen.contentElements()

        #expect(
            spoken.compactMap(\.accessibilityLabel) == [
                "Add Your First Habit",
                "Start with a Pre-Selected Set",
            ],
            "the empty state's spoken content was \(spoken.map { $0.accessibilityLabel ?? "<nil>" })"
        )
        #expect(spoken.allSatisfy { $0.accessibilityTraits.contains(.button) })
        #expect(spoken.allSatisfy { $0.accessibilityTraits.contains(.notEnabled) == false })
    }

    /// The two sentences left the announcement, not just the screen.
    @Test func nothingSpeaksTheDeletedTitleOrDescription() throws {
        let screen = try Screen()
        defer { screen.tearDown() }
        let labels = screen.contentElements().compactMap(\.accessibilityLabel)

        #expect(labels.contains("No Habits") == false)
        #expect(labels.contains { $0.contains("waiting for you") } == false)
    }

    @Test func activatingTheSecondButtonInstallsTheCuratedSet() throws {
        let screen = try Screen()
        defer { screen.tearDown() }
        let button = try #require(screen.element(labelled: "Start with a Pre-Selected Set"))

        #expect(button.accessibilityActivate())
        screen.settle()

        let habits = try screen.container.mainContext.fetch(FetchDescriptor<Habit>())
        #expect(habits.count == DefaultHabits.all.count)
        #expect(habits.contains { $0.completions?.isEmpty == false } == false)
    }

    @Test func activatingTheFirstButtonOpensTheEditor() throws {
        let screen = try Screen()
        defer { screen.tearDown() }
        let button = try #require(screen.element(labelled: "Add Your First Habit"))

        #expect(button.accessibilityActivate())
        screen.settle()

        #expect(screen.host.presentedViewController != nil)
        #expect(try screen.container.mainContext.fetchCount(FetchDescriptor<Habit>()) == 0)
    }

    // MARK: - Reading the tree

    /// `WeeklyGridView` over an empty store, hosted in a window.
    ///
    /// A window, not a detached view: SwiftUI builds no accessibility elements
    /// for a hierarchy that was never put on screen, and a sheet has nothing to
    /// present from.
    @MainActor
    struct Screen {
        /// **Every container this suite builds is held for the life of the
        /// test host, and that is the fix for #357.**
        ///
        /// SwiftData registers an observer of its own on
        /// `NotificationCenter.default` for the `@Query` in a hosted
        /// `WeeklyGridView` — the `_SwiftData_SwiftUI` frame in every crash
        /// report — and nothing takes that observer away when the view goes.
        /// Once the container behind it has been deallocated, the next
        /// `ModelContext.save()` *anywhere in the process* is posted to it and
        /// traps inside SwiftData: `EXC_BREAKPOINT`, the test host restarted
        /// by `xcodebuild`, and a bare `[Failed]` against whichever test was
        /// running when it went.
        ///
        /// That is measured, not reasoned about. Releasing the container after
        /// unmounting the screen and then saving from the next one reproduced
        /// the reported crash — the same trap address, the same
        /// `_SwiftData_SwiftUI` frames, `HabitStore.commit()` under a
        /// `postNotificationName` — on **6 runs out of 6**. The same arm with
        /// the container held: **0 out of 6**.
        ///
        /// **What it is not** is two screens alive at once, which is what this
        /// was filed under. Two live screens over two live containers, one of
        /// them saving, is 0 runs out of 6; three at once is clean too. A
        /// foreign save reaching a *live* container's observer is fine. So
        /// this suite is left free to overlap, and nothing here unmounts: the
        /// teardown below is unchanged, because replacing the root view is
        /// what *releases* the container and that is the one thing that must
        /// not happen.
        ///
        /// Four in-memory containers for the life of one test host is the
        /// price, and none of this reaches the app: `GlowStore` builds one
        /// container for the life of the process and never releases it.
        private static var kept: [ModelContainer] = []

        let container: ModelContainer
        let host: UIViewController
        let window: UIWindow

        init() throws {
            container = try ModelContainer(
                for: GlowStore.schema,
                configurations: ModelConfiguration(
                    schema: GlowStore.schema, isStoredInMemoryOnly: true
                )
            )
            host = UIHostingController(rootView: WeeklyGridView().modelContainer(container))
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            // Joined to the host app's scene: a window with none presents no
            // sheet, which reads as a dead button rather than as a detached
            // window.
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                window.windowScene = scene
            }
            window.rootViewController = host
            window.isHidden = false
            window.makeKeyAndVisible()
            Screen.kept.append(container)
            settle()
        }

        /// The grid's `.task`, SwiftUI's layout pass and a sheet's presentation
        /// all land on the run loop, and none of what is asserted here exists
        /// until they have.
        func settle() {
            host.view.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            host.view.layoutIfNeeded()
        }

        /// Put the window away before the next test builds its own.
        ///
        /// **Unchanged, and deliberately so** (#357). Unmounting the screen
        /// here — replacing the root view — was tried, and it is what releases
        /// the `ModelContainer`, which is the crash's one precondition:
        /// measured, that turns a 4% flake into a crash on 6 runs out of 6.
        /// The container has to outlive the observer, so the screen may as
        /// well stay up. See `kept` above.
        func tearDown() {
            host.presentedViewController?.dismiss(animated: false)
            window.rootViewController = nil
            window.isHidden = true
            window.windowScene = nil
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        func contentElements() -> [NSObject] {
            var found: [NSObject] = []
            var seen = Set<ObjectIdentifier>()
            Screen.walk(host.view, into: &found, seen: &seen, depth: 0)
            return found
        }

        func element(labelled label: String) -> NSObject? {
            contentElements().first { $0.accessibilityLabel == label }
        }

        private static func walk(
            _ node: NSObject, into found: inout [NSObject], seen: inout Set<ObjectIdentifier>,
            depth: Int
        ) {
            guard depth < 60 else { return }
            guard seen.insert(ObjectIdentifier(node)).inserted else { return }
            // The toolbar is the same in both states and is not this screen's
            // content. Its elements are `_UIButtonBarButton`s under the bar.
            let className = String(describing: type(of: node))
            guard className.contains("NavigationBar") == false,
                className.contains("ButtonBar") == false
            else { return }

            if node.isAccessibilityElement {
                found.append(node)
            }

            if let children = node.accessibilityElements as? [NSObject], children.isEmpty == false {
                for child in children {
                    walk(child, into: &found, seen: &seen, depth: depth + 1)
                }
            } else {
                let count = node.accessibilityElementCount()
                if count > 0 && count != NSNotFound {
                    for index in 0..<count {
                        guard let child = node.accessibilityElement(at: index) as? NSObject else {
                            continue
                        }
                        walk(child, into: &found, seen: &seen, depth: depth + 1)
                    }
                }
            }

            if let view = node as? UIView {
                for subview in view.subviews {
                    walk(subview, into: &found, seen: &seen, depth: depth + 1)
                }
            }
        }
    }
}
