import Foundation
import SwiftData
import Testing
@testable import Glow

/// #283: the stored shape is a declared version, and editing it is a decision.
///
/// `GlowSchemaV1` froze the shape shipping today. These tests hold the code
/// to the freeze: the model metadata the schema derives — entity names,
/// every attribute with its value type, every relationship with its delete
/// rule — is compared against the shape V1 declared, written out here as
/// literals. A model edit that changes stored metadata fails this suite, and
/// the failure's answer is a version decision — a `GlowSchemaV2` with a
/// migration stage, or an explicit finding that the store is unchanged —
/// never a silent lean on lightweight inference.
///
/// The literals are the point, not a redundancy: a test that derived the
/// expectation from the model would move with every edit and gate nothing.
@MainActor
@Suite("Schema contract")
struct SchemaContractTests {
    private var schema: Schema { Schema(versionedSchema: GlowSchemaV1.self) }

    @Test("V1 is version 1.0.0 and both model types are in it")
    func versionAndModels() {
        #expect(GlowSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(Set(schema.entities.map(\.name)) == ["Habit", "Completion"])
        // The production schema is built from V1, so every container and the
        // migration's candidate validation are on the declared version.
        #expect(GlowStore.schema.entities.count == schema.entities.count)
    }

    @Test("The plan declares exactly the shipped versions, newest last")
    func planIsV1Only() {
        #expect(GlowMigrationPlan.schemas.count == 1)
        #expect(GlowMigrationPlan.schemas.last == GlowSchemaV1.self)
        // No stages: one version has no path to migrate along. V2's stage
        // lands here, in the same change that adds V2 to `schemas`.
        #expect(GlowMigrationPlan.stages.isEmpty)
    }

    private func entity(_ name: String) throws -> Schema.Entity {
        try #require(schema.entities.first { $0.name == name })
    }

    /// Attribute name → the spelling of its value type, for comparison
    /// against the frozen literals.
    private func attributes(of entity: Schema.Entity) -> [String: String] {
        entity.attributes.reduce(into: [:]) { table, attribute in
            table[attribute.name] = String(describing: attribute.valueType)
        }
    }

    @Test("Habit's stored shape is exactly what V1 froze")
    func habitShape() throws {
        let habit = try entity("Habit")
        #expect(attributes(of: habit) == [
            "id": "UUID",
            "name": "String",
            "icon": "String",
            "isDaily": "Bool",
            "timesPerWeek": "Int",
            "timesPerDay": "Int",
            "accentRaw": "String",
            "createdAt": "Date",
            "sortOrder": "Int",
            "isSpacer": "Bool",
        ])

        let completions = try #require(
            habit.relationships.first { $0.name == "completions" }
        )
        #expect(habit.relationships.count == 1)
        // The cascade is part of the contract: it is what deletes a habit's
        // history with it.
        #expect(completions.deleteRule == .cascade)
    }

    @Test("Completion's stored shape is exactly what V1 froze")
    func completionShape() throws {
        let completion = try entity("Completion")
        #expect(attributes(of: completion) == [
            "id": "UUID",
            "day": "Date",
            "dayKey": "String",
            "demoSessionID": "Optional<UUID>",
        ])

        let habit = try #require(
            completion.relationships.first { $0.name == "habit" }
        )
        #expect(completion.relationships.count == 1)
        #expect(habit.deleteRule == .nullify)
    }

    // MARK: - The opens

    /// A store written the way every TestFlight build wrote one — a plain
    /// container with no plan — opened through `GlowStore.container(at:)`,
    /// which is the exact call both production opens now share (#283). The
    /// floor this proves is the documented one: the shape V1 froze is the
    /// shape those builds wrote, so adopting the plan changes nothing a
    /// returning store can feel.
    @Test("Both containers open a pre-plan store through the plan, unchanged")
    func plannedOpenReadsAPrePlanStore() throws {
        let url = TestStore.url()
        defer { TestStore.discard(url) }

        // Written as the previous builds wrote it: no versioned schema, no
        // plan. TestStore is that spelling.
        let habitID = UUID()
        let writer = try TestStore.writable(at: url)
        let habit = Habit(
            id: habitID, name: "Gym", icon: "figure.run", frequency: .daily,
            createdAt: TestCalendar.date(2026, 8, 1), sortOrder: 0
        )
        writer.insert(habit)
        let completion = Completion(
            day: TestCalendar.date(2026, 8, 18), habit: habit,
            calendar: TestCalendar.monday
        )
        writer.insert(completion)
        habit.completions?.append(completion)
        try writer.save()

        // The app's open: writable, through the plan.
        let opened = try GlowStore.container(at: url)
        let context = ModelContext(opened)
        let habits = try context.fetch(FetchDescriptor<Habit>())
        #expect(habits.map(\.id) == [habitID])
        #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 1)

        // The widget's open: read-only, through the same plan, same file.
        let readOnly = try GlowStore.container(at: url, readOnly: true)
        let readContext = ModelContext(readOnly)
        #expect(try readContext.fetch(FetchDescriptor<Habit>()).map(\.id) == [habitID])

        // And again — a plan with one version must be a no-op every time.
        let reopened = try GlowStore.container(at: url)
        #expect(
            try ModelContext(reopened).fetchCount(FetchDescriptor<Completion>()) == 1
        )
    }

    @Test("A fresh store created through the plan reads back what it holds")
    func plannedOpenCreates() throws {
        let url = TestStore.url()
        defer { TestStore.discard(url) }

        let container = try GlowStore.container(at: url)
        let context = ModelContext(container)
        let habit = Habit(
            name: "Read", icon: "book", frequency: .timesPerWeek(3),
            createdAt: TestCalendar.date(2026, 8, 1), sortOrder: 0
        )
        context.insert(habit)
        try context.save()

        let readOnly = try GlowStore.container(at: url, readOnly: true)
        let names = try ModelContext(readOnly).fetch(FetchDescriptor<Habit>()).map(\.name)
        #expect(names == ["Read"])
    }
}
