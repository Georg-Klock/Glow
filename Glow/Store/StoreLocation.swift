import Foundation
import OSLog

/// Where the store file lives.
///
/// A widget runs in its own process and cannot see the app's private
/// container, so the store has to sit in a shared App Group container that both
/// can open. This type owns that decision and the one-time move.
enum StoreLocation {
    static let appGroupID = "group.com.georgklock.glow"
    static let fileName = "Glow.store"

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

    /// Moves a pre-App-Group store into the shared container, once.
    ///
    /// SwiftData keeps a write-ahead log and a shared-memory file next to the
    /// store, and moving the store without them loses every write still sitting
    /// in the log. That is the whole reason this is not a one-line copy.
    static func migrateIfNeeded() {
        // Migrates to wherever the store now lives, shared or not. Guarding on
        // the shared container being available was a bug: when the App Group is
        // missing, the path still changes from default.store to Glow.store, and
        // skipping the copy silently orphans every habit the user had.
        let destination = url
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { return }

        // The name SwiftData used before this indirection existed.
        let legacy = URL.applicationSupportDirectory.appending(path: "default.store")
        guard manager.fileExists(atPath: legacy.path) else { return }

        do {
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(fileURLWithPath: legacy.path + suffix)
                let to = URL(fileURLWithPath: destination.path + suffix)
                guard manager.fileExists(atPath: from.path) else { continue }
                try manager.copyItem(at: from, to: to)
            }
            log.info("Moved the store into the App Group container")
        } catch {
            // Leave the original alone: a half-migrated store that still opens
            // from its old location beats a lost one.
            log.error("Store migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
