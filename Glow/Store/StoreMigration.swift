import Foundation
import OSLog
import SwiftData

/// Moving the store from one path to another without ever adopting half of it.
///
/// A SQLite store is not one file. SwiftData keeps a write-ahead log and a
/// shared-memory file beside the database, and the recent writes — the ones a
/// person would notice missing — are exactly the ones still sitting in the log.
/// Copying the three files one at a time and logging whatever went wrong leaves
/// a destination that opens perfectly and is missing last week, and because the
/// destination now exists, every later launch skips the migration and keeps it.
/// That is #131.
///
/// So nothing is copied into place. A complete set is staged beside the
/// destination, opened as a real `ModelContainer` to prove it is a store and not
/// a prefix of one, and only then moved in — sidecars first, database last,
/// because the database file is what every later launch tests for. A promotion
/// cut short therefore leaves no destination to adopt, and the next launch
/// starts over.
///
/// Two rules hold the rest up:
///
/// - **The source is never deleted.** Not after a successful migration either.
///   Reclaiming that space is a separate, later decision that can be taken when
///   the new copy has proven itself over more than one launch.
/// - **Nothing is overwritten, only moved aside.** A destination that has to be
///   replaced goes to `Quarantine/`, where it can still be opened by hand.
enum StoreMigration {
    private static let log = Logger(subsystem: "com.georgklock.glow", category: "store")

    /// The files SwiftData keeps beside the database, in the order they are
    /// promoted. The database itself is last and is not in this list.
    static let sidecarSuffixes = ["-wal", "-shm"]

    /// Where a staged copy is assembled: a directory beside the destination,
    /// deliberately in the same container so that promoting it is a rename
    /// rather than a second copy that can fail halfway.
    static let stagingDirectoryName = "Migration-Staging"

    /// Where a displaced store is kept.
    static let quarantineDirectoryName = "Quarantine"

    // MARK: - What happened

    enum Outcome: Equatable, Sendable {
        /// Nothing to do: no earlier store, or this one is already recorded.
        case notNeeded
        /// A staged copy was validated and promoted.
        case migrated
        /// A destination that was already there proved to be a complete store
        /// holding everything the source holds, and was recorded as such.
        case adopted
        /// The destination was unopenable or was a strict subset of the source
        /// — a partial copy. It was moved to `quarantine` and replaced.
        case repaired(quarantine: URL)
        /// Both stores hold records the other does not. Neither is authoritative
        /// by inspection, so the destination stays in use, the source stays
        /// where it is, and the record names it for a later merge.
        case diverged(source: URL)
        /// Nothing was changed. The caller must not open a store on this path:
        /// the person's history is elsewhere and opening would create an empty
        /// one beside it.
        case failed(String)
    }

    /// Thrown so a failed migration reaches the app as an error rather than as
    /// a silently empty store.
    struct Failure: LocalizedError, Equatable {
        let reason: String
        var errorDescription: String? { reason }
    }

    // MARK: - What a store contains

    /// The stable identifiers in a store, which is what two candidates are
    /// compared on. Counts alone cannot tell a partial copy from a store the
    /// person has since edited; identifiers can.
    struct Inventory: Equatable, Sendable {
        var habitIDs: Set<UUID> = []
        var completionIDs: Set<UUID> = []

        var habitCount: Int { habitIDs.count }
        var completionCount: Int { completionIDs.count }

        /// Every record `other` has is here too — so this store could be a
        /// later state of `other`, and adopting it loses nothing.
        func covers(_ other: Inventory) -> Bool {
            other.habitIDs.isSubset(of: habitIDs)
                && other.completionIDs.isSubset(of: completionIDs)
        }
    }

    // MARK: - The durable marker

    /// Written last, and only after the destination has been proven to open.
    ///
    /// Its presence is what makes a later launch cheap: without it every launch
    /// would open and count both stores. Its *absence* beside an existing
    /// destination is the interesting state — that is either an install
    /// migrated before this record existed or a promotion cut short, and both
    /// are settled by inspection rather than assumed.
    ///
    /// `format` is the extension point. A versioned schema migration adds its
    /// own version here and bumps it; a record this build cannot read is
    /// treated as absent, which costs one revalidation and never adopts
    /// anything unproven.
    struct Record: Codable, Equatable, Sendable {
        static let currentFormat = 1

