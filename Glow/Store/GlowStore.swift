import Foundation
import SwiftData

/// Process-local reconciliation for a write performed through the AppIntent's
/// peer SwiftData container. SwiftData keeps the file coherent but does not
/// invalidate another container's already-fetched view state (#145, #465).
enum StoreChange {
    static let fromIntent = Notification.Name("com.georgklock.glow.store-change-from-intent")
    /// Every successful live-store save, including a completion made in the
    /// app's own context. Views that retain a bounded projection use this to
    /// invalidate it without refetching on unrelated redraws (#478).
    static let committed = Notification.Name("com.georgklock.glow.store-change-committed")
}

/// The one container, shared by the app and the widget.
///
/// Both processes open the same file in the App Group container — the app
/// read-write, the widget extension read-only (`makeReadOnlyContainer`). The
/// writes a widget tap causes go through `MarkHabitIntent`, which runs in the
/// **app's** process (`LiveActivityIntent`, #58) but opens a container and
/// context of its own, per tap. SwiftData keeps the *file* consistent; what it
/// does not do is keep another context's already-fetched objects up to date,
/// and that sentence used to say only the first half.
///
/// **Neither direction is automatic**, so both are wired explicitly:
///
///  - The app tells the widget, by following every write with a timeline
///    reload. See `WidgetRefresh`.
///  - The intent posts `StoreChange.fromIntent` after every verdict. Live app
///    surfaces that render its rows advance a local revision and fetch their
///    bounded snapshots again (#465).
///
/// That signal is a redraw bridge, not a context merge. A `Habit` fetched by
/// the app can still hold a cached `completions` relationship while the
/// intent's context deletes one of its rows — the crash #145 fixed by making
/// `Habit.liveCompletions` fetch through its context instead. Nothing should
/// read a cached relationship array and assume a peer container kept it live.
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
