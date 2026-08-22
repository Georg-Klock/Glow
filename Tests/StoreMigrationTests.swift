import Foundation
import SwiftData
import Testing
@testable import Glow

/// Migration tests run against real files.
///
/// In-memory stores cannot express what #131 is about: the bug is that a
/// SQLite store is three files and the old copy took them one at a time. Every
/// fixture here is therefore a store on disk with a live write-ahead log beside
/// it, and every failure is produced by the filesystem rather than by a hook —
/// an unreadable sidecar, a database file that is only a prefix of one, a
/// sidecar left behind by a promotion that was cut short.
@Suite("Store migration", .serialized)
@MainActor
struct StoreMigrationTests {
    // MARK: - Fixtures

    /// A directory of its own per test, removed afterwards.
    private func inTemporaryDirectory<T>(_ body: (URL) throws -> T) rethrows -> T {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "glow-migration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return try body(root)
    }

    private func openContainer(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: GlowStore.schema,
            configurations: ModelConfiguration(schema: GlowStore.schema, url: url)
        )
    }

    /// Writes habits and completions into a store and returns what it now holds.
    ///
    /// The container is *not* closed. A cleanly closed SQLite connection folds
    /// its write-ahead log into the database and deletes it, which would make
    /// every fixture here a single file and quietly remove the thing under
    /// test. An app killed by the system leaves the log; so does this.
    @discardableResult
    private func seed(
        _ container: ModelContainer, habits: Int, daysEach: Int, from day: Date = Date()
    ) throws -> StoreMigration.Inventory {
        let context = ModelContext(container)
        for index in 0..<habits {
            let habit = Habit(
                name: "Habit \(index)",
                icon: "drop.fill",
                frequency: .daily,
                createdAt: day,
                sortOrder: index
            )
            context.insert(habit)
            for offset in 0..<daysEach {
                let completion = Completion(
                    day: day.addingTimeInterval(Double(-offset) * 86_400), habit: habit
                )
                context.insert(completion)
            }
        }
        try context.save()
        return StoreMigration.Inventory(
            habitIDs: Set(try context.fetch(FetchDescriptor<Habit>()).map(\.id)),
            completionIDs: Set(try context.fetch(FetchDescriptor<Completion>()).map(\.id))
        )
    }

    /// Opens a store, writes into it, and lets it go again — a later session of
    /// the app, in other words. Returns everything the store then holds.
    @discardableResult
    private func writeInto(
        _ url: URL, habits: Int, daysEach: Int
    ) throws -> StoreMigration.Inventory {
        let container = try openContainer(at: url)
        return try seed(container, habits: habits, daysEach: daysEach)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func sidecar(_ store: URL, _ suffix: String) -> URL {
        URL(fileURLWithPath: store.path + suffix)
    }

    private func quarantineFolder(beside store: URL) -> URL {
        store.deletingLastPathComponent().appending(path: StoreMigration.quarantineDirectoryName)
    }

    // MARK: - The whole store moves, log included

    @Test("A store, its write-ahead log and its shared memory all arrive")
    func migratesEveryFile() throws {
        try inTemporaryDirectory { root in
            let source = root.appending(path: "default.store")
            let destination = root.appending(path: "Glow.store")
            let container = try openContainer(at: source)
            let seeded = try seed(container, habits: 3, daysEach: 5)

            #expect(exists(sidecar(source, "-wal")), "the fixture needs a live log")

            #expect(StoreMigration.run(from: source, to: destination) == .migrated)

            #expect(StoreMigration.inventory(of: destination) == seeded)
            // The source is left where it is. Reclaiming it is a later,
            // separate decision.
            #expect(exists(source))
            #expect(StoreMigration.readRecord(for: destination)?.habitCount == 3)
            #expect(StoreMigration.readRecord(for: destination)?.completionCount == 15)
            _ = container
        }
    }

    @Test("Writes that only exist in the log survive the move")
    func walOnlyWritesSurvive() throws {
        try inTemporaryDirectory { root in
            let source = root.appending(path: "default.store")
            let destination = root.appending(path: "Glow.store")
            let container = try openContainer(at: source)
            let seeded = try seed(container, habits: 4, daysEach: 6)

            // The evidence that this fixture is worth anything: the database
            // file *by itself* is behind. That copy is precisely what the old
            // migration produced when a sidecar failed.
            let baseOnly = root.appending(path: "base-only.store")
            try FileManager.default.copyItem(at: source, to: baseOnly)
            let partial = StoreMigration.inventory(of: baseOnly)
            #expect(partial != seeded, "the log holds nothing, so this proves nothing")
            #expect(partial.map { seeded.covers($0) } == true)

            #expect(StoreMigration.run(from: source, to: destination) == .migrated)
            #expect(StoreMigration.inventory(of: destination) == seeded)
            _ = container
        }
    }

    // MARK: - The bug

    @Test("A destination that is only part of the source is replaced, not adopted")
    func partialDestinationIsRepaired() throws {
        try inTemporaryDirectory { root in
            let source = root.appending(path: "default.store")
            let destination = root.appending(path: "Glow.store")
            let container = try openContainer(at: source)
            let seeded = try seed(container, habits: 4, daysEach: 6)

            // Exactly what the old code left behind: the database copied, the
            // log not. It opens; it is simply missing the recent writes.
            try FileManager.default.copyItem(at: source, to: destination)
            let adoptedByTheOldCode = try #require(StoreMigration.inventory(of: destination))
            #expect(adoptedByTheOldCode != seeded)

            let outcome = StoreMigration.run(from: source, to: destination)
            guard case .repaired(let quarantine) = outcome else {
                Issue.record("expected a repair, got \(outcome)")
                return
            }

            #expect(StoreMigration.inventory(of: destination) == seeded)
            // The displaced copy is moved aside, never deleted.
            #expect(exists(quarantine))
            #expect(StoreMigration.inventory(of: quarantine) == adoptedByTheOldCode)
            #expect(exists(source))
            _ = container
        }
    }

    @Test("A copy interrupted partway adopts nothing and leaves the source readable")
    func interruptedCopyAdoptsNothing() throws {
        try inTemporaryDirectory { root in
            let source = root.appending(path: "default.store")
            let destination = root.appending(path: "Glow.store")
            let container = try openContainer(at: source)
            let seeded = try seed(container, habits: 3, daysEach: 4)

            // Fail the copy at the sidecar, which is the step the old code
            // logged and carried on from.
            let log = sidecar(source, "-wal")
            try #require(exists(log))
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: log.path)
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644], ofItemAtPath: log.path
                )
            }

            let outcome = StoreMigration.run(from: source, to: destination)
            guard case .failed = outcome else {
                Issue.record("expected a failure, got \(outcome)")
                return
            }

            // Nothing was adopted, nothing was left half-built, and the next
            // launch has something to retry from.
            #expect(!exists(destination))
            #expect(!exists(sidecar(destination, "-wal")))
            #expect(!exists(root.appending(path: StoreMigration.stagingDirectoryName)))
            #expect(!exists(StoreMigration.recordURL(for: destination)))

            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: log.path
            )
            #expect(StoreMigration.inventory(of: source) == seeded)
            _ = container
        }
    }

    @Test("A sidecar left by an interrupted promotion does not block the next attempt")
    func straySidecarDoesNotBlockTheRetry() throws {
        try inTemporaryDirectory { root in
            let source = root.appending(path: "default.store")
            let destination = root.appending(path: "Glow.store")
            let container = try openContainer(at: source)
            let seeded = try seed(container, habits: 2, daysEach: 3)

            // Sidecars are promoted before the database file, so this is the
            // state a promotion cut short leaves: a log belonging to a database
            // that is not there.
            try Data("not a log".utf8).write(to: sidecar(destination, "-wal"))
            try Data("not shared memory".utf8).write(to: sidecar(destination, "-shm"))

            #expect(StoreMigration.run(from: source, to: destination) == .migrated)
            #expect(StoreMigration.inventory(of: destination) == seeded)
            _ = container
        }
    }

    // MARK: - Doing it twice

    @Test("Migrating twice is a no-op and never overwrites later writes")
    func migrationIsIdempotent() throws {
        try inTemporaryDirectory { root in
            let source = root.appending(path: "default.store")
            let destination = root.appending(path: "Glow.store")
            let container = try openContainer(at: source)
            let seeded = try seed(container, habits: 2, daysEach: 2)

            #expect(StoreMigration.run(from: source, to: destination) == .migrated)

            // The person keeps using the app. The second launch must not put
            // the older store back over the top of that.
            let afterUse = try writeInto(destination, habits: 1, daysEach: 1)
            #expect(afterUse.covers(seeded))

            #expect(StoreMigration.run(from: source, to: destination) == .notNeeded)
            #expect(StoreMigration.inventory(of: destination) == afterUse)
            _ = container
        }
    }

    @Test("A complete store left by an earlier build is adopted and recorded")
    func completeDestinationIsAdopted() throws {
        try inTemporaryDirectory { root in
            let source = root.appending(path: "default.store")
            let destination = root.appending(path: "Glow.store")
            let container = try openContainer(at: source)
            let seeded = try seed(container, habits: 2, daysEach: 2)

            // A store migrated before the record existed: everything the source
            // holds, plus what has happened since.
            #expect(StoreMigration.run(from: source, to: destination) == .migrated)
            let afterUse = try writeInto(destination, habits: 1, daysEach: 1)
            #expect(afterUse.covers(seeded))
            try FileManager.default.removeItem(at: StoreMigration.recordURL(for: destination))

            #expect(StoreMigration.run(from: source, to: destination) == .adopted)
            #expect(StoreMigration.inventory(of: destination) == afterUse)
            #expect(StoreMigration.readRecord(for: destination) != nil)
            #expect(!exists(quarantineFolder(beside: destination)))
            _ = container
        }
    }

    @Test("Two stores that each hold what the other does not are both kept")
    func divergentStoresAreBothKept() throws {
        try inTemporaryDirectory { root in
            let source = root.appending(path: "default.store")
            let destination = root.appending(path: "Glow.store")
            let sourceContainer = try openContainer(at: source)
            let inSource = try seed(sourceContainer, habits: 2, daysEach: 2)

            let destinationContainer = try openContainer(at: destination)
            let inDestination = try seed(destinationContainer, habits: 3, daysEach: 1)

            #expect(!inSource.covers(inDestination))
            #expect(!inDestination.covers(inSource))

            #expect(StoreMigration.run(from: source, to: destination) == .diverged(source: source))

            // Neither is deleted, neither is overwritten, and the record says
            // where the one that was not merged in still is.
            #expect(StoreMigration.inventory(of: destination) == inDestination)
            #expect(exists(source))
            #expect(StoreMigration.readRecord(for: destination)?.unmergedSource == source.path)
            _ = (sourceContainer, destinationContainer)
        }
    }

    // MARK: - Nothing to do, and nothing that can be done

    @Test("A fresh install migrates nothing and creates nothing")
    func freshInstallIsUntouched() throws {
        try inTemporaryDirectory { root in
            let source = root.appending(path: "default.store")
            let destination = root.appending(path: "Glow.store")

            #expect(StoreMigration.run(from: source, to: destination) == .notNeeded)

            #expect(!exists(destination))
            #expect(!exists(StoreMigration.recordURL(for: destination)))
            let left = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(left.isEmpty)
        }
    }

    @Test("A store that cannot be opened with nothing to restore from fails loudly")
    func unopenableStoreWithNoSourceFails() throws {
        try inTemporaryDirectory { root in
            let source = root.appending(path: "default.store")
            let destination = root.appending(path: "Glow.store")
            let rubbish = Data("this is not a database".utf8)
            try rubbish.write(to: destination)

            let outcome = StoreMigration.run(from: source, to: destination)
            guard case .failed = outcome else {
                Issue.record("expected a failure, got \(outcome)")
                return
            }
            // Failing means changing nothing.
            let onDisk = try Data(contentsOf: destination)
            #expect(onDisk == rubbish)
            #expect(!exists(StoreMigration.recordURL(for: destination)))
        }
    }

    @Test("An unreadable store is quarantined rather than deleted when there is a source")
    func unopenableDestinationIsQuarantined() throws {
        try inTemporaryDirectory { root in
            let source = root.appending(path: "default.store")
            let destination = root.appending(path: "Glow.store")
            let container = try openContainer(at: source)
            let seeded = try seed(container, habits: 2, daysEach: 2)

            let rubbish = Data("this is not a database".utf8)
            try rubbish.write(to: destination)

            let outcome = StoreMigration.run(from: source, to: destination)
            guard case .repaired(let quarantine) = outcome else {
                Issue.record("expected a repair, got \(outcome)")
                return
            }
            #expect(StoreMigration.inventory(of: destination) == seeded)
            let quarantined = try Data(contentsOf: quarantine)
            #expect(quarantined == rubbish)
            _ = container
        }
    }

    // MARK: - The record

    @Test("A record this build cannot read is treated as absent")
    func futureRecordIsIgnored() throws {
        try inTemporaryDirectory { root in
            let destination = root.appending(path: "Glow.store")
            let record = """
            {"format": 99, "generation": "\(UUID().uuidString)", \
            "migratedAt": "2026-08-22T00:00:00Z", "source": "default.store", \
            "habitCount": 0, "completionCount": 0}
            """
            try Data(record.utf8).write(to: StoreMigration.recordURL(for: destination))

            #expect(StoreMigration.readRecord(for: destination) == nil)
        }
    }

    @Test("The paths the app migrates between are the two the store has ever had")
    func locationsAreTheRealOnes() {
        #expect(StoreLocation.legacyURL.lastPathComponent == "default.store")
        #expect(StoreLocation.url.lastPathComponent == StoreLocation.fileName)
    }
}
