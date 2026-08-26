import MessageUI
import SwiftUI

/// Apple's mail composer, wrapped for one job: the history export with a
/// subject, a body and a single attachment, addressed to no one (#289).
///
/// The composer is the system's on purpose. Glow prepares the message and
/// then stops; the person reviews it, fills in where it goes, and presses
/// Send — or does not. Nothing is sent by this app, and nothing can be:
/// `MFMailComposeViewController` gives the hosting app no send call.
///
/// What this type owns is the translation between MessageUI and the app —
/// building the controller from `MailExport`'s decisions, and mapping the
/// delegate's four results onto `MailExport.Outcome` so that what happens
/// *after* the composer (`MailExport.reaction(to:)`) is testable without
/// presenting anything.
struct MailComposeView: UIViewControllerRepresentable {
    /// The attachment's bytes — read before presenting, so the composer holds
    /// the data itself and the temporary file's lifetime stays the sheet's,
    /// exactly as the share sheet's already is.
    let data: Data
    let filename: String
    let mimeType: String
    let subject: String
    /// Called once per delegate result. The presenter clears the sheet — the
    /// dismissal and the file's release ride on `onDismiss`, the same single
    /// event the share sheet uses, so a composer swiped away without ever
    /// calling the delegate still releases the file.
    let onFinish: (MailExport.Outcome) -> Void

    /// Whether this device can present a composer at all. The one call site
    /// of MessageUI's answer, so Settings routes through
    /// `MailExport.route(canSendMail:)` and a test can hold both branches
    /// without a configured Mail account.
    static func canSendMail() -> Bool {
        MFMailComposeViewController.canSendMail()
    }

    /// MessageUI's four results in the app's own words. Total: an unknown
    /// future case reads as `.failed`, which errs toward telling the person
    /// something went wrong rather than silently swallowing it.
    static func outcome(of result: MFMailComposeResult) -> MailExport.Outcome {
        switch result {
        case .sent: .sent
        case .saved: .saved
        case .cancelled: .cancelled
        case .failed: .failed
        @unknown default: .failed
        }
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setSubject(subject)
        controller.setMessageBody(MailExport.body, isHTML: false)
        // Empty, always: no recipient is discovered, inferred or prefilled.
        // Set explicitly rather than left to the default, so the promise is a
        // line of code beside the constant that states it.
        controller.setToRecipients(MailExport.recipients)
        controller.addAttachmentData(data, mimeType: mimeType, fileName: filename)
        return controller
    }

    func updateUIViewController(
        _ controller: MFMailComposeViewController, context: Context
    ) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MailExport.Outcome) -> Void

        init(onFinish: @escaping (MailExport.Outcome) -> Void) {
            self.onFinish = onFinish
        }

        /// The `error` parameter is deliberately not surfaced or logged: it
        /// can carry account details, and the reaction to `.failed` is the
        /// same whatever the reason. No path, no habit, no address ever
        /// reaches the log from here.
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish(MailComposeView.outcome(of: result))
        }
    }
}