        var format: Int = currentFormat
        /// Identifies this copy, so a later merge can say which one it means.
        var generation: UUID = UUID()
        var migratedAt: Date = Date()
        var source: String
        var habitCount: Int
        var completionCount: Int
        /// A store that could not be merged in automatically and is still on
        /// disk. Nil in every ordinary case.
        var unmergedSource: String?
    }

    static func recordURL(for destination: URL) -> URL {
        URL(fileURLWithPath: destination.path + ".migration.json")
    }

    static func readRecord(for destination: URL) -> Record? {
        guard let data = try? Data(contentsOf: recordURL(for: destination)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(Record.self, from: data) else { return nil }
        // A record from a later build describes a store this one may not
        // understand. Treat it as absent and re-prove the destination.
        guard record.format <= Record.currentFormat else { return nil }
        return record
    }

    // MARK: - The migration

    /// Ensures the store at `destination` is a complete copy of the store at
    /// `source`, or says why it is not.
    ///
    /// Safe to call on every launch: once a destination is recorded this returns
    /// immediately, and it never writes to `source`.
    @discardableResult
    static func run(from source: URL, to destination: URL) -> Outcome {
        let manager = FileManager.default
        let sourceExists = manager.fileExists(atPath: source.path)
        let destinationExists = manager.fileExists(atPath: destination.path)

        // A fresh install: no history anywhere, nothing to prove.
        guard sourceExists || destinationExists else { return .notNeeded }

        if destinationExists, readRecord(for: destination) != nil { return .notNeeded }

        guard sourceExists else {
            // Nothing to fall back to, so the destination is either good or the
            // app has a problem it must report rather than paper over.
            guard let inventory = inventory(of: destination) else {
                return .failed(
                    "The store could not be opened, and there is no earlier copy to restore from."
                )
            }
            writeRecord(for: destination, source: source, inventory: inventory)
            log.info("Adopted an existing store that predates the migration record")
            return .adopted
        }

        let staging = destination.deletingLastPathComponent()
            .appending(path: stagingDirectoryName)
        let stagedStore = staging.appending(path: destination.lastPathComponent)
        // Whatever happens below, no staging artifact is left to be mistaken
        // for a store or to block the next attempt.
        defer { try? manager.removeItem(at: staging) }

        let staged: Inventory
        do {
            try stage(source, into: staging, as: stagedStore)
            guard let inventory = inventory(of: stagedStore) else {
                throw Failure(reason: "the copy did not open as a store")
            }
            staged = inventory
        } catch {
            let reason = (error as? Failure)?.reason ?? error.localizedDescription
            log.error("Staging the earlier store failed: \(reason, privacy: .public)")
            // The source is untouched and still openable from where it is. If
            // there is also a destination, prove it before trusting it.
            if destinationExists, let inventory = inventory(of: destination) {
                writeRecord(for: destination, source: source, inventory: inventory)
                return .adopted
            }
            return .failed("The earlier store could not be copied: \(reason).")
        }

        if destinationExists {
            let existing = inventory(of: destination)

            if let existing, existing.covers(staged) {
                // Everything the source holds is already here, plus whatever
                // the person has done since. Leave it alone and record it.
                writeRecord(for: destination, source: source, inventory: existing)
                return .adopted
            }

            if let existing, !staged.covers(existing) {
                // Each holds records the other does not, so neither can be
                // called the later state of the other by looking at it. The
                // destination is what the app has been writing to, so it stays;
                // the source stays where it is and is named in the record.
                writeRecord(
                    for: destination, source: source, inventory: existing, unmerged: source
                )
                log.error(
                    """
                    Two stores diverged; keeping the one in use and leaving \
                    \(source.lastPathComponent, privacy: .public) in place
                    """
                )
                return .diverged(source: source)
            }

            // Unopenable, or a strict subset of the store it came from — which
            // no amount of later use could produce. This is the partial copy.
            do {
                let quarantine = try quarantine(destination)
                try promote(from: stagedStore, to: destination)
                writeRecord(for: destination, source: source, inventory: staged)
                log.error(
                    """
                    Replaced an incomplete store; the previous one is in \
                    \(quarantineDirectoryName, privacy: .public)
                    """
                )
                return .repaired(quarantine: quarantine)
            } catch {
                return .failed(
                    "The incomplete store could not be replaced: \(error.localizedDescription)."
                )
            }
        }

        do {
            try promote(from: stagedStore, to: destination)
            writeRecord(for: destination, source: source, inventory: staged)
            log.info("Moved the store into the App Group container")
            return .migrated
        } catch {
            return .failed("The store could not be moved: \(error.localizedDescription).")
        }
    }

    // MARK: - Steps

    /// Copies the database and every sidecar into a private directory.
    ///
    /// All or nothing: a sidecar that fails to copy throws, and the caller
    /// removes the whole directory. Half a copy never gets a name anything
    /// else looks for.
    private static func stage(_ source: URL, into staging: URL, as stagedStore: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: staging.path) {
            try manager.removeItem(at: staging)
        }
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        for suffix in [""] + sidecarSuffixes {
            let from = URL(fileURLWithPath: source.path + suffix)
            guard manager.fileExists(atPath: from.path) else { continue }
            try manager.copyItem(at: from, to: URL(fileURLWithPath: stagedStore.path + suffix))
        }
    }

