import Foundation
import OSLog

/// Where the store file lives.
///
/// A widget runs in its own process and cannot see the app's private container,
/// so the store has to sit in a shared App Group container that both
/// can open. This type owns that decision and the one-time move.
enum StoreLocation {
    static let appGroupID = "group.com.georgklock.glow"
    static let fileName = "Glow.store"

    /// The name SwiftData used before this indirection existed.
    static let legacyFileName = "default.store"

    private static let log = Logger(subsystem: "com.georgklock.glow", category: "store")

    /// The shared container, or nil when the App Group is unavailable, which
    /// happens if the entitlement is missing or the profile has not caught up.
    static var sharedContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// The store the app and widget both open.
    ///
    /// Falls back to the app's own Application Support directory when the group
    /// container is unavailable. The app then still works; only the widget goes
    /// blank, which is a better failure than refusing to launch.
    static var url: URL {
        if let shared = sharedContainer {
            return shared.appending(path: fileName)
        }
        log.error("App Group \(appGroupID, privacy: .public) unavailable; using the local container")
        return URL.applicationSupportDirectory.appending(path: fileName)
    }

    /// The store SwiftData wrote before any of this existed.
    static var legacyURL: URL {
        URL.applicationSupportDirectory.appending(path: legacyFileName)
    }

    /// Moves a pre-App-Group store into the shared container, once.
    ///
    /// The mechanics — staging, validating, promoting, recording — are
    /// `StoreMigration`'s. What lives here is only which two paths are involved,
    /// and that this runs to *wherever the store now lives*, shared or not:
    /// guarding on the shared container being available was a bug, because when
    /// the App Group is missing the path still changes from default.store to
    /// Glow.store, and skipping the copy silently orphans every habit the user
    /// had.
    ///
    /// The outcome is returned rather than only logged. A migration that could
    /// not be completed must stop the app opening a store on this path — an
    /// empty store created beside the person's real one is the failure that is
    /// hardest to undo.
    @discardableResult
    static func migrateIfNeeded() -> StoreMigration.Outcome {
        let outcome = StoreMigration.run(from: legacyURL, to: url)
        switch outcome {
        case .notNeeded, .migrated, .adopted:
            break
        case .repaired(let quarantine):
            log.error(
                "Store repaired from the earlier copy; the incomplete one is at \(quarantine.lastPathComponent, privacy: .public)"
            )
        case .diverged:
            log.error("Two stores diverged; the earlier one was left in place unmerged")
        case .failed(let reason):
            log.error("Store migration failed: \(reason, privacy: .public)")
        }
        return outcome
    }
}
