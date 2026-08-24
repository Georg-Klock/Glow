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
    static let schema = Schema([Habit.self, Completion.self])

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
        let configuration = ModelConfiguration(schema: schema, url: StoreLocation.url)
        let container = try ModelContainer(for: schema, configurations: configuration)
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
    /// should render an empty state, not crash the extension.
    static func makeReadOnlyContainer() -> ModelContainer? {
        let configuration = ModelConfiguration(
            schema: schema,
            url: StoreLocation.url,
            allowsSave: false
        )
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            WidgetTrace.record("read-only container failed: \(error)")
            return nil
        }
    }
}
