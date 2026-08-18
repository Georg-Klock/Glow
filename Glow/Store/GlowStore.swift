import Foundation
import SwiftData

/// The one container, shared by the app and the widget.
///
/// Both processes open the same file in the App Group container. SwiftData
/// handles the concurrent access; what it cannot do is tell the widget that the
/// app just wrote something, which is why every write is followed by a timeline
/// reload.
enum GlowStore {
    static let schema = Schema([Habit.self, Completion.self])

    static func makeContainer() throws -> ModelContainer {
        StoreLocation.migrateIfNeeded()
        let configuration = ModelConfiguration(schema: schema, url: StoreLocation.url)
        return try ModelContainer(for: schema, configurations: configuration)
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
        return try? ModelContainer(for: schema, configurations: configuration)
    }
}
