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
    /// Opacity for the glowing layer at this instant.
    ///
    /// A widget cannot run a continuous animation: WidgetKit renders one
    /// snapshot per timeline entry, out of process. So the breath is baked into
    /// the timeline instead — a series of entries a couple of seconds apart,
    /// each carrying the next point on the curve.
    var phase: Double = 1.0
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
    /// TEMPORARY, still exaggerated for testing.
    ///
    /// One-second entries visibly pulsed on device, which is the interesting
    /// result: WidgetKit honours entries far finer than the "one minute
    /// minimum" this is usually described as having. So this pushes further —
    /// quarter-second sampling on a one-second cycle.
    ///
    /// The window stays at 60s deliberately. Entries are cheap and the reload
    /// at the end of the window is what costs refresh budget, so sampling finer
    /// buys smoothness for free; shortening the window would not.
    private static let breathStep: TimeInterval = 0.25
    private static let breathWindow: TimeInterval = 60
    /// Seconds for a full down-and-up cycle.
    private static let breathCycle: Double = 1

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let base = loadEntry()
        let now = Date()

        // The open slot is defined as "today", so the day rolling over is the
        // one moment the widget goes stale on its own. Everything else is a
        // write, and writes reload the timeline explicitly.
        let midnight = WeekCalendar.calendar.date(
            byAdding: .day, value: 1, to: WeekCalendar.day(now)
        ) ?? now.addingTimeInterval(3600)

        guard base.habits.contains(where: { habit in
            WeekGrid.slots(for: habit, in: base.week, today: base.date).contains { $0.state == .open }
        }) else {
            // Nothing is glowing, so nothing needs to breathe. Do not spend the
            // refresh budget on a still image.
            completion(Timeline(entries: [base], policy: .after(midnight)))
            return
        }

        var entries: [WeekEntry] = []
        let steps = Int(Self.breathWindow / Self.breathStep)
        for step in 0...steps {
            let t = Double(step) * Self.breathStep
            // A cosine gives the same ease-in-out shape the app animates with,
            // sampled rather than interpolated.
            let curve = (cos(t / Self.breathCycle * 2 * .pi) + 1) / 2
            let phase = GlowImageView.breathLow + (1.0 - GlowImageView.breathLow) * curve
            entries.append(WeekEntry(
                date: now.addingTimeInterval(t),
                week: base.week,
                habits: base.habits,
                phase: phase
            ))
        }

        let next = min(now.addingTimeInterval(Self.breathWindow), midnight)
        completion(Timeline(entries: entries, policy: .after(next)))
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
