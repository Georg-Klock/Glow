import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import Glow

/// The tab bar shows icons only, and still speaks its three names (#319).
///
/// `.labelStyle(.iconOnly)` on the `TabView` is what removes the rendered
/// titles — checked against the iOS 26.5 SDK by looking rather than by
/// reading: the simulator renders three icons and no text under them. What
/// this suite holds is the half that must not go with the look: the `Tab`
/// titles stay the tabs' accessible names, so a screen reader still hears
/// "Widgets", "This Week" and "Settings" under a bar that shows none of those
/// words. If a later change swaps the style for something that strips the
/// title from the accessibility tree too, this is where it shows up.
///
/// Hosted the way `EmptyStateAccessibilityTests` hosts its screen, and under
/// the same simulator requirement (#245): a device that has never had
/// accessibility enabled vends an empty tree, which fails this suite on a
/// correct screen. `Tools/test.sh` switches it on; a hand-typed `xcodebuild
/// test` may not have.
@MainActor
struct TabBarAccessibilityTests {
    @Test func iconOnlyTabsStillSpeakTheirNames() throws {
        let screen = try Screen()
        defer { screen.tearDown() }

        for name in ["Widgets", "This Week", "Settings"] {
            let element = screen.element(labelled: name)
            #expect(element != nil, "no accessibility element speaks \(name)")
        }
    }

    /// The same shape as `EmptyStateAccessibilityTests.Screen`, hosting the
    /// whole `RootTabView` so the walked tree is the one the tab bar vends.
    @MainActor
    struct Screen {
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
            host = UIHostingController(rootView: RootTabView().modelContainer(container))
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                window.windowScene = scene
            }
            window.rootViewController = host
            window.isHidden = false
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            host.view.layoutIfNeeded()
        }

        func tearDown() {
            host.presentedViewController?.dismiss(animated: false)
            window.rootViewController = nil
            window.isHidden = true
            window.windowScene = nil
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        func element(labelled label: String) -> NSObject? {
            var found: [NSObject] = []
            var seen = Set<ObjectIdentifier>()
            Self.walk(host.view, into: &found, seen: &seen)
            return found.first { $0.accessibilityLabel == label }
        }

        private static func walk(
            _ node: NSObject, into found: inout [NSObject], seen: inout Set<ObjectIdentifier>
        ) {
            guard seen.insert(ObjectIdentifier(node)).inserted else { return }
            if node.isAccessibilityElement {
                found.append(node)
                return
            }
            if let elements = node.accessibilityElements {
                for case let element as NSObject in elements {
                    walk(element, into: &found, seen: &seen)
                }
            }
            if let view = node as? UIView {
                for sub in view.subviews {
                    walk(sub, into: &found, seen: &seen)
                }
            }
        }
    }
}
