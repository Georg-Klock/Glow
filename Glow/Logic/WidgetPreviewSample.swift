import Foundation

/// The week and the month a *gallery preview* draws.
///
/// **A gallery preview is rendered once and cached** (#365). Measured in the
/// simulator: WidgetKit calls `snapshot(for:in:)` with `context.isPreview`
/// true, exactly once per install of the extension, and the picture it gets
/// back is what the gallery shows from then on. Re-opening the gallery does
/// not re-ask — the trace records no second call — so whatever the store
/// happened to say at that one moment is frozen into the sheet until the app
/// is installed again.
///
/// That is why the preview cannot be a store read. The most common moment for
/// that one call is *before the app has ever been launched*, when there is no
/// container to open: the read comes back `.unavailable` and the gallery
/// keeps "Data unavailable — Open Glow" for the life of the install. Reading
/// the store later is no better, because a person's real week frozen at
/// install time is a picture that is wrong on every day but one.
///
/// So the preview is a fixture, and it is the only fixture in the app. That
/// is a deliberate exception to `WidgetsView`'s rule — *"the habits the
/// previews draw — the person's own, not a fixture"* — and the exception is
/// forced: the Widgets tab can re-read the store on every appearance, and the
/// gallery is a bitmap the system took once.
///
/// The fixture is not invented twice over. It is `DefaultHabits.all`, the set
/// the app itself offers on the empty state, over `SeededHistory`, the
/// invented past the demo toggle already uses — so what the gallery advertises
/// is a set the person can actually have, in the shape the app already draws
/// it in.
///
/// Pure, like everything else in here: the day and the rest day arrive as
/// parameters, read once at the provider.
enum WidgetPreviewSample {
    /// The week rows, in the app's own order, blank rows included.
    ///
    /// Bounded to the week it draws, the way `WeekWidgetStore.rows` bounds a
    /// real read — a row only ever asks about seven days.
    static func rows(
        in week: Week,
        today: Date,
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> [HabitSnapshot] {
        let days = week.days[0]...week.days[6]
        return DefaultHabits.all.enumerated().map { position, template in
            snapshot(
                template, at: position, today: today, restDay: restDay,
                calendar: calendar, within: days
            )
        }
    }

    /// The one habit the small family's month is drawn for.
    ///
    /// The first offered row, which is what `MonthStore.month(of: nil, …)`
    /// resolves an unconfigured widget to — so the preview and a freshly
    /// placed small widget advertise the same choice.
    static func month(
        containing today: Date,
        restDay: Int?,
        calendar: Calendar = WeekCalendar.calendar
    ) -> HabitSnapshot {
        let offered = DefaultHabits.all.enumerated().first { !$0.element.isSpacer }
        guard let offered else {
            // `DefaultHabits.all` is a literal with eight habits in it; this
            // branch exists so the type is honest, not because it can happen.
            return HabitSnapshot(
                id: id(at: 0), name: "", icon: "", frequency: .daily,
                completionCounts: [:], isSpacer: true
            )
        }
        let days = MonthGrid.dayRange(containing: today, calendar: calendar)
            .map { range in
                range.lowerBound.date(in: calendar)...range.upperBound.date(in: calendar)
            }
        return snapshot(
            offered.element, at: offered.offset, today: today, restDay: restDay,
            calendar: calendar, within: days
        )
    }

    /// One template's row, with the invented past `SeededHistory` gives it.
    ///
    /// `within` bounds which days are kept, the way a real read is bounded to
    /// what it draws; nil keeps them all.
    private static func snapshot(
        _ template: DefaultHabits.Template,
        at position: Int,
        today: Date,
        restDay: Int?,
        calendar: Calendar,
        within days: ClosedRange<Date>?
    ) -> HabitSnapshot {
        guard !template.isSpacer else {
            return HabitSnapshot(
                id: id(at: position), name: "", icon: "",
                frequency: template.frequency, completionCounts: [:], isSpacer: true
            )
        }
        let completed = SeededHistory.completions(
            for: template.frequency,
            form: SeededHistory.form(at: position),
            seed: UInt64(position),
            today: today,
            restDay: restDay,
            calendar: calendar
        )
        return HabitSnapshot(
            id: id(at: position),
            name: template.name,
            icon: template.icon,
            frequency: template.frequency,
            completedDays: Set(days.map { window in completed.filter(window.contains) } ?? completed)
        )
    }

    /// A stable id per position, so two renders of the preview are the same
    /// preview. Never a `UUID()`: an id that moved would make the sample a
    /// different set of habits on every call, and `WeekEntry` compares by it.
    private static func id(at position: Int) -> UUID {
        UUID(
            uuid: (
                0x61, 0x11, 0x0C, 0x00, 0x00, 0x00, 0x40, 0x00,
                0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, UInt8(truncatingIfNeeded: position)
            )
        )
    }
}
