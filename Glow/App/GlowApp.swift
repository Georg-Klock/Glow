import SwiftData
import SwiftUI

@main
struct GlowApp: App {
    /// One container for the whole app. Local only: no CloudKit in v1, though
    /// the model shape is kept sync-ready. See docs/ARCHITECTURE.md.
    private let container: ModelContainer

    init() {
        do {
            container = try GlowStore.makeContainer()
        } catch {
            // A store that cannot open is not recoverable from inside the app,
            // and continuing would silently drop every write.
            fatalError("Could not open the habit store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            WeeklyGridView()
                .tint(GlowPalette.color)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
