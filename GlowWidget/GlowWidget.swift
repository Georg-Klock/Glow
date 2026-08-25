import AppIntents
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
///
/// **Which rows it shows is a per-widget choice** (#188). All three families,
/// not just the small ones: a person who wants large to show something other
/// than the default set gets the same control as everyone else rather than
/// being assumed never to want it. The intent, entity and query live in the
/// shared sources (`WeekWidgetConfig.swift`) — see the note there; defined only
/// in this target, the stored choice never reaches the provider.
///
/// A widget already on a home screen when this ships arrives with the intent's
/// default — `rows` nil — which is the case that keeps the app's own order, so
/// the change is invisible to anyone who does not open the sheet. The kind
/// string is unchanged for the same reason: it is what an existing widget is
/// keyed by.
struct GlowWidget: Widget {
    let kind = WidgetKind.week.rawValue

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectWeekLayoutIntent.self,
            provider: WeekProvider()
        ) { entry in
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
        // Name, sentence and families all from `WidgetKind`. The Widgets tab
        // shows the same three families and says the same words about them, so
        // there is one list rather than two that can disagree (#210).
        //
        // The name arrives as a `String` property rather than an interpolated
        // literal, and that is the whole of #254: an interpolated literal here
        // is a `LocalizedStringKey` carrying formatted text, which WidgetKit
        // traps on while evaluating this very body.
        .configurationDisplayName(WidgetKind.week.galleryName)
        .description(WidgetKind.week.summary)
        .supportedFamilies(WidgetKind.week.families)
    }
}

struct WeekProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        let today = WeekCalendar.today()
        return WeekEntry(
            date: today,
            week: WeekCalendar.week(containing: today),
            habits: []
        )
    }

    func snapshot(for configuration: SelectWeekLayoutIntent, in context: Context) async -> WeekEntry {
        let entry = loadEntry(for: configuration)
        // Traced to answer one question the trace could not: whether the widget
        // gallery's preview is stale because WidgetKit never asks us, or
        // because it asks and then shows something older. `isPreview` is what
        // separates the gallery's call from a placed widget's. Counts only, per
        // `WidgetTrace`.
        WidgetTrace.record(
            "week snapshot: preview=\(context.isPreview), habits=\(entry.habits.count)"
        )
        return entry
    }

    /// One still entry and a midnight refresh — plus, after a tap, the few
    /// cross-fade frames that ride inside the reload the tap already paid for.
    func timeline(
        for configuration: SelectWeekLayoutIntent, in context: Context
    ) async -> Timeline<WeekEntry> {
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
        let entry = loadEntry(for: configuration)
        let now = Date()
        let midnight = WeekCalendar.calendar.date(
            byAdding: .day, value: 1, to: WeekCalendar.day(now)
        ) ?? now.addingTimeInterval(3600)
        // Whether the stored choice reaches the provider is exactly what the
        // device check needs to see, and the same question about the month
        // widget's single entity was only ever settled on hardware — see
        // `MonthWidgetConfig`. Counts and ids only, see `WidgetTrace`.
        WidgetTrace.record(
            "week timeline: rows=\(configuration.rows.map { "\($0.count)" } ?? "unset")"
        )

        // A tap animates. Everything else renders still.
        // Reduce Motion travels with the burst rather than being read here.
        // `UIAccessibility.isReduceMotionEnabled` is main-actor isolated and a
        // `TimelineProvider` is not; the intent that records the note is, so
        // the value is read where it is safe to read. See `WidgetBurst.record`.
        guard let burst = WidgetBurst.pending(now: now), !WidgetBurst.reduceMotion else {
            let why = WidgetBurst.pending(now: now) == nil ? "none pending" : "suppressed by reduce motion"
            GlowLog.widget.notice("timeline: 1 entry, still (burst \(why, privacy: .public))")
            WidgetTrace.record("timeline: 1 entry, still (burst \(why))")
            return Timeline(entries: [entry], policy: .after(midnight))
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
        return Timeline(entries: entries, policy: .after(midnight))
    }


    /// Not main-actor isolated: a timeline provider is called on whatever queue
    /// WidgetKit chooses, and the context `WeekWidgetStore` creates is local to
    /// the call, so it never crosses a boundary.
    ///
    /// The fetch moved to `WeekWidgetStore` (#188) so the configuration picker
    /// and this render read one descriptor. Two copies of "the week-shaped
    /// rows, in the user's order" would be two that could drift, and the
    /// picker offering a row the widget cannot draw is exactly the drift that
    /// would not be noticed.
    private func loadEntry(for configuration: SelectWeekLayoutIntent) -> WeekEntry {
        let today = WeekCalendar.today()
        let week = WeekCalendar.week(containing: today)
        return WeekEntry(
            date: today,
            week: week,
            habits: WeekWidgetStore.rows(chosen: configuration.rows?.map(\.id), in: week)
        )
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
