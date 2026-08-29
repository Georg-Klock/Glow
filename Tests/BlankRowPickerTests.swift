import Foundation
import SwiftData
import Testing
@testable import Glow

/// #371: the week widget's picker offers habits and no blank rows.
///
/// `WeekWidgetConfig`'s own note says a blank row is "the whole reason someone
/// opens this picker" — #172 found the app's clustering puts a gap where a
/// medium widget's cut falls, and #188 built the picker so a widget can place
/// its own gap instead of the app being reordered around it. Nothing was
/// asserting that, so the promise and the behaviour were free to disagree.
///
/// These read the real store through the same `container:` seam
/// `StoreReadStateTests` uses. A mock would be the mirror copy the working
/// rules forbid, and it would pass whatever the picker did.
@MainActor
@Suite("The picker offers blank rows")
struct BlankRowPickerTests {
    private func container(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: GlowStore.schema,
            configurations: ModelConfiguration(schema: GlowStore.schema, url: url)
        )
    }

    /// A habit, a blank row, a habit — the shape #172 describes, where the gap
    /// falls between two things somebody wants to see.
    private func seedRowsAroundASpacer(_ container: ModelContainer) throws {
        let context = ModelContext(container)
        let made = TestCalendar.date(2026, 8, 1)
        context.insert(Habit(
            name: "Alpha", icon: "figure.run", frequency: .daily,
            createdAt: made, sortOrder: 0
        ))
        context.insert(Habit(
            name: "", icon: "", frequency: .daily,
            createdAt: made, sortOrder: 1, isSpacer: true
        ))
        context.insert(Habit(
            name: "Beta", icon: "book", frequency: .daily,
            createdAt: made, sortOrder: 2
        ))
        try context.save()
    }

    @Test("The store offers the blank row along with the habits")
    func rowNamesKeepsTheSpacer() throws {
        let url = URL.temporaryDirectory.appending(path: "blank-rows-\(UUID()).store")
        let store = try container(at: url)
        try seedRowsAroundASpacer(store)

        let rows = try WeekWidgetStore.rowNames(container: store)

        #expect(rows.count == 3, "the picker was offered \(rows.count) rows, not three")
        #expect(rows.map(\.isSpacer) == [false, true, false],
                "the blank row is not in the offered rows, or is not in the app's order")
    }

    /// The entity is what the system's picker actually draws, so the name has
    /// to survive the mapping as well as the fetch — and two blank rows have to
    /// arrive distinguishable, which is the property #371 turns on.
    @Test("Blank rows reach the picker numbered, and no two share a title")
    func blankRowsAreNumbered() async throws {
        let url = URL.temporaryDirectory.appending(path: "blank-rows-\(UUID()).store")
        let store = try container(at: url)
        let context = ModelContext(store)
        let made = TestCalendar.date(2026, 8, 1)
        context.insert(Habit(
            name: "Alpha", icon: "figure.run", frequency: .daily,
            createdAt: made, sortOrder: 0
        ))
        context.insert(Habit(
            name: "", icon: "", frequency: .daily,
            createdAt: made, sortOrder: 1, isSpacer: true
        ))
        context.insert(Habit(
            name: "", icon: "", frequency: .daily,
            createdAt: made, sortOrder: 2, isSpacer: true
        ))
        try context.save()

        // The real query, through its container seam. Building the entities
        // here instead would assert against a copy of the numbering rather than
        // against the code the picker calls.
        let entities = try await WeekRowQuery(container: store).suggestedEntities()
        let titles = entities.map { String(localized: $0.displayRepresentation.title) }

        #expect(titles == ["Alpha", "Blank Row 1", "Blank Row 2"],
                "the picker was offered \(titles)")
        #expect(Set(titles).count == titles.count,
                "two rows share a title, which is what hid them: \(titles)")
    }
}
