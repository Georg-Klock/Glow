import Foundation
import Testing
@testable import Glow

/// The widget chooses the screen: each widget's URL lands on its own tab.
@Suite("Deep links")
struct DeepLinkTests {
    @Test("Each widget's own URL lands on its screen")
    func widgetURLs() {
        #expect(DeepLink.destination(for: DeepLink.today) == .today)
        #expect(DeepLink.destination(for: DeepLink.week) == .week)
    }

    @Test("Case does not matter; a URL is not a spelling test")
    func caseInsensitive() {
        #expect(DeepLink.destination(for: URL(string: "GLOW://Today")!) == .today)
        #expect(DeepLink.destination(for: URL(string: "Glow://WEEK")!) == .week)
    }

    @Test("Anything unrecognised changes nothing rather than guessing a tab", arguments: [
        "glow://year",
        "glow://",
        "glowup://today",
        "https://today",
        "https://example.com/glow://today",
    ])
    func unknownIsNil(raw: String) {
        let url = try? #require(URL(string: raw))
        #expect(url.flatMap(DeepLink.destination(for:)) == nil)
    }
}
