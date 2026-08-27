import Foundation
import Testing

@testable import Glow

/// The tab bar shows icons only, and must go on speaking its three names
/// (#319).
///
/// `.labelStyle(.iconOnly)` on the `TabView` is what removes the rendered
/// titles. That it keeps the titles as the tabs' *accessible* names was
/// measured rather than assumed — `RootTabView` hosted in a real window on an
/// iPhone 17 Pro simulator, iOS 26.5, the accessibility tree walked the way
/// `EmptyStateAccessibilityTests` walks its screen: "Widgets", "This Week"
/// and "Settings" were all spoken under a bar that renders none of them.
///
/// The measurement is not left running in the suite, deliberately. A hosted
/// `RootTabView` is a live hierarchy observing the week preferences, and the
/// host writes those keys from test threads — the #179 crash class, and the
/// hosted run took the test host down under exactly that write. One hosted
/// suite (`EmptyStateAccessibilityTests`) is the measured price already paid
/// (#245, #291); a second doubles it for a property that, once measured, is
/// held by the source. So this is a scan, the way `TestHostTests` reads
/// `GlowApp.swift` for claims a test cannot safely watch (#141, #168): the
/// style and the titles must both stay, because the style is what drops the
/// words from the glass and the titles are what keeps them in the tree.
struct TabBarAccessibilityTests {
    private func rootTabViewSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Glow/Views/RootTabView.swift"),
            encoding: .utf8
        )
    }

    @Test("The tab bar is icons only")
    func iconOnlyStyleIsApplied() throws {
        let source = try rootTabViewSource()
        #expect(
            source.contains(".labelStyle(.iconOnly)"),
            "the icon-only style left RootTabView; the titles are rendering again"
        )
    }

    @Test("Every tab still declares the name a screen reader speaks")
    func tabTitlesStayDeclared() throws {
        let source = try rootTabViewSource()
        for title in ["Tab(\"Widgets\"", "Tab(\"This Week\"", "Tab(\"Settings\""] {
            #expect(
                source.contains(title),
                "\(title)…) is gone — an icon-only tab without a title is silent under VoiceOver"
            )
        }
    }
}