    /// Moves a proven copy into place.
    ///
    /// Sidecars first and the database last, because the database file is the
    /// one every later launch tests for: interrupted before the last move there
    /// is no destination and the migration simply runs again, and interrupted
    /// after it every file is already there.
    private static func promote(from stagedStore: URL, to destination: URL) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else {
            throw Failure(reason: "a store is already at the destination")
        }
        guard manager.fileExists(atPath: stagedStore.path) else {
            throw Failure(reason: "the staged copy has no database file")
        }
        // Sidecars orphaned by an earlier interrupted promotion belong to a
        // database that is not there; keeping them beside a new one would mix
        // two stores.
        for suffix in sidecarSuffixes {
            try? manager.removeItem(at: URL(fileURLWithPath: destination.path + suffix))
        }
        for suffix in sidecarSuffixes + [""] {
            let from = URL(fileURLWithPath: stagedStore.path + suffix)
            guard manager.fileExists(atPath: from.path) else { continue }
            try manager.moveItem(at: from, to: URL(fileURLWithPath: destination.path + suffix))
        }
    }

    /// Moves a store aside, with its sidecars, and returns where it went.
    ///
    /// Moved rather than deleted on purpose. Whatever is wrong with it, it is
    /// the only copy of whatever it does contain.
    @discardableResult
    static func quarantine(_ store: URL) throws -> URL {
        let manager = FileManager.default
        let stamp = filenameStamp(Date())
        let folder = store.deletingLastPathComponent()
            .appending(path: quarantineDirectoryName)
            .appending(path: "\(stamp)-\(UUID().uuidString.prefix(8))")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let moved = folder.appending(path: store.lastPathComponent)
        for suffix in [""] + sidecarSuffixes {
            let from = URL(fileURLWithPath: store.path + suffix)
            guard manager.fileExists(atPath: from.path) else { continue }
            try manager.moveItem(at: from, to: URL(fileURLWithPath: moved.path + suffix))
        }
        try? manager.removeItem(at: recordURL(for: store))
        return moved
    }

    /// Opens a store the way the app opens it and reads back what it holds.
    ///
    /// Opening it *is* the validation. A truncated database, a schema this
    /// build cannot read and a file that is not a database at all all fail
    /// here, before anything has been moved.
    static func inventory(of store: URL) -> Inventory? {
        guard FileManager.default.fileExists(atPath: store.path) else { return nil }
        do {
            let configuration = ModelConfiguration(schema: GlowStore.schema, url: store)
            let container = try ModelContainer(for: GlowStore.schema, configurations: configuration)
            let context = ModelContext(container)
            let habits = try context.fetch(FetchDescriptor<Habit>())
            let completions = try context.fetch(FetchDescriptor<Completion>())
            return Inventory(
                habitIDs: Set(habits.map(\.id)),
                completionIDs: Set(completions.map(\.id))
            )
        } catch {
            log.error("A store did not open: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Sortable, legal in a file name, and built per call: a shared
    /// `ISO8601DateFormatter` is not `Sendable`, and this is not on any path
    /// that runs often enough to care.
    private static func filenameStamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func writeRecord(
        for destination: URL, source: URL, inventory: Inventory, unmerged: URL? = nil
    ) {
        let record = Record(
            source: source.lastPathComponent,
            habitCount: inventory.habitCount,
            completionCount: inventory.completionCount,
            unmergedSource: unmerged?.path
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(record).write(to: recordURL(for: destination), options: .atomic)
        } catch {
            // The copy is in place and correct; only the note saying so is
            // missing. The next launch re-proves it and writes this again.
            log.error(
                "The migration record could not be written: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
