import Foundation
import SwiftData
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

/// The App Group's week preferences, set for the length of one test and put
/// back afterwards.
///
/// `WeekPreferences.firstWeekday` and `restDay` live in `UserDefaults` — one
/// value for the whole process, shared by every suite. Five suites write them
/// and several more read them through `WeekGrid`, `WeekSpans`, `WeekDots`,
/// `MonthGrid` and `HabitStore.toggleCompletion`, which is a hazard if any two
/// of those ever run at once.
///
/// **Two things stop that, and the first one is the real one.** The scheme runs
/// tests sequentially (`parallelizable: false`, stated in project.yml with the
/// measurement that established it), so no two tests overlap at all. The lock
/// below is the belt to that brace: it serialises the *writers* against each
/// other, so turning parallel testing on would leave only the readers to fix
/// rather than everything. See #105.
///
/// Recursive, because a suite that nests one of these inside another is
/// reasonable and should not deadlock.
enum TestPreferences {
    private static let gate = NSRecursiveLock()

    /// Runs `body` with the week's preferences pinned, whatever they were.
    ///
    /// `restDay` is not optional-by-omission: passing nothing means *no rest
    /// day*, explicitly, rather than "leave whatever was there". A test that
    /// assumes a clean week should say so.
    /// `@discardableResult` because the common use is to pin the week's
    /// preferences around a body that asserts inside itself and returns
    /// nothing worth reading.
    @discardableResult
    static func withWeek<T>(
        firstWeekday: Int? = nil,
        restDay: Int? = nil,
        _ body: () throws -> T
    ) rethrows -> T {
        gate.lock()
        let previousFirst = WeekPreferences.firstWeekday
        let previousRest = WeekPreferences.restDay
        defer {
            WeekPreferences.firstWeekday = previousFirst
            WeekPreferences.restDay = previousRest
            gate.unlock()
        }
        WeekPreferences.firstWeekday = firstWeekday ?? WeekPreferences.defaultFirstWeekday
        WeekPreferences.restDay = restDay
        return try body()
    }

    /// The weekday number of one column of a week, which is what `restDay`
    /// wants — every suite that sets one was converting by hand.
    static func weekday(
        ofColumn column: Int, in week: Week, calendar: Calendar = TestCalendar.monday
    ) -> Int {
        calendar.component(.weekday, from: week.days[column])
    }
}

/// A store on a real file, for the tests that need to *fail* a write.
///
/// An in-memory container cannot be opened twice, and a save that throws is the
/// only honest way to ask what a half-finished seeding leaves behind. So the
/// file is opened writable to set the scene, opened again read-only to run the
/// write that cannot land, and opened writable a third time to see what
/// survived — which is also the relaunch, since nothing carries over between
/// them but the file.
@MainActor
enum TestStore {
    static func url() -> URL {
        URL.temporaryDirectory.appending(path: "glow-tests-\(UUID().uuidString).store")
    }

    static func writable(at url: URL) throws -> ModelContext {
        ModelContext(
            try ModelContainer(
                for: GlowStore.schema,
                configurations: ModelConfiguration(schema: GlowStore.schema, url: url)
            )
        )
    }

    /// The same file, opened so that every `save()` through it throws.
    static func readOnly(at url: URL) throws -> ModelContext {
        ModelContext(
            try ModelContainer(
                for: GlowStore.schema,
                configurations: ModelConfiguration(
                    schema: GlowStore.schema, url: url, allowsSave: false
                )
            )
        )
    }

    /// The store and the two files SwiftData keeps beside it.
    static func discard(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}

/// Defaults that take a write and do not keep it — the flag that never landed,
/// which is one half of every "the store and the record disagree" failure.
final class ForgetfulDefaults: UserDefaults, @unchecked Sendable {
    override func set(_ value: Any?, forKey defaultName: String) {}
    override func set(_ value: Bool, forKey defaultName: String) {}
}

extension HabitSnapshot {
    static func fixture(
        name: String = "Read",
        frequency: Frequency = .daily,
        completedDays: Set<Date> = [],
        isSpacer: Bool = false
    ) -> HabitSnapshot {
        HabitSnapshot(
            id: UUID(),
            name: name,
            icon: "📖",
            frequency: frequency,
            completedDays: completedDays,
            isSpacer: isSpacer
        )
    }
}
