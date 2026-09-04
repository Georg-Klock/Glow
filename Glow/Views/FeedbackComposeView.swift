import MessageUI
import SwiftUI

/// Apple's mail composer, wrapped for the Send Feedback row (#564) — the same
/// shape `ShareSheet` is for Export History.
///
/// The composer is the system's on purpose. Glow fills in the recipient, the
/// subject and the version line and then stops; the person writes, and presses
/// Send or does not. Nothing is sent by this app, and nothing can be:
/// `MFMailComposeViewController` gives the hosting app no send call. The
/// delegate's four results all mean the same thing here — the sheet comes
/// down. MessageUI's error object is deliberately neither surfaced nor logged;
/// it can carry account details (#289's rule, kept).
struct FeedbackComposeView: UIViewControllerRepresentable {
    let version: AppVersion
    let onFinish: @MainActor () -> Void

    /// Whether this device can present a composer at all — false on every
    /// simulator and on any phone with no account in Mail. The one call site
    /// of MessageUI's answer; `SettingsView` routes on it and falls back to
    /// `FeedbackMail.mailtoURL`.
    @MainActor
    static func canSendMail() -> Bool {
        MFMailComposeViewController.canSendMail()
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([FeedbackMail.recipient])
        controller.setSubject(FeedbackMail.subject)
        controller.setMessageBody(FeedbackMail.body(version: version), isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    /// Main-actor like the delegate callbacks UIKit makes into it; the
    /// protocol predates isolation annotations, hence `@preconcurrency`.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let onFinish: @MainActor () -> Void

        init(onFinish: @escaping @MainActor () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish()
        }
    }
}
