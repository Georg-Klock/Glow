import Foundation
import Testing
@testable import Glow

/// The widget chooses the screen: each widget's URL lands on its own tab.
@Suite("Deep links")
struct DeepLinkTests {
    @Test("Each widget's own URL lands on its screen")
    func widgetURLs() {
        #expect(DeepLink.destination(for: DeepLink.week) == .week)
    }

    @Test("Case does not matter; a URL is not a spelling test")
    func caseInsensitive() {
        #expect(DeepLink.destination(for: URL(string: "Glow://WEEK")!) == .week)
        #expect(DeepLink.destination(for: URL(string: "GLOW://Week")!) == .week)
    }

    @Test("Anything unrecognised changes nothing rather than guessing a tab", arguments: [
        "glow://year",
        // The per-day screen's own link, and it now means nothing rather than
        // landing somebody on This Week uninvited (#209).
        "glow://today",
        "GLOW://Today",
        "glow://",
        "glowup://today",
        "https://today",
        "https://example.com/glow://today",
    ])
    func unknownIsNil(raw: String) {
        let url = URL(string: raw)
        #expect(url.flatMap(DeepLink.destination(for:)) == nil)
    }
}
