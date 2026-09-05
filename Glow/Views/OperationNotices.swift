import Foundation
import Observation
import SwiftUI

/// The one place a failed user action becomes something the person can see.
///
/// **A log is not feedback** (#282). Every mutation in this app already throws
/// correctly and rolls back, and every catch block called `HabitStore.report`
/// — which writes an OS log a developer can read and the person who tapped
/// cannot. A failed toggle looked accepted, a failed reorder looked done, a
/// failed export did nothing visible at all. The log stays, as the diagnostic
/// it always was; this is the other half.
///
/// One mechanism rather than per-view alerts, so every failure speaks with
/// the same voice and the same rules:
///
/// - **The message is a fixed sentence chosen here.** Never the error's own
///   text — `localizedDescription` can carry a path or a framework detail —
///   and never a habit's name, a UUID, or anything a person typed. The
///   underlying error goes to the log, privacy-qualified, where it went
///   before.
/// - **Retry is offered only where the operation is safe to repeat.** The
///   catch site decides, because only it knows: a failed save rolled back, so
///   re-running a toggle, a reorder or an export starts from clean state. A
///   *destructive* action never carries a retry — deleting and resetting go
///   back through their own confirmed path or not at all.
///
/// `RootTabView` presents the current notice as an alert, which is the
/// accessible answer for a rare event: VoiceOver announces it once, focus
/// moves to it, and it says nothing a screen reader should not read out.
@MainActor
@Observable
final class OperationNotices {
    /// The app's one instance. A singleton rather than environment plumbing
    /// because the reporters are catch blocks in computed bindings and
    /// per-operation stores, where an `@Environment` value has no view to
    /// arrive through. Tests construct their own.
    static let shared = OperationNotices()

    /// What failed, in the words the person is shown.
    ///
    /// The catalogue is closed on purpose: a new failure surface picks one of
    /// these or adds a case *here*, where the privacy rule above is the review
    /// gate — not an interpolated string at the call site.
    enum Failure {
        case save
        case delete
        case mark
        case reorder
        case addSpacer
        case installDefaults
        case reset
        case demo
        case export

        var message: String {
            switch self {
            case .save: "The habit could not be saved."
            case .delete: "The habit could not be deleted."
            case .mark: "That could not be recorded."
            case .reorder: "The new order could not be saved."
            case .addSpacer: "The blank row could not be added."
            case .installDefaults: "The habits could not be added."
            case .reset: "Nothing was reset. Your habits are unchanged."
            case .demo: "The demo history could not be changed."
            case .export: "The export could not be written, so nothing was shared."
            }
        }

        /// Whether a retry may even be offered. Destructive operations are
        /// excluded at the type, not by call-site discipline: a caller passing
        /// a retry closure for these is ignored, so renewed confirmation is
        /// the only way back through them.
        var allowsRetry: Bool {
            switch self {
            case .delete, .reset: false
            case .save, .mark, .reorder, .addSpacer, .installDefaults, .demo, .export: true
            }
        }
    }

    struct Notice: Identifiable {
        let id = UUID()
        let failure: Failure
        /// Re-runs the operation, when the operation is safe to re-run.
        let retry: (@MainActor () -> Void)?

        var message: String { failure.message }
    }

    private(set) var current: Notice?

    /// Shows one failure. A second failure while one is up replaces it — the
    /// newer one is the one whose gesture the person just made.
    func report(_ failure: Failure, retry: (@MainActor () -> Void)? = nil) {
        current = Notice(failure: failure, retry: failure.allowsRetry ? retry : nil)
    }

    func dismiss() {
        current = nil
    }
}

extension View {
    /// Presents the current failure notice as an alert.
    ///
    /// An alert rather than a banner: rare enough to interrupt, announced
    /// once by VoiceOver, and dismissed knowingly. "Try Again" appears only
    /// when the notice carries a retry — `OperationNotices.Failure.allowsRetry`
    /// keeps it off destructive operations at the type.
    ///
    /// **Attached once per presentation context**, not once per view: on
    /// `RootTabView` for everything the tabs show, and on `HabitEditorView`
    /// because it is a sheet — an alert attached under an active sheet cannot
    /// present, so a save failure inside the editor would be feedback the
    /// person never sees. The two contexts cannot both present at once — the
    /// sheet covers the root exactly when it is the one reporting — so one
    /// notice gets one alert.
    @MainActor
    func operationNoticeAlert() -> some View {
        modifier(OperationNoticeAlert())
    }
}

@MainActor
private struct OperationNoticeAlert: ViewModifier {
    private var notices = OperationNotices.shared

    func body(content: Content) -> some View {
        content.alert(
            notices.current?.message ?? "",
            isPresented: Binding(
                get: { notices.current != nil },
                set: { if !$0 { notices.dismiss() } }
            )
        ) {
            if let retry = notices.current?.retry {
                Button("Try Again") { retry() }
            }
            Button("OK", role: .cancel) {}
        }
    }
}
