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
/// A widget already on a home screen arrives with the intent's default —
/// `rows` nil. Large keeps the app's order, including spacers; medium now skips
/// automatic spacers so its measured capacity is spent on real habits (#496).
/// A configured spacer is still honoured. The kind string is unchanged: it is
/// what an existing widget is keyed by.
struct GlowWidget: Widget {
    let kind = WidgetKind.week.rawValue

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectWeekLayoutIntent.self,
            provider: WeekProvider()
        ) { entry in
            WidgetContentInset { WeekWidgetView(entry: entry) }
                // Declared with `containerBackground`, never `.background`, and
                // left removable. That is the whole contract: a widget does not
                // choose whether it has a background — the person does, by
                // setting the Home Screen to Default, Tinted or Clear. Under
                // Tinted or Clear the system renders in `accented` mode, drops
                // this background and substitutes glass.
                //
                // Under Default the system composites this background itself,
                // and a *material* here is blurred from the wallpaper the way a
                // system widget's is — `.clear` measures as black there, a
                // colour is flat, a material is glass. Since 2026-09-05 the
                // container is `GlowPalette.widgetContainer`: the app's dark
                // glass with nothing of the app's behind it, so a little of the
                // wallpaper reads through (`widgetSurface` explains the pair).
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
    /// **The gallery's picture, and the only fixture in the app** (#365).
    ///
    /// A placeholder is drawn before anything has been loaded, so it cannot
    /// read the store — and it used to say so by returning `.empty` with no
    /// month half at all, which the week families drew as "No habits yet" and
    /// the small family drew as "Data unavailable", per its own rule that a
    /// missing month half can only be a provider bug. Neither is a preview of
    /// anything. See `WidgetPreviewSample`.
    func placeholder(in context: Context) -> WeekEntry {
        WidgetDisplaySize.record(context.displaySize, for: context.family)
        return previewEntry(at: context.family)
    }

    func snapshot(for configuration: SelectWeekLayoutIntent, in context: Context) async -> WeekEntry {
        WidgetDisplaySize.record(context.displaySize, for: context.family)
        // A widget view cannot rely on a SwiftUI task completing before
        // WidgetKit archives its still image. Prepare the current tile here,
        // off the main actor, so #507's body fix keeps the Home Screen's HDR.
        _ = await GlowImageCache.shared.prepare(peak: GlowSettings.peakHeadroom)

        // **The gallery gets the sample, not the store** (#365). Measured in
        // the simulator: this is called with `isPreview` true once per install
        // of the extension, and the render is cached — re-opening the gallery
        // does not call it again. The commonest moment for that one call is
        // before the app has ever been launched, when the container does not
        // exist yet, so a store read froze "Data unavailable" into all three
        // pages for the life of the install. That is this issue, both halves:
        // the large family's stale drawing is the same cache, holding a
        // picture an older build took.
        if context.isPreview {
            let entry = previewEntry(at: context.family)
            // What was served, not what was read — nothing was read. The small
            // family's content is the month half, so its count would always be
            // the week half's zero. Counts only, per `WidgetTrace`.
            let served = context.family == .systemSmall ? "month" : entry.habits.traced
            WidgetTrace.record(
                "week snapshot: preview=true, family=\(context.family), sample=\(served)"
            )
            return entry
        }
        if context.family == .systemSmall {
            return monthEntry(for: configuration)
        }
        let entry = loadEntry(for: configuration)
        // `isPreview` is what separates the gallery's call from a placed
        // widget's, and it is still recorded on this branch so a preview
        // arriving here at all would be visible. Counts only, per
        // `WidgetTrace`.
        WidgetTrace.record(
            "week snapshot: preview=\(context.isPreview), habits=\(entry.habits.traced)"
        )
        return entry
    }

    /// The sample week, or the sample month at the small family.
    ///
    /// Today is still `WeekCalendar.today()`: the render is taken at install
    /// time and correct then, and a fixed weekday would be wrong immediately.
    /// The rest day is read here, at the provider — the boundary — and handed
    /// down, the way every other preference a rule depends on is.
    private func previewEntry(at family: WidgetFamily) -> WeekEntry {
        let today = WeekCalendar.today()
        let week = WeekCalendar.week(containing: today)
        let restDay = WeekPreferences.restDay
        guard family != .systemSmall else {
            return WeekEntry(
                date: today,
                week: week,
                habits: .empty,
                month: .loaded(
                    WidgetPreviewSample.month(containing: today, restDay: restDay)
                )
            )
        }
        return WeekEntry(
            date: today,
            week: week,
            habits: .loaded(
                WidgetPreviewSample.rows(in: week, today: today, restDay: restDay)
            )
        )
    }

    /// One still entry and a midnight refresh — plus, after a tap, the few
    /// cross-fade frames that ride inside the reload the tap already paid for.
    func timeline(
        for configuration: SelectWeekLayoutIntent, in context: Context
    ) async -> Timeline<WeekEntry> {
        WidgetDisplaySize.record(context.displaySize, for: context.family)
        // See `snapshot`: the provider is the asynchronous boundary where a
        // widget's current HDR tile must be ready before its view is archived.
        _ = await GlowImageCache.shared.prepare(peak: GlowSettings.peakHeadroom)

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
        // Timed, and recorded on the way out with the time in it (#121). The
        // stamp on a trace line is when the provider *finished*, so without
        // the load it cannot be told apart from when WidgetKit *called* —
        // and those are a slow store and a late reload, which are different
        // problems.
        // **The small family is the month** (#322): one habit's calendar,
        // chosen by the intent's `habit` or falling back to the first offered
        // (`MonthStore.month`). One still entry and the same midnight policy
        // the month kind always had — no burst frames, because the month's
        // tap acknowledgement is the dot itself. The trace keeps the month
        // vocabulary so the lines read continuously across the merge.
        if context.family == .systemSmall {
            let loadStarted = Date()
            let entry = monthEntry(for: configuration)
            WidgetTrace.record(
                "month timeline: family=\(context.family), habit=\(WidgetTrace.tag(configuration.habit?.id))"
                    + ", load \(WidgetTrace.elapsed(since: loadStarted))"
            )
            let now = Date()
            let midnight = WeekCalendar.calendar.date(
                byAdding: .day, value: 1, to: WeekCalendar.day(now)
            ) ?? now.addingTimeInterval(3600)
            return Timeline(entries: [entry], policy: .after(midnight))
        }

        let loadStarted = Date()
        let entry = loadEntry(for: configuration)
        let load = WidgetTrace.elapsed(since: loadStarted)
        let now = Date()
        let midnight = WeekCalendar.calendar.date(
            byAdding: .day, value: 1, to: WeekCalendar.day(now)
        ) ?? now.addingTimeInterval(3600)
        // Whether the stored choice reaches the provider is exactly what the
        // device check needs to see, and the same question about the month
        // widget's single entity was only ever settled on hardware — see
        // `MonthWidgetConfig`. Counts and ids only, see `WidgetTrace`.
        // The family is in the line because #321 needed it and it was not
        // there: "is any placed week widget being served at Small" cannot be
        // answered by a trace that never says which family a timeline was
        // built for.
        // The frame WidgetKit actually gave this widget, beside the size
        // `WidgetMetrics` assumes for it (#367). Those are two different
        // claims: one is measured per render on the device in front of you,
        // the other is a constant authored against a 6.1" phone. How many rows
        // fit is computed from the first and asserted from the second, so a
        // disagreement between them is invisible until a row goes missing —
        // which is what it is being read to find out. Sizes only, no names,
        // per `WidgetTrace`.
        let assumed = WidgetMetrics.size(of: context.family)
        WidgetTrace.record(
            "week timeline: family=\(context.family), rows=\(configuration.rows.map { "\($0.count)" } ?? "unset")"
                + ", display \(WidgetTrace.size(context.displaySize))"
                + " vs assumed \(WidgetTrace.size(assumed))"
        )

        // A tap animates. Everything else renders still.
        // Reduce Motion travels with the burst rather than being read here.
        // `UIAccessibility.isReduceMotionEnabled` is main-actor isolated and a
        // `TimelineProvider` is not; the intent that records the note is, so
        // the value is read where it is safe to read. See `WidgetBurst.record`.
        guard let burst = WidgetBurst.pending(now: now), !WidgetBurst.reduceMotion else {
            let why = WidgetBurst.pending(now: now) == nil ? "none pending" : "suppressed by reduce motion"
            // Now *and* the next midnight, so the row re-flows on the day
            // turning over whether or not WidgetKit has obliged the reload
            // (#345).
            let still = [entry] + (nextMidnightEntry(after: entry).map { [$0] } ?? [])
            GlowLog.widget.notice(
                "timeline: \(still.count, privacy: .public) entries, still (burst \(why, privacy: .public))"
            )
            WidgetTrace.record(
                "timeline: \(still.count) entries, still (burst \(why), load \(load))"
            )
            return Timeline(entries: still, policy: .after(midnight))
        }

        // The cross-fade's few stills and the settle, dated from *this moment*
        // rather than from the tap (#267) — the frames used to be offset from
        // the tap and the spent ones dropped, which charged the animation for
        // reload latency instead of merely delaying it. The decision is
        // `WidgetBurst.timeline(renderedAt:)`, which is pure and tested; this
        // is the part that turns it into entries.
        //
        // The fade itself is still a handful of stills on purpose. It used to
        // sample the app's closing spring at 40fps — seventeen entries — and
        // on a real home screen it read as a stutter rather than a snap:
        // entries do not arrive at the rate they were sampled at. See
        // WidgetBurst and docs/glow.md.
        //
        // The burst rides inside this one timeline, so it spends no reloads of
        // its own, and nothing follows the settle until the day turns over.
        let entries = WidgetBurst.timeline(renderedAt: now).map { step in
            WeekEntry(
                date: step.date,
                week: entry.week,
                habits: entry.habits,
                rowsAreConfigured: entry.rowsAreConfigured,
                burstHabit: step.progress == nil ? nil : burst.habitID,
                burstDay: step.progress == nil ? nil : burst.day,
                progress: step.progress ?? 1
            )
        } + (nextMidnightEntry(after: entry).map { [$0] } ?? [])
        // The lag is no longer subtracted from the fade, so this line is now
        // purely a measurement — and the one #121 is about. Every tap reports
        // how long WidgetKit took to ask.
        let lag = String(format: "%.2f", now.timeIntervalSince(burst.startedAt))
        let summary = "timeline: \(entries.count) entries, burst \(burst.habitID.uuidString) \(lag)s after the tap, load \(load)"
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
            // Three outcomes, not two (#282): the store's answer arrives typed
            // and stays typed, so a failed container renders "unavailable"
            // rather than the new-user empty state.
            habits: WeekWidgetStore.rows(chosen: configuration.rows?.map(\.id), in: week),
            rowsAreConfigured: configuration.rows?.isEmpty == false
        )
    }

    /// The same row, dated at the next local midnight (#345).
    ///
    /// **A reload policy is a request; an entry is a guarantee.** The timeline
    /// already asked to be rebuilt `.after(midnight)`, and that stays — but
    /// WidgetKit decides when it obliges, and until it does the Home Screen
    /// keeps rendering the last entry it was given. That entry says today is
    /// yesterday, so the row draws yesterday's open ring on a day it is no
    /// longer actionable, which is the one thing SPEC §1 says light must never
    /// do. A second entry costs nothing and needs no reload to be right.
    ///
    /// The record does not change at midnight; *today* does. `WeekSpans` is a
    /// function of both, so the same habits at a later date re-flow on their
    /// own: the division moves and any newly dead rep appears. The week is
    /// recomputed rather than carried over, because a midnight that crosses the
    /// week start is exactly the case where reusing it would draw the new day
    /// against the old seven columns.
    private func nextMidnightEntry(after entry: WeekEntry) -> WeekEntry? {
        guard let midnight = WeekCalendar.calendar.date(
            byAdding: .day, value: 1, to: WeekCalendar.day(entry.date)
        ) else { return nil }
        return WeekEntry(
            date: midnight,
            week: WeekCalendar.week(containing: midnight),
            habits: entry.habits,
            rowsAreConfigured: entry.rowsAreConfigured
        )
    }

    /// The small family's entry: the week halves empty, the month half loaded.
    /// `today()` rather than `Date()` for the same reason the old month
    /// provider read it (#204): which month to draw and which dot is open are
    /// claims about "today", not timestamps.
    private func monthEntry(for configuration: SelectWeekLayoutIntent) -> WeekEntry {
        let today = WeekCalendar.today()
        return WeekEntry(
            date: today,
            week: WeekCalendar.week(containing: today),
            habits: .empty,
            month: MonthStore.month(of: configuration.habit?.id, containing: today)
        )
    }
}

