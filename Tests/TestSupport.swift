import Foundation
@testable import Glow

/// A calendar pinned to UTC, so a test asserting "Monday" means the same thing
/// on this machine and on a CI runner in another timezone.
enum TestCalendar {
    static var monday: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    /// 2026-08-17 is a Monday, so the fixtures read the way they are written.
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return monday.date(from: components) ?? .distantPast
    }
}

extension HabitSnapshot {
    static func fixture(
        name: String = "Read",
        frequency: Frequency = .daily,
        completedDays: Set<Date> = []
    ) -> HabitSnapshot {
        HabitSnapshot(
            id: UUID(),
            name: name,
            icon: "📖",
            frequency: frequency,
            accent: .teal,
            completedDays: completedDays
        )
    }
}
