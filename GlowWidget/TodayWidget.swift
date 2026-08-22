import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

/// The Today widget: a habit's day as a ring of arcs, tappable in place.
///
/// Two kinds rather than one configurable kind. Small shows one habit and the
/// person picks which — so several small widgets can sit on one home screen
/// showing different habits. Medium shows the first three per-day habits in
/// the user's own order and offers nothing to configure, because a picker on
/// a widget that ignores it would be a control promising something it does
/// not do. There is no large: three rings already say everything it could.
///
/// The configuration intent, entity and query live in the shared sources
/// (`TodayWidgetConfig.swift`) — see the note there; defined only in this
/// target, the stored choice never reached the provider.
struct TodaySmallWidget: Widget {
    let kind = WidgetKind.todaySmall.rawValue

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectHabitIntent.self,
            provider: TodaySmallProvider()
        ) { entry in
            TodaySmallView(entry: entry)
                // The same background contract as the week widget: declared
                // with `containerBackground`, left removable, black only under
                // the Default appearance. See GlowWidget.swift.
                .containerBackground(GlowPalette.widgetBackground, for: .widget)
                // The ring acts in place through its intent; everything else
                // opens the app on Today.
                .widgetURL(DeepLink.today)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Glow Up: Today")
        .description("One habit's day as a ring. Tap for one more.")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayMediumWidget: Widget {
    let kind = WidgetKind.todayMedium.rawValue

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayMediumProvider()) { entry in
            TodayMediumView(entry: entry)
                .containerBackground(GlowPalette.widgetBackground, for: .widget)
                .widgetURL(DeepLink.today)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Glow Up: Today")
        .description("Your day's rings, up to three. Tap one for one more.")
        .supportedFamilies([.systemMedium])
    }
}

struct TodaySmallProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), habits: [])
    }

    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> TodayEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<TodayEntry> {
        let now = Date()
        // Whether the stored choice reaches the provider is exactly what the
        // device check needs to see, and the simulator could not answer it.
        WidgetTrace.record(
            "today-small timeline: habit=\(WidgetTrace.tag(configuration.habit?.id))"
        )
        return Timeline(
            entries: [entry(for: configuration)],
            policy: .after(TodayStore.midnight(after: now))
        )
    }

    private func entry(for configuration: SelectHabitIntent) -> TodayEntry {
        let all = TodayStore.perDayHabits()
        // A freshly placed, never-configured widget shows the first habit —
        // something real rather than a "choose habit" placeholder. A chosen
        // habit that was deleted shows the empty state instead, rather than
        // silently becoming a different habit.
        let shown: [DayRingSnapshot]
        if let chosen = configuration.habit {
            shown = all.filter { $0.id == chosen.id }
        } else {
            shown = Array(all.prefix(1))
        }
        return TodayEntry(date: Date(), habits: shown)
    }
}

struct TodayMediumProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), habits: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), habits: Array(TodayStore.perDayHabits().prefix(3))))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let entry = TodayEntry(date: now, habits: Array(TodayStore.perDayHabits().prefix(3)))
        completion(Timeline(entries: [entry], policy: .after(TodayStore.midnight(after: now))))
    }
}
