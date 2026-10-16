import UIKit

/// Whether this device is offered the goal pop at all (#661).
///
/// **The pop is two seconds over the Dynamic Island**, and that is the whole
/// of its argument (SPEC, the bounded exception to "no celebratory
/// flourishes"). An iPad has no Island. Measured on the iPad Air 11-inch (M4)
/// simulator: ActivityKit still reports Live Activities enabled,
/// `Activity.request` succeeds, and iPadOS shows the activity as a card in the
/// Lock Screen list — the first time behind its own "Allow Live Activities"
/// prompt. A card left on the Lock Screen is a different feature, and a
/// permission prompt for a feature whose surface the device lacks is worse
/// than no feature. So on anything that is not a phone the app does not
/// request the activity, and Settings does not offer the choice.
///
/// **A hardware capability, not a layout branch.** `docs/ARCHITECTURE.md`
/// keeps layout off the idiom — it follows the window's width, which is what
/// a resizable iPad window needs. Whether the device has a Dynamic Island does
/// not change with the window, and the idiom is the nearest public answer to
/// it: every iPhone the app runs on either has an Island or shows nothing for
/// a pop at all, and no iPad has one.
///
/// Pure: the idiom arrives as a parameter, read once at each boundary —
/// `SettingsView` for the section, `GoalPopCentre` before any request.
enum GoalPopAvailability {
    /// A phone is offered the pop; an iPad, a Mac running the iPad app, and
    /// any idiom added later are not. Unknown is a no, because the cost of a
    /// wrong yes is a system permission prompt and the cost of a wrong no is
    /// two seconds of words.
    static func isOffered(idiom: UIUserInterfaceIdiom) -> Bool {
        idiom == .phone
    }
}
