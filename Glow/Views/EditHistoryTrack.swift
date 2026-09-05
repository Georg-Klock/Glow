import SwiftUI

/// One habit's week as seven facts: a filled circle where a completion exists
/// on that exact civil day, an empty one where none does (#543).
///
/// This is deliberately not a projection of `WeekGrid` or `WeekSpans`. Those
/// types answer what a cadence owes and therefore draw open, missed, rest and
/// joined marks. Correcting history asks the smaller factual question —
/// whether a completion exists on this day — so every cell is the same plain
/// selected/unselected circle regardless of cadence, creation date or whether
/// the date is in the past or future.
///
/// It stands in for `HabitRowView.track` while This Week is in
/// `WeekGridMode.correctingHistory` (#557); the label column, the row's
/// height and its place in the `List` are the row's and do not change. It was
/// the track half of `EditHistoryRow` on the separate screen that #557
/// removed — the label half was a second drawing of what `HabitRowView`
/// already draws.
struct EditHistoryTrack: View {
    let snapshot: HabitSnapshot
    let week: Week
    let geometry: RowGeometry
    let onToggle: (Date) -> Void

    var body: some View {
        HStack(spacing: SlotLayout.gap(trackWidth: geometry.trackWidth)) {
            ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                let selected = snapshot.count(on: day) > 0
                Button {
                    onToggle(day)
                } label: {
                    Group {
                        if selected {
                            Circle().fill(GlowPalette.lit)
                        } else {
                            Circle().stroke(GlowPalette.grey, lineWidth: 1.5)
                        }
                    }
                    .frame(
                        width: min(18, geometry.slotHeight),
                        height: min(18, geometry.slotHeight)
                    )
                    // The whole column is the target, the same footprint the
                    // cadence marks have in this row. The separate screen gave
                    // each circle a 36pt-tall target; inside a `List` row that
                    // is exactly one slot tall, that would reach into the
                    // neighbouring rows' insets.
                    .frame(
                        width: SlotLayout.slotWidth(
                            trackWidth: geometry.trackWidth, slotCount: 7
                        ),
                        height: geometry.slotHeight
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    "edit-history-cell-\(snapshot.id.uuidString)-"
                        + DayID(day, calendar: WeekCalendar.calendar).text
                )
                .accessibilityLabel(
                    "\(snapshot.name), \(day.formatted(date: .complete, time: .omitted))"
                )
                .accessibilityValue(selected ? "Selected" : "Not selected")
                .accessibilityHint(selected ? "Removes this completion." : "Adds a completion.")
            }
        }
    }
}
