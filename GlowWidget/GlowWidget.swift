import SwiftData
import SwiftUI
import UIKit
import WidgetKit

/// The home screen widget: the same week, the same rule, one tap.
///
/// It glows. That was written off as impossible before the widget existed —
/// WidgetKit renders in a separate process and archives the result, so the
/// pipeline was assumed to flatten HDR — and the assumption was never tested.
/// It draws the same PQ image the app does, on the same headroom. See
/// docs/glow.md.
///
/// What it keeps beyond that is the part that matters daily: logging a habit
/// without opening anything.
struct GlowWidget: Widget {
    let kind = "GlowWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeekProvider()) { entry in
            WeekWidgetView(entry: entry)
                .padding(.leading, WidgetMetrics.padLeading)
                .padding(.trailing, WidgetMetrics.padTrailing)
                .padding(.vertical, WidgetMetrics.padVertical)
                // No background at all. The design draws a container and this
                // followed it for a while; on a real home screen it read as a
                // panel sitting on the wallpaper rather than marks floating on
                // it, which is the opposite of the point. iOS 17 and later still
                // require a container background to be declared — declaring it
                // clear is how you opt out, not omitting it.
                .containerBackground(.clear, for: .widget)
        }
        // WidgetKit's own margins are close to the design's but not equal, and
        // they are applied inside the container — so the padding above only
        // means what the file says once they are switched off.
        .contentMarginsDisabled()
        .configurationDisplayName("Glow Up: This Week")
        .description("Your habits for the week. Tap today's slot to log it.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WeekEntry: TimelineEntry {
    let date: Date
    let week: Week
    let habits: [HabitSnapshot]
    /// The habit whose completion is mid-animation, if any.
    var burstHabit: UUID?
    /// How far the solid fill has risen over the glow, 0 through 1.
    var coverage: Double = 1
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

    /// How long a breath takes, and how finely it is sampled.
    ///
    /// Deliberately bounded: this is an experiment in whether WidgetKit honours
    /// sub-minute entries at all. Every entry is free, but the reload at the end
    /// of the window is not — widgets get a limited refresh budget per day, and
    /// spending it on a pulse would leave the widget stale by evening. If the
    /// pulse works, the window length is the dial to trade against that budget.
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        // One entry, and a refresh at midnight. The open slot is defined as
        // "today", so the day rolling over is the only moment the widget goes
        // stale on its own. Everything else is a write, and writes reload the
        // timeline explicitly.
        //
        // It briefly did more than this: a breathing pulse baked into a series
        // of sub-second entries. It worked — measured on an iPhone 14 Pro, the
        // entry clock advanced in step with the pulse, so WidgetKit renders
        // entries far finer than the minute it is usually credited with. It
        // still came out, because entries are free and reloads are not. See
        // docs/glow.md.
        let entry = loadEntry()
        let now = Date()
        let midnight = WeekCalendar.calendar.date(
            byAdding: .day, value: 1, to: WeekCalendar.day(now)
        ) ?? now.addingTimeInterval(3600)

        // A tap animates. Everything else renders still.
        guard let burst = WidgetBurst.pending(now: now), !reduceMotion else {
            let why = WidgetBurst.pending(now: now) == nil ? "none pending" : "suppressed by reduce motion"
            GlowLog.widget.notice("timeline: 1 entry, still (burst \(why, privacy: .public))")
            WidgetTrace.record("timeline: 1 entry, still (burst \(why))")
            completion(Timeline(entries: [entry], policy: .after(midnight)))
            return
        }

        var entries: [WeekEntry] = []
        var t = now.timeIntervalSince(burst.startedAt)
        while t < WidgetBurst.duration {
            entries.append(WeekEntry(
                date: burst.startedAt.addingTimeInterval(t),
                week: entry.week,
                habits: entry.habits,
                burstHabit: burst.habitID,
                coverage: WidgetBurst.coverage(at: t)
            ))
            t += WidgetBurst.step
        }
        // Settle, and then nothing until the day turns over. The burst rides
        // inside this one timeline, so it spends no reloads of its own.
        entries.append(WeekEntry(
            date: burst.startedAt.addingTimeInterval(WidgetBurst.duration),
            week: entry.week,
            habits: entry.habits
        ))
        let lag = String(format: "%.2f", now.timeIntervalSince(burst.startedAt))
        let summary = "timeline: \(entries.count) entries, burst \(burst.habitID.uuidString) starting \(lag)s in"
        GlowLog.widget.notice("\(summary, privacy: .public)")
        WidgetTrace.record(summary)
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }

    /// Pulsing content is what Reduce Motion exists to switch off, and an
    /// extension can read it directly.
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }


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
