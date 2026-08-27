import AppIntents
import SwiftUI
import WidgetKit

/// The month widget: one habit's calendar month, small family only.
///
/// The week widget answers "how is this week going" and the Today widget
/// answers "what is left today"; this one answers "am I actually keeping this
/// up", which otherwise lives buried in Settings and shows every habit at
/// once. One habit, chosen per widget — the Today small widget's model — so
/// several of these can sit on one home screen showing different habits.
///
/// Small only, deliberately: one habit's month is one thing to say, and a
/// bigger frame would only invite a second.
struct MonthWidget: Widget {
    let kind = WidgetKind.month.rawValue

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectWeeklyHabitIntent.self,
            provider: MonthProvider()
        ) { entry in
            MonthWidgetView(entry: entry)
                .padding(.leading, WidgetMetrics.padLeading)
                .padding(.trailing, WidgetMetrics.padTrailing)
                .padding(.vertical, WidgetMetrics.padVertical)
                // The same background contract as every other widget here:
                // declared with `containerBackground`, left removable, black
                // only under the Default appearance. See GlowWidget.swift.
                .containerBackground(GlowPalette.widgetBackground, for: .widget)
                // Today's dot acts in place through its intent; everything
                // else opens the app on This Week — the weekly cadence, seen
                // over a longer run.
                .widgetURL(DeepLink.week)
        }
        .contentMarginsDisabled()
        // Name, sentence and families all from `WidgetKind`, because the
        // Widgets tab says the same three things about this widget and a
        // second copy of them is a page that eventually describes a widget
        // the gallery does not have (#210).
        .configurationDisplayName(WidgetKind.month.galleryName)
        .description(WidgetKind.month.summary)
        .supportedFamilies(WidgetKind.month.families)
    }
}

struct MonthProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MonthEntry {
        MonthEntry(date: Date(), habit: .empty)
    }

    func snapshot(for configuration: SelectWeeklyHabitIntent, in context: Context) async -> MonthEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectWeeklyHabitIntent, in context: Context) async -> Timeline<MonthEntry> {
        let now = Date()
        // Built before the line is written, and timed, so this means the same
        // thing the week widget's line means (#121). It used to record on
        // entry, before any store work — which made the two providers'
        // timestamps incomparable in exactly the comparison they were being
        // used for.
        let loadStarted = Date()
        let built = entry(for: configuration)
        WidgetTrace.record(
            "month timeline: family=\(context.family), habit=\(WidgetTrace.tag(configuration.habit?.id))"
                + ", load \(WidgetTrace.elapsed(since: loadStarted))"
        )
        // One entry, and a refresh at midnight: the open dot is defined as
        // "today", and a month only ever changes at a midnight too. Writes
        // reload the timelines explicitly, same as the other widgets.
        return Timeline(
            entries: [built],
            policy: .after(MonthStore.midnight(after: now))
        )
    }

    private func entry(for configuration: SelectWeeklyHabitIntent) -> MonthEntry {
        // One habit, one month. Both halves of that used to be paid for
        // whether or not they were drawn: every weekly habit's whole history
        // was projected, and all but one of the results thrown away. See #135.
        //
        // `today()` rather than `Date()` (#204): `MonthWidgetView` reads
        // `entry.date` as today — which month to draw, and which dot is the
        // open one — so this is a place "today" is established, not a
        // timestamp. The timeline's refresh policy above still runs off the
        // real clock, because when to reload is not a thing the override has
        // an opinion about.
        let now = WeekCalendar.today()
        return MonthEntry(
            date: now,
            habit: MonthStore.month(of: configuration.habit?.id, containing: now)
        )
    }
}
