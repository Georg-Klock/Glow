import SwiftData
import SwiftUI
import WidgetKit

/// The home screen widget: the same week, the same rule, one tap.
///
/// It cannot glow. WidgetKit renders in a separate process and archives the
/// result, and that pipeline does not carry HDR, so today's open slot is drawn
/// in flat bright colour instead. This was called out as a non-goal in the spec
/// before the widget existed, and it still holds: the real glow lives in the
/// app. What the widget keeps is the part that matters daily, which is being
/// able to log a habit without opening anything.
struct GlowWidget: Widget {
    let kind = "GlowWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeekProvider()) { entry in
            WeekWidgetView(entry: entry)
                // Fully transparent, so the widget disappears into a dark
                // wallpaper and reads as slots floating on the home screen
                // rather than as a card sitting on it. iOS 17 and later still
                // require a container background to be declared; declaring it
                // clear is how you opt out rather than omitting it.
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Glow Up: This Week")
        .description("Your habits for the week. Tap today's slot to log it.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WeekEntry: TimelineEntry {
    let date: Date
    let week: Week
    let habits: [HabitSnapshot]
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        let today = WeekCalendar.day(Date())
        return WeekEntry(
            date: today,
            week: WeekCalendar.week(containing: today),
            habits: []
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        // One entry, and a refresh at midnight. The open slot is defined as
        // "today", so the only scheduled moment the widget goes stale on its
        // own is the day rolling over. Everything else is a write, and writes
        // reload the timeline explicitly.
        let entry = loadEntry()
        let midnight = WeekCalendar.calendar.date(
            byAdding: .day, value: 1, to: WeekCalendar.day(Date())
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }

    /// Not main-actor isolated: `TimelineProvider` is called on whatever queue
    /// WidgetKit chooses, and the context created here is local to this call,
    /// so it never crosses a boundary.
    private func loadEntry() -> WeekEntry {
        let today = WeekCalendar.day(Date())
        let week = WeekCalendar.week(containing: today)

        guard let container = GlowStore.makeReadOnlyContainer() else {
            return WeekEntry(date: today, week: week, habits: [])
        }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)])
        let habits = (try? context.fetch(descriptor))?.map { $0.snapshot() } ?? []

        return WeekEntry(date: today, week: week, habits: habits)
    }
}

@main
struct GlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        GlowWidget()
    }
}
