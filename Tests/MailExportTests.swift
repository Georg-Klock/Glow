import Foundation
import MessageUI
import Testing
@testable import Glow

/// The email half of the export (#289), held at the seam MessageUI cannot
/// cross: everything here is what the composer is *given* and what Settings
/// does when it *comes back* — the two halves a test can pin without
/// presenting anything, and the two halves that carry the privacy promises.
@Suite("Mail export")
struct MailExportTests {
    private let calendar = TestCalendar.monday

    // MARK: - What the composer is given

    @Test("The subject is neutral and dated, and nothing else")
    func subjectIsNeutralAndDated() {
        let subject = MailExport.subject(
            on: TestCalendar.date(2026, 8, 17), calendar: calendar
        )
        #expect(subject == "Glow Up history — 2026-08-17")
    }

    @Test("The subject and the filename name the same civil day")
    func subjectMatchesFilename() {
        // Both spell the day through `DayID`, so an export made at 23:50
        // cannot carry one date in the subject and another on the attachment.
        let date = TestCalendar.date(2026, 8, 19)
        let subject = MailExport.subject(on: date, calendar: calendar)
        let filename = HistoryExport.filename(
            on: date, extension: "csv", calendar: calendar
        )
        #expect(subject.hasSuffix("2026-08-19"))
        #expect(filename == "Glow Up history 2026-08-19.csv")
    }

    @Test("The body says what the attachment is and where control ends")
    func bodyIsExactlyTheDecidedCopy() {
        // Pinned byte-for-byte: this copy is a published promise, and the
        // decided absence — nothing suggesting the email keeps the history
        // safe — is only checkable against the exact text.
        #expect(MailExport.body == """
            Attached is your Glow Up history — every habit and every day you \
            logged it.

            Pressing Send transfers the file through your email provider; \
            copies it keeps are outside Glow's control.
            """)
    }

    @Test("The message promises no safekeeping, in any spelling")
    func bodyMakesNoRecoveryPromise() {
        // The #285 sweep, held for the one new user-facing string this
        // feature adds. An export is not a backup, and the copy must not
        // drift toward implying the email protects anything.
        let lowered = (MailExport.body + " " + MailExport.subject(
            on: TestCalendar.date(2026, 8, 17), calendar: calendar
        )).lowercased()
        for phrase in ["backup", "back up", "restore", "recover", "safe"] {
            #expect(!lowered.contains(phrase), "the copy reads as a backup: \(phrase)")
        }
    }

    @Test("No recipient, ever")
    func recipientsAreEmpty() {
        // Glow does not know the person's address and does not claim to;
        // the To field is theirs to fill inside the composer.
        #expect(MailExport.recipients.isEmpty)
    }

    @Test("The MIME type is exact for the two files this app writes, nil past them")
    func mimeTypes() {
        #expect(MailExport.mimeType(forExtension: "csv") == "text/csv")
        #expect(MailExport.mimeType(forExtension: "json") == "application/json")
        // Case comes from a filename, not from this app's own spelling.
        #expect(MailExport.mimeType(forExtension: "CSV") == "text/csv")
        // No octet-stream fallback: a third format has to arrive here on
        // purpose or the composer is refused, never mislabelled.
        #expect(MailExport.mimeType(forExtension: "txt") == nil)
        #expect(MailExport.mimeType(forExtension: "") == nil)
    }

    // MARK: - Which surface a tap gets

    @Test("Mail that can send gets the composer; Mail that cannot gets the share sheet")
    func routing() {
        // Both arms, held here because a simulator without a Mail account
        // only ever executes one of them.
        #expect(MailExport.route(canSendMail: true) == .composer)
        #expect(MailExport.route(canSendMail: false) == .shareFallback)
    }

    // MARK: - What happens when the composer comes back

    @Test("The temporary file is released on every way out of the composer")
    func everyOutcomeReleasesTheFile() {
        // Sent and saved are Mail's copies now; cancelled and failed have no
        // reader left. Enumerated over `allCases` so a fifth outcome cannot
        // arrive without deciding what it releases.
        for outcome in MailExport.Outcome.allCases {
            #expect(MailExport.reaction(to: outcome).releasesFile)
        }
    }

    @Test("Only failure speaks; cancelling is a decision, not an error")
    func onlyFailureShowsAnError() {
        for outcome in MailExport.Outcome.allCases {
            #expect(
                MailExport.reaction(to: outcome).showsError == (outcome == .failed)
            )
        }
    }

    @Test("MessageUI's four results map one-to-one, in the view's own seam")
    func delegateResultsMap() {
        // The one place MessageUI's vocabulary is translated, so nothing
        // outside `MailComposeView` needs the framework.
        #expect(MailComposeView.outcome(of: .sent) == .sent)
        #expect(MailComposeView.outcome(of: .saved) == .saved)
        #expect(MailComposeView.outcome(of: .cancelled) == .cancelled)
        #expect(MailComposeView.outcome(of: .failed) == .failed)
    }
}
