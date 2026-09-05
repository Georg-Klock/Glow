import Foundation

/// What the Send Feedback row puts in front of a person (#564): who it goes
/// to, what it is called, and the one line the body carries before they start
/// typing. Pure, so the `mailto:` fallback's encoding is asserted rather than
/// trusted — a malformed fallback URL fails silently.
///
/// **This is not #289 coming back.** Email My History was a second way to send
/// the *export* to the person's own address and was removed as a duplicate of
/// the share sheet (#317). This sends a message *to Georg*, carries no file and
/// no history, and is the only way in the app to reach him. The local-only
/// invariant is untouched: a compose sheet a person reviews and can cancel, and
/// nothing is sent by the app itself — `MFMailComposeViewController` gives the
/// hosting app no send call, and a `mailto:` URL only opens a client.
enum FeedbackMail {
    /// Fixed. Nothing here discovers, infers or prefills anyone else.
    static let recipient = "glowup@georgklock.com"

    /// Short and greppable in an inbox; editable in the composer.
    static let subject = "Glow Up feedback"

    /// The body a compose sheet opens with: room to write, then the build the
    /// message is about, the way a bug report wants it and positioned so
    /// composing happens above it rather than after it.
    static func body(version: AppVersion) -> String {
        "\n\n\n— Glow Up \(version.marketing) (\(version.build))"
    }

    /// The fallback for a device with no Mail account, where
    /// `MFMailComposeViewController.canSendMail()` is false — every simulator,
    /// and any phone whose mail lives in a third-party client. Hands the same
    /// three fields to whichever app registers the scheme.
    ///
    /// **Encoded by hand, to RFC 3986's unreserved set.** `URLComponents`
    /// leaves `+`, `&`-adjacent characters and a mailto's `?` alone in places a
    /// mail client may not, and a `+` in a subject is read as a space by some
    /// of them. Alphanumerics and `-._~` pass; every other byte, spaces and
    /// newlines included, is a `%XX` escape. Round-tripped in
    /// `FeedbackMailTests`.
    static func mailtoURL(version: AppVersion) -> URL? {
        guard let subject = percentEncoded(subject),
              let body = percentEncoded(body(version: version))
        else { return nil }
        return URL(string: "mailto:\(recipient)?subject=\(subject)&body=\(body)")
    }

    /// RFC 3986 unreserved characters only.
    static func percentEncoded(_ text: String) -> String? {
        text.addingPercentEncoding(withAllowedCharacters: unreserved)
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
