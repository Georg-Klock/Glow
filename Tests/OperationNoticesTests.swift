import Foundation
import Testing
@testable import Glow

/// #282: a failed user action is something the person is told about, in words
/// chosen here rather than by the error.
///
/// The suite constructs its own `OperationNotices` — the shared instance is
/// the app's, and a test that posted into it would be a test writing into
/// production state.
@MainActor
@Suite("Operation notices")
struct OperationNoticesTests {
    @Test("A reported failure becomes the current notice")
    func reportShows() {
        let notices = OperationNotices()
        #expect(notices.current == nil)
        notices.report(.mark)
        #expect(notices.current?.message == OperationNotices.Failure.mark.message)
        notices.dismiss()
        #expect(notices.current == nil)
    }

    @Test("A retry travels with a retryable failure")
    func retryIsKept() {
        let notices = OperationNotices()
        var retried = false
        notices.report(.export) { retried = true }
        notices.current?.retry?()
        #expect(retried)
    }

    @Test("A destructive failure drops its retry at the type")
    func destructiveDropsRetry() {
        let notices = OperationNotices()
        // Even a call site that passes one — the type is the gate, not
        // call-site discipline: a delete or a reset goes back through its own
        // confirmed path or not at all.
        notices.report(.delete) { Issue.record("a destructive retry was kept") }
        #expect(notices.current != nil)
        #expect(notices.current?.retry == nil)
        notices.report(.reset) { Issue.record("a destructive retry was kept") }
        #expect(notices.current?.retry == nil)
    }

    @Test("A newer failure replaces an older one")
    func newerReplacesOlder() {
        let notices = OperationNotices()
        notices.report(.reorder)
        let first = notices.current?.id
        notices.report(.mark)
        #expect(notices.current?.id != first)
        #expect(notices.current?.message == OperationNotices.Failure.mark.message)
    }

    /// The privacy rule, held where the words live (#282): the catalogue is
    /// fixed sentences, so nothing dynamic — no habit name, no UUID, no path,
    /// no framework text — can reach the alert. This asserts the shape every
    /// present and future case has to keep.
    @Test("Every message is a fixed, self-contained sentence")
    func messagesAreClosed() {
        let all: [OperationNotices.Failure] = [
            .save, .delete, .mark, .reorder, .addSpacer,
            .installDefaults, .reset, .demo, .export,
        ]
        for failure in all {
            let message = failure.message
            #expect(!message.isEmpty)
            #expect(message.hasSuffix("."), "\(message) is not a sentence")
            #expect(!message.contains("/"), "\(message) looks like it carries a path")
            // Eight hex digits in a row is the shortest telltale of an
            // interpolated identifier.
            #expect(
                message.ranges(of: /[0-9A-Fa-f]{8}/).isEmpty,
                "\(message) looks like it carries an identifier"
            )
        }
    }
}
