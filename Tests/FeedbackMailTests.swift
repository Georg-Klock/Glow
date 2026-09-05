import Foundation
import Testing
@testable import Glow

/// The Send Feedback row's three fields and its `mailto:` fallback (#564).
@Suite("Feedback mail")
struct FeedbackMailTests {
    private let version = AppVersion(marketing: "0.1", build: "1")

    @Test("The recipient and subject are fixed")
    func fixedFields() {
        #expect(FeedbackMail.recipient == "glowup@georgklock.com")
        #expect(FeedbackMail.subject == "Glow Up feedback")
    }

    @Test("The body ends with the build and leaves room above it")
    func bodyCarriesTheVersion() {
        let body = FeedbackMail.body(version: version)
        #expect(body.hasSuffix("Glow Up 0.1 (1)"))
        #expect(body.hasPrefix("\n\n"), "composing should happen above the version line")
        #expect(!body.contains("?"), "an unread bundle would print ? here")
    }

    @Test("The mailto URL round-trips every field through its own encoding")
    func mailtoRoundTrips() throws {
        let url = try #require(FeedbackMail.mailtoURL(version: version))
        #expect(url.scheme == "mailto")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == FeedbackMail.recipient)
        let items = try #require(components.queryItems)
        #expect(items.count == 2)
        #expect(items.first { $0.name == "subject" }?.value == FeedbackMail.subject)
        #expect(items.first { $0.name == "body" }?.value == FeedbackMail.body(version: version))
    }

    @Test("The encoding escapes everything outside RFC 3986's unreserved set")
    func encodingIsStrict() throws {
        let encoded = try #require(FeedbackMail.percentEncoded("a b+c&d=e?f/g\n(h) ü-._~"))
        #expect(encoded == "a%20b%2Bc%26d%3De%3Ff%2Fg%0A%28h%29%20%C3%BC-._~")
        // What the URL actually carries: no raw space, newline, plus or
        // ampersand anywhere in the query, so no client can misread a field.
        // Read through `URLComponents`, as `mailtoRoundTrips` does: on iOS 18.5
        // `URL.query(percentEncoded:)` is nil for a `mailto:` URL and on 26.5 it
        // is the string, so asserting through it tested the runtime, not the
        // encoding (#573). The app never reads the query back; only this did.
        let url = try #require(FeedbackMail.mailtoURL(version: version))
        let query = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        )
        for raw in [" ", "\n", "+", "(", ")"] {
            #expect(!query.contains(raw), "raw \(raw.debugDescription) in query")
        }
        #expect(query.filter { $0 == "&" }.count == 1, "exactly one separator")
    }
}
