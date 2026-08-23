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
    let kind = WidgetKind.week.rawValue

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeekProvider()) { entry in
            WeekWidgetView(entry: entry)
                .padding(.leading, WidgetMetrics.padLeading)
                .padding(.trailing, WidgetMetrics.padTrailing)
                .padding(.vertical, WidgetMetrics.padVertical)
                // Declared with `containerBackground`, never `.background`, and
                // left removable. That is the whole contract: a widget does not
                // choose whether it has a background — the person does, by
                // setting the Home Screen to Default, Tinted or Clear. Under
                // Tinted or Clear the system renders in `accented` mode, drops
                // this background and substitutes glass.
                //
                // Black is what it is under Default, where the background is
                // composited into the snapshot opaquely and every alpha resolves
                // against black. `.clear` measures as black there — which it
                // does, and which was wrongly written up in this file as proof
                // that a home screen widget cannot be transparent. It is not a
                // platform limit; it is one appearance out of three.
                //
                // `containerBackgroundRemovable` is deliberately untouched, and
                // not for the reason this comment used to give. It claimed that
                // passing false opts out of glass — buying black in every
                // appearance at the price of StandBy, the iPad Lock Screen
                // gallery and foreground tinting. Only the price is real. On
                // iOS 26 the flag governs contexts that have no background at
                // all; the Home Screen's Tinted and Clear appearances are a
                // restyling, and they substitute glass whether it is true or
                // false. Measured in the simulator, 2026-08-21, on a widget
                // rendering fresh content — the same panel under both values.
                //
                // Nor can the background be smuggled in as content. A black
                // image behind the view, carrying the `.fullColor` accented
                // rendering mode that keeps the glow tile from being flattened,
                // is dropped as completely as the declared background is: the
                // probe was run in red and never appeared. Under Tinted and
                // Clear the system keeps the silhouette of the marks and
                // nothing else. See #53.
                //
                // Two things the design file specifies for this container are
                // deliberately not reproduced, and a render diff will show both
                // as differences rather than regressions:
                //
                //  - **Figma's `GLASS` effect** — radius 4, refraction 0.8,
                //    depth 20, light at −45°. SwiftUI has no equivalent;
                //    `Material` and `.glassEffect` reproduce none of the
                //    refraction, dispersion or directional light. In a flat
                //    export it shows as the faint hairline along the top-left
                //    corner arc.
                //  - **A 30pt corner radius**, because iOS masks a widget to
                //    its own continuous-corner squircle regardless. The file's
                //    *interior* corners are plain circular arcs and those are
                //    reproduced.
                .containerBackground(GlowPalette.widgetBackground, for: .widget)
                // The marks act in place through their intents; everything
                // else opens the app on this widget's own screen.
                .widgetURL(DeepLink.week)
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

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        let today = WeekCalendar.today()
        return WeekEntry(
            date: today,
            week: WeekCalendar.week(containing: today),
            habits: []
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(loadEntry())
    }

    /// One still entry and a midnight refresh — plus, after a tap, the few
    /// cross-fade frames that ride inside the reload the tap already paid for.
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
        // Reduce Motion travels with the burst rather than being read here.
        // `UIAccessibility.isReduceMotionEnabled` is main-actor isolated and a
        // `TimelineProvider` is not; the intent that records the note is, so
        // the value is read where it is safe to read. See `WidgetBurst.record`.
        guard let burst = WidgetBurst.pending(now: now), !WidgetBurst.reduceMotion else {
            let why = WidgetBurst.pending(now: now) == nil ? "none pending" : "suppressed by reduce motion"
            GlowLog.widget.notice("timeline: 1 entry, still (burst \(why, privacy: .public))")
            WidgetTrace.record("timeline: 1 entry, still (burst \(why))")
            completion(Timeline(entries: [entry], policy: .after(midnight)))
            return
        }

        // The cross-fade's few stills, skipping any the reload latency has
        // already spent. This used to sample the app's closing spring at
        // 40fps — seventeen entries — and on a real home screen it read as a
        // stutter rather than a snap: entries do not arrive at the rate they
        // were sampled at. See WidgetBurst and docs/glow.md.
        var entries: [WeekEntry] = []
        let elapsed = now.timeIntervalSince(burst.startedAt)
        for frame in WidgetBurst.frames where frame.offset >= elapsed {
            entries.append(WeekEntry(
                date: burst.startedAt.addingTimeInterval(frame.offset),
                week: entry.week,
                habits: entry.habits,
                burstHabit: burst.habitID,
                progress: frame.progress
            ))
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


    /// Not main-actor isolated: `TimelineProvider` is called on whatever queue
    /// WidgetKit chooses, and the context created here is local to this call,
    /// so it never crosses a boundary.
    private func loadEntry() -> WeekEntry {
        let today = WeekCalendar.today()
        let week = WeekCalendar.week(containing: today)

        guard let container = GlowStore.makeReadOnlyContainer() else {
            return WeekEntry(date: today, week: week, habits: [])
        }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Habit>(
            predicate: Habit.weekly,
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        // Bounded to the week it draws (#135). A home screen widget reloading
        // every time a completion lands was reading every completion of every
        // habit to fill in seven columns.
        let habits = Habit.snapshots(
            of: (try? context.fetch(descriptor)) ?? [], within: week.dayIDs()
        )

        return WeekEntry(date: today, week: week, habits: habits)
    }
}

@main
struct GlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        GlowWidget()
        MonthWidget()
        // Not a home screen widget: the Dynamic Island's two seconds when a
        // goal is met. A Live Activity is declared in the same bundle. See #58.
        GoalPopActivity()
    }
}
