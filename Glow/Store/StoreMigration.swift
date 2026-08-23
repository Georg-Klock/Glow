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
    ///
    /// **Format 2 is the day-identity migration** (#130). The two fields it
    /// added are optional rather than defaulted, and that is not a style
    /// choice: Swift's synthesized decoder does not apply a property's default
    /// value to a missing key, so a non-optional addition would make every
    /// format-1 record on every phone fail to decode and read as absent.
    /// Optional decodes cleanly from the records already written, and nil there
    /// means exactly what it says — this store predates the backfill.
    struct Record: Codable, Equatable, Sendable {
        static let currentFormat = 2

        /// The version of the day-identity backfill this store has been
        /// through. Nil, or a value below `currentDayFormat`, means the store
        /// may still hold completions whose day is inferred rather than
        /// recorded — which reads the same but cannot be queried on.
        static let currentDayFormat = 1

        var format: Int = currentFormat
        var dayFormat: Int?
        /// How many legacy completions have been given a `DayID`, cumulative.
        var stampedDays: Int?
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

    // MARK: - Day identities

    /// What the day-identity backfill did.
    enum DayStamping: Equatable, Sendable {
        /// Every completion already carries its own day.
        case notNeeded
        /// This many legacy rows were given one.
        case stamped(Int)
        /// Nothing was written. The store is exactly as it was, and reads still
        /// answer correctly — see `Completion.dayID`.
        case failed(String)
    }

    /// Writes down the day each pre-#130 completion belongs to.
    ///
    /// **This does not change what the app shows, and that is the design.**
    /// `Completion.dayID` infers a legacy row's day with the same rule this
    /// uses, so a store reads identically before, during and after. What the
    /// backfill buys is a day that is *recorded* rather than derived: queryable
    /// in the store, visible to a person opening the file, and — once every row
    /// has one — a `dayKey` predicate that #135 can push into SQLite instead of
    /// filtering in memory.
    ///
    /// That makes the riskiest change in the store the one that can be
    /// abandoned at any point:
    ///
    /// - **Nothing is destroyed.** `Completion.day` is untouched, so the
    ///   original observation survives and a later build with a better
    ///   inference can redo this from it.
    /// - **Nothing is created or removed.** Only an empty column is filled, and
    ///   the row count is checked either side of the save to say so.
    /// - **It resumes rather than restarts.** The work is defined as "rows with
    ///   no key", so a run cut off half-way leaves the rest for the next
    ///   launch, and a completed run finds nothing to do.
    /// - **A failure is survivable.** It returns rather than throws, and the
    ///   caller opens the store anyway, because a store whose days are inferred
    ///   is a store that works.
    ///
    /// Safe to call from either process on every launch. On a stamped store it
    /// is one fetch that returns nothing.
    @discardableResult
    static func stampDayIdentities(
        in context: ModelContext,
        storeAt destination: URL? = nil
    ) -> DayStamping {
        do {
            let legacy = try context.fetch(
                FetchDescriptor<Completion>(predicate: #Predicate { $0.dayKey == "" })
            )
            let totalBefore = try context.fetchCount(FetchDescriptor<Completion>())

            guard !legacy.isEmpty else {
                note(dayIdentitiesFor: destination, stamped: 0)
                return .notNeeded
            }

            for completion in legacy {
                completion.dayKey = DayID.recovered(fromLegacyMidnight: completion.day).text
            }

            // Proved before the save, not after it: a row that came out of the
            // rule without a readable key would be a row whose day this build
            // just made worse, and rolling back is only possible while the
            // change is still pending.
            guard legacy.allSatisfy({ DayID($0.dayKey) != nil }) else {
                context.rollback()
                return .failed("a day identity did not read back")
            }

            try context.save()

            // And again from the store, because "the objects in memory look
            // right" is what the partial copy in #131 also looked like.
            let remaining = try context.fetchCount(
                FetchDescriptor<Completion>(predicate: #Predicate { $0.dayKey == "" })
            )
            let totalAfter = try context.fetchCount(FetchDescriptor<Completion>())
            guard remaining == 0, totalAfter == totalBefore else {
                return .failed(
                    "the store still holds \(remaining) undated rows of \(totalAfter)"
                )
            }

            note(dayIdentitiesFor: destination, stamped: legacy.count)
            log.info("Gave \(legacy.count, privacy: .public) completions a recorded day")
            return .stamped(legacy.count)
        } catch {
            context.rollback()
            log.error(
                "Day identities were not recorded: \(error.localizedDescription, privacy: .public)"
            )
            return .failed(error.localizedDescription)
        }
    }

    /// Annotates an existing migration record with what the backfill did.
    ///
    /// Only annotates. A store with no record has never been migrated from
    /// anywhere — a fresh install — and inventing one here would hand `run` a
    /// reason to skip work it has not done. The backfill needs no marker to be
    /// correct: it is defined by what is still unstamped, not by what a file
    /// says.
    private static func note(dayIdentitiesFor destination: URL?, stamped: Int) {
        guard let destination, var record = readRecord(for: destination) else { return }
        guard record.dayFormat != Record.currentDayFormat || stamped > 0 else { return }
        record.format = Record.currentFormat
        record.dayFormat = Record.currentDayFormat
        record.stampedDays = (record.stampedDays ?? 0) + stamped
        write(record, for: destination)
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
        write(
            Record(
                source: source.lastPathComponent,
                habitCount: inventory.habitCount,
                completionCount: inventory.completionCount,
                unmergedSource: unmerged?.path
            ),
            for: destination
        )
    }

    private static func write(_ record: Record, for destination: URL) {
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
