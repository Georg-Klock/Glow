import Foundation
import SwiftData

/// What the removed debug tools left behind, taken out at launch (#628).
///
/// Demo history and Debug: Override Today shipped in every build (#204) and
/// then behind a hidden gesture (#566). Guideline 2.3.1(a) does not allow hidden
/// features, so both are gone from the app — but an install that used either
/// still carries their data, and deleting the tools deleted the only code that
/// could take it back out:
///
/// - **Invented completions.** Every row the demo wrote carries a
///   `demoSessionID` (#140). Left in place they are ten weeks of history nobody
///   logged, drawn and exported as if they were real — and once the attribute
///   comes off the model, SwiftData's lightweight migration keeps the rows with
///   nothing left saying they were invented. So the attribute stays for this
///   release and this purge runs on every launch; both come out together in the
///   first update after 1.0 ships.
/// - **Pre-provenance demo ids.** An install that seeded the demo before #140
///   recorded the ids in the App Group instead of on the rows. They are read,
///   deleted, and then the key goes.
/// - **The override key.** Nothing reads it any more, so it is only untidy, and
///   removed for that reason alone.
///
/// Idempotent and cheap on an install that never used either tool: two counting
/// predicates' worth of fetch and two key removals.
@MainActor
enum RetiredDebugData {
    /// Where Debug: Override Today stored its day (#204).
    static let debugTodayKey = "debugTodayOverride"

    /// Where the demo recorded its ids before they moved onto the rows (#140).
    static let demoLegacyIDsKey = "demoHistoryCompletionIDs"

    /// Deletes every invented completion and removes both keys. Returns how many
    /// rows went.
    ///
    /// One save for all of it, rolled back on failure so a half-applied purge
    /// never reaches the next save from somewhere else. The legacy key is removed
    /// only after that save, so an interrupted purge re-reads the same list next
    /// launch.
    ///
    /// **Deletes through the context and never touches `Habit.completions`.**
    /// That array is the rows this context fetched once, and a peer container —
    /// the widget's tap intent — can delete one behind its back; reading an
    /// element that is gone is a precondition failure inside SwiftData (#145,
    /// `StaleWriterTests`).
    @discardableResult
    static func purge(context: ModelContext, defaults: UserDefaults = GlowSettings.store) throws -> Int {
        defaults.removeObject(forKey: debugTodayKey)

        var doomed = try context.fetch(
            FetchDescriptor<Completion>(predicate: #Predicate { $0.demoSessionID != nil })
        )
        let legacy = (defaults.stringArray(forKey: demoLegacyIDsKey) ?? []).compactMap(UUID.init)
        if !legacy.isEmpty {
            let named = try context.fetch(
                FetchDescriptor<Completion>(predicate: #Predicate { legacy.contains($0.id) })
            )
            doomed += named.filter { $0.demoSessionID == nil }
        }

        if !doomed.isEmpty {
            for completion in doomed {
                context.delete(completion)
            }
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
            // The Widgets tab keeps a projection that only refreshes on a
            // committed save (#478). At launch no view is listening yet, so this
            // is for the rare purge that runs while one is.
            NotificationCenter.default.post(name: StoreChange.committed, object: nil)
        }

        defaults.removeObject(forKey: demoLegacyIDsKey)
        return doomed.count
    }
}
