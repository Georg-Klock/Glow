import SwiftUI

/// M T W T F S S, aligned to a seven-slot track.
///
/// Frequency rows deliberately do not line up with these: their pills are not
/// day-pinned, so there is nothing for them to line up with.
///
/// **Its own file so the render gate can compile it** (#386), which is the
/// same reason each widget's view sits in a file with its entry and nothing
/// else: `GlowRenderTests` renders app views by compiling them, and
/// `WeeklyGridView.swift` cannot be compiled into that target — it reaches
/// the editor sheet, the notices and the banners, and it is the file the
/// render harness has no use for.
struct WeekdayHeader: View {
    let geometry: RowGeometry
    let week: Week
    let today: Date
    /// The week's rows, for the one question a weekday letter asks that is not
    /// about itself: is anything still open today (#335, §8.5).
    let snapshots: [HabitSnapshot]

    /// The rest day, read here for the same reason `HabitRowView` reads it —
    /// the header has to redraw when Settings moves the day, and only a value
    /// SwiftUI can see does that. See that file for the measurement.
    @AppStorage(WeekPreferences.restDayKey, store: GlowSettings.store)
    private var restDayStorage: Int = 0
    private var restDay: Int? { WeekPreferences.restDay(stored: restDayStorage) }

    private var anyOpen: Bool {
        TypeTier.anyOpen(in: snapshots, week: week, today: today, restDay: restDay)
    }

    /// The same read the rows make, for the same reason and with the same
    /// standing: this header is built inside `WeeklyGridView`'s
    /// `NavigationStack`, not by the struct that constructs one, so the value
    /// the toolbar menu's Edit item toggles is the value it sees. See
    /// `HabitRowView.isEditing` for the distinction, and CLAUDE.md's entry on
    /// `@Environment(\.editMode)` for the case where it does not hold.
    @Environment(\.editMode) private var editMode
    private var isEditing: Bool { editMode?.wrappedValue.isEditing ?? false }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var initials: [String] { WeekCalendar.weekdayInitials() }

    var body: some View {
        HStack(spacing: geometry.labelGap) {
            Color.clear
                .frame(width: geometry.labelWidth, height: 1)
            HStack(spacing: SlotLayout.gap(trackWidth: geometry.trackWidth)) {
                ForEach(0..<7, id: \.self) { index in
                    let isToday = week.days[index] == today
                    // **The letter alone.** A date used to sit under it — room
                    // the widget does not have, spent on saying which Tuesday.
                    // It went when this screen was required to be a large
                    // widget scaled up: a second line makes the header taller
                    // than `headerHeight`, and every row below it then sits
                    // somewhere the widget's does not. See docs/decisions.md.
                    let column = Text(initials[index])
                        .font(.system(size: geometry.textSize))
                        .frame(height: geometry.headerHeight)

                    Group {
                        // Three steps, not two (#335, §8.5). Today emits only
                        // while something is still open; once every habit is
                        // handled it steps down to the lit tier — still plainly
                        // today, no longer asking.
                        switch TypeTier.weekday(isToday: isToday, anyHabitOpen: anyOpen) {
                        case .emitting: column.glowing()
                        case .lit: column.foregroundStyle(GlowPalette.lit)
                        case .resting: column.foregroundStyle(GlowPalette.grey)
                        }
                    }
                    .frame(
                        width: SlotLayout.slotWidth(
                            trackWidth: geometry.trackWidth,
                            slotCount: 7
                        )
                    )
                }
            }
            .frame(width: geometry.trackWidth, alignment: .leading)
        }
        .accessibilityHidden(true)
        // Nothing left to label. The letters stand over the columns, and in
        // edit mode there are no columns — so they go with them, on the rows'
        // own timing so the whole week leaves as one thing rather than as a
        // header and eleven rows that happen to agree.
        //
        // Opacity rather than removal: the header carries the section's height,
        // and a list whose first row jumps up under the title is a different
        // change from the one being made.
        .opacity(isEditing ? 0 : 1)
        .animation(reduceMotion ? nil : HabitRowView.editFade, value: isEditing)
        // No gesture. #190 put a discrete horizontal drag here and #207 took it
        // back out in favour of the toolbar's buttons, so this header is once
        // again seven letters over seven numbers and nothing else. What the
        // drag would have been worth was never measured: no drag of any kind
        // recognises under the simulator's synthetic input — this app's own
        // shipped row `swipeActions` do not open under it either — so it would
        // have shipped on an assumption. See docs/decisions.md and #205.
    }
}