extension StoreRead where Value == [HabitSnapshot] {
    /// A count for a trace line, or the outcome when there is none. Never a
    /// name, per `WidgetTrace`.
    var traced: String {
        switch self {
        case .loaded(let habits): "\(habits.count)"
        case .empty: "0"
        case .unavailable: "unavailable"
        }
    }
}

@main
struct GlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        GlowWidget()
        // Not a home screen widget: the Dynamic Island's two seconds when a
        // goal is met. A Live Activity is declared in the same bundle. See #58.
        GoalPopActivity()
    }
}

/// The content inset, applied where the family is known.
///
/// A `WidgetConfiguration`'s content closure cannot read `\.widgetFamily`
/// itself, and the inset is not one number any more: the small family is inset
/// evenly because the month is a centred block of cells, where the week's 6/14
/// is an optical adjustment for a row that starts with a label column (#331,
/// and node `234:11216`). So the read happens in a view that has an
/// environment to read it from.
private struct WidgetContentInset<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.leading, WidgetMetrics.padLeading(for: family))
            .padding(.trailing, WidgetMetrics.padTrailing(for: family))
            .padding(.top, WidgetMetrics.padTop)
            .padding(.bottom, WidgetMetrics.padBottom)
            .containerBackground(for: .widget) {
                GlowPalette.widgetContainer(reduceTransparency: reduceTransparency)
            }
    }
}
