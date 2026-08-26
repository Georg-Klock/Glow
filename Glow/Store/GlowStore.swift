import Foundation
import SwiftData

/// The one container, shared by the app and the widget.
///
/// Both processes open the same file in the App Group container. SwiftData
/// keeps the *file* consistent; what it does not do is keep either process's
/// already-fetched objects up to date, and that sentence used to say only the
/// first half.
///
/// **Neither direction is automatic**, and only one of them was wired up:
///
///  - The app tells the widget, by following every write with a timeline
///    reload. See `WidgetRefresh`.
///  - Nothing tells the app when the *widget* writes. A `Habit` the app fetched
///    earlier keeps a cached `completions` array, and the widget's process can
///    delete a row out from under it — which crashed on the next render until
///    `Habit.liveCompletions` stopped trusting the cache (#145).
///
/// The complete fix is a cross-process change notification, and whether
/// SwiftData exposes persistent history the way Core Data does is not
/// established here. Until it is, nothing should read a cached relationship
/// array and assume its rows still exist.
enum GlowStore {
    /// Built from the versioned declaration, not from a bare model list
    /// (#283): every reader of this property — both containers here, the
    /// migration's candidate validation, the tests' stores — is thereby on
    /// the schema `GlowMigrationPlan` names, and there is no second spelling
    /// to drift.
    static let schema = Schema(versionedSchema: GlowSchemaV1.self)

    /// The read failed — thrown where a caller can throw (the entity
    /// queries), carrying a stable sentence and nothing else. Never a habit
    /// name, a path, or the framework's own error text (#282): the underlying
    /// error is logged privately where it happened, and this is what a person
    /// may be shown.
    struct Unreadable: LocalizedError {
        var errorDescription: String? {
            "Glow's data could not be read. Open Glow, then try again."
        }
    }

    /// Opens the one store, migrating an earlier one into place first.
    ///
    /// **Throws rather than opening when the migration could not be completed.**
    /// Opening anyway would create an empty store at the new path while the
    /// person's history sat unreachable at the old one, and the moment they
    /// added a habit to the empty one the two would have diverged for good. A
    /// launch that stops and says so is recoverable; that is not.
    static func makeContainer() throws -> ModelContainer {
        if case .failed(let reason) = StoreLocation.migrateIfNeeded() {
            throw StoreMigration.Failure(reason: reason)
        }
        let container = try container(at: StoreLocation.url)
        // After the file is in place and before anything reads it, but *not*
        // as a condition of opening: a store whose completions still infer
        // their day shows the same history as one that has been through this.
        // Failing here must therefore not stop a launch. See #130.
        StoreMigration.stampDayIdentities(
            in: ModelContext(container), storeAt: StoreLocation.url
        )
        return container
    }

    /// A read-only container for the widget process.
    ///
    /// Returns nil rather than throwing: a widget that cannot read its store
    /// renders *unavailable* (#282), and must not crash the extension. A
    /// store mid-upgrade, or written by a build whose schema this plan does
    /// not reach, fails to open and lands here — never on "No habits yet".
    static func makeReadOnlyContainer() -> ModelContainer? {
        do {
            return try container(at: StoreLocation.url, readOnly: true)
        } catch {
            WidgetTrace.record("read-only container failed: \(error)")
            return nil
        }
    }

    /// The one spelling of a container open, shared by the app's writable
    /// container, the widget's read-only one, and the tests (#283).
    ///
    /// Through the named plan on every open. With one declared version the
    /// plan has nothing to migrate and the open is byte-identical to before;
    /// what it buys is that a future `GlowSchemaV2` upgrades a store by a
    /// reviewable stage rather than by whatever lightweight inference happens
    /// to do — and that the two processes cannot disagree about what shape
    /// the store is, because there is exactly one place the shape is named.
    static func container(at url: URL, readOnly: Bool = false) throws -> ModelContainer {
        // `cloudKitDatabase:` defaults to `.automatic`, which asks SwiftData
        // to find a CloudKit container on its own. `.none` makes local-only
        // this call site's own claim rather than a property of the current
        // signing configuration — and with the opens collapsed into this one
        // spelling, it is said once. `LocalOnlyContractTests` scans for the
        // production `ModelConfiguration` that stops saying it. See #281.
        let configuration = ModelConfiguration(
            schema: schema, url: url, allowsSave: !readOnly,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema, migrationPlan: GlowMigrationPlan.self,
            configurations: configuration
        )
    }
}
