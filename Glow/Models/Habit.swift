import Foundation
import SwiftData

/// A tracked habit.
///
/// Stored shape notes, both aimed at a later CloudKit sync being a change of
/// configuration rather than a migration: every property has a default value,
/// there are no unique constraints, and the relationship is optional. CloudKit
/// requires all three, and retrofitting them means rewriting the store.
///
/// `Frequency` is stored as its two parts rather than as an encoded enum so the
/// column is queryable and readable in the store, and so a future schema change
/// does not hinge on an enum's Codable representation.
@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = HabitSymbol.default
    var isDaily: Bool = true
    /// Only meaningful when `isDaily` is false.
    var timesPerWeek: Int = 3
    /// Retained so the stored schema does not change. The app committed to a
    /// single colour, so nothing reads this; dropping the column would be a
    /// migration for no gain.
    var accentRaw: String = ""
    var createdAt: Date = Date.distantPast
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Completion.habit)
    var completions: [Completion]? = []

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        frequency: Frequency,
        createdAt: Date,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.completions = []
        self.frequency = frequency
    }

    var frequency: Frequency {
        get { isDaily ? .daily : Frequency(timesPerWeek: timesPerWeek) }
        set {
            switch newValue {
            case .daily:
                isDaily = true
            case .timesPerWeek(let count):
                isDaily = false
                timesPerWeek = count
            }
        }
    }

    var completedDays: Set<Date> {
        Set((completions ?? []).map(\.day))
    }

    func snapshot() -> HabitSnapshot {
        HabitSnapshot(
            id: id,
            name: name,
            icon: icon,
            frequency: frequency,
            completedDays: completedDays
        )
    }
}
