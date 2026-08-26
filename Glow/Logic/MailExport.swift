import Foundation

/// The email half of history export: what the message says, and what happens
/// on each way out of the composer (#289).
///
/// **It is an export, not a backup.** Nothing here — copy included — may
/// suggest that emailing the file protects anybody against losing their
/// phone. The file is a record a person chooses to send somewhere; where it
/// ends up, and whether it survives anything, is the mail provider's business
/// and is said to be.
///
/// The privacy boundary is the same one `HistoryExport` states, drawn one
/// step further: Glow prepares an attachment after a tap and presents Apple's
/// composer, and that is all. No recipient is prefilled — this app does not
/// know the person's address and does not claim to — nothing is sent until
/// they press Send, and the composer is the system's, so what they review is
/// what goes.
///
/// Pure, per the `WeekGrid` pattern: no views, no store, no `Date()`. The
/// composer itself is UIKit and lives in the view layer (`MailComposeView`);
/// what lives here is every decision a test can hold without presenting
/// anything — the exact subject, the exact body, the MIME type, the empty
/// recipient list, and the reaction to each of the four ways a composer can
/// come back.
enum MailExport {
    /// Neutral and dated, nothing else: "Glow Up history — 2026-08-26".
    ///
    /// The date is the export's own day in the calendar's spelling (`DayID`),
    /// so the subject and the filename name the same civil day.
    static func subject(
        on date: Date, calendar: Calendar = WeekCalendar.calendar
    ) -> String {
        "Glow Up history — \(DayID(date, calendar: calendar).text)"
    }

    /// One sentence saying what the attachment is, and one saying what Send
    /// does. Deliberately nothing about keeping it safe — see the type note.
    static let body = """
        Attached is your Glow Up history — every habit and every day you \
        logged it.

        Pressing Send transfers the file through your email provider; copies \
        it keeps are outside Glow's control.
        """

    /// Always empty. Glow never discovers, stores or guesses an address; the
    /// To field is the person's to fill in the composer. A constant rather
    /// than a convention, so a test can pin it.
    static let recipients: [String] = []

    /// The MIME type for the one of the two files this app writes, by the
    /// extension `HistoryExport.filename` gave it. Nil for anything else —
    /// there is no third format, and a fallback like `application/octet-stream`
    /// would let a new format ship with a silently wrong type.
    static func mimeType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "csv": "text/csv"
        case "json": "application/json"
        default: nil
        }
    }

    /// Which surface a tap on Email My History gets.
    ///
    /// The real branch in Settings calls this rather than reading
    /// `canSendMail()` inline, so both arms are exercised by a test instead of
    /// one of them existing only on devices with a configured Mail account.
    /// The fallback is the existing generic share sheet with the same file —
    /// the honest answer on a phone with no Mail, not an error.
    enum Route: Equatable {
        case composer
        case shareFallback
    }

    static func route(canSendMail: Bool) -> Route {
        canSendMail ? .composer : .shareFallback
    }

    /// The four ways out of the system composer, in this app's own words —
    /// the view layer maps `MFMailComposeResult` onto this so nothing outside
    /// it needs MessageUI.
    enum Outcome: CaseIterable, Equatable {
        case sent
        case saved
        case cancelled
        case failed
    }

    /// What Settings does when the composer comes back.
    ///
    /// The temporary file is released on **all four** outcomes: once the
    /// composer is dismissed the system has taken what it needs — a sent
    /// message or a saved draft is Mail's copy, not Glow's — and a cancelled
    /// or failed compose has no reader left. Only `.failed` shows an error;
    /// cancelling is a decision, not a failure, and dressing it as one would
    /// teach people that backing out breaks something.
    struct Reaction: Equatable {
        let releasesFile: Bool
        let showsError: Bool
    }

    static func reaction(to outcome: Outcome) -> Reaction {
        Reaction(releasesFile: true, showsError: outcome == .failed)
    }
}
