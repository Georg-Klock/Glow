import SwiftData
import SwiftUI

/// The one surface that edits a habit on an arbitrary day (#543).
///
/// This is deliberately not a projection of `WeekGrid` or `WeekSpans`. Those
/// types answer what a cadence owes and therefore draw open, missed, rest and
/// joined marks. Edit History asks the smaller factual question — whether a
/// completion exists on this exact day — so every cell is the same plain
/// selected/unselected circle regardless of cadence, creation date or whether
/// the date is in the past or future.
struct EditHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: Habit.weekly, sort: [SortDescriptor(\Habit.sortOrder)])
    private var storedRows: [Habit]

    @State private var today: Date
    @State private var weekStart: Date
    @State private var recordStart: Date?
    /// A completion is a relationship row, not a property on `Habit`. Advancing
    /// this after a write makes the bounded snapshot fetch run again on the
    /// same frame rather than waiting for `@Query` to notice an unchanged
    /// habit row.
    @State private var revision = 0

    @AppStorage(WeekPreferences.firstWeekdayKey, store: GlowSettings.store)
    private var firstWeekday: Int = WeekPreferences.defaultFirstWeekday

    init(initialWeek: Date, today: Date) {
        let day = WeekCalendar.day(today)
        _today = State(initialValue: day)
        _weekStart = State(initialValue: WeekCalendar.startOfWeek(containing: initialWeek))
    }

    private var habits: [Habit] { storedRows.filter { !$0.isSpacer } }
    private var store: HabitStore { HabitStore(context: context) }

    private var week: Week {
        // Register the setting as a SwiftUI dependency. The value itself is
        // consumed by `WeekCalendar.calendar`.
        _ = firstWeekday
        return WeekCalendar.week(containing: weekStart)
    }

    private var reach: EditHistoryReach {
        EditHistoryReach.from(recordStart: recordStart, today: today)
    }

    private var snapshots: [HabitSnapshot] {
        _ = revision
        return Habit.snapshots(of: habits, within: week.dayIDs())
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let inset = GridMetrics.horizontalPadding
                let geometry = RowGeometry(totalWidth: max(0, proxy.size.width - inset * 2))
                let snapshots = self.snapshots

                VStack(spacing: 0) {
                    weekPicker
                        .padding(.horizontal, inset)
                        .padding(.bottom, 10)

                    if habits.isEmpty {
                        ContentUnavailableView(
                            "No Habits Yet",
                            systemImage: "circle.dotted",
                            description: Text("Add a habit from This Week, then edit its history here.")
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                EditHistoryHeader(geometry: geometry, week: week)
                                    .padding(.bottom, 8)

                                ForEach(Array(habits.enumerated()), id: \.element.id) {
                                    index, habit in
                                    EditHistoryRow(
                                        habit: snapshots[index],
                                        week: week,
                                        geometry: geometry
                                    ) { day in
                                        toggle(habit, on: day)
                                    }
                                }
                            }
                            .padding(.horizontal, inset)
                            .padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .navigationTitle("Correct History")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        // The checkmark above is the sole exit. There is no pushed destination
        // to swipe back from, and this closes the presentation gesture too.
        .interactiveDismissDisabled(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshToday()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshToday() }
        }
        .onChange(of: firstWeekday) { _, _ in
            weekStart = reach.clamped(WeekCalendar.startOfWeek(containing: weekStart))
        }
        .onReceive(NotificationCenter.default.publisher(for: StoreChange.fromIntent)) { _ in
            revision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: StoreChange.committed)) { _ in
            refreshReach()
        }
        .task { refreshReach() }
    }

    private var weekPicker: some View {
        HStack(spacing: 12) {
            Button {
                step(-1)
            } label: {
                Label("Previous Week", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .disabled(weekStart <= reach.earliest)

            Spacer(minLength: 0)

            Text(WeekCalendar.weekRangeTitle(for: week, today: today))
                .font(.headline)
                .lineLimit(1)
                .accessibilityLabel("Week of \(WeekCalendar.weekRangeTitle(for: week, today: today))")

            Spacer(minLength: 0)

            Button {
                step(1)
            } label: {
                Label("Next Week", systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)
            .disabled(weekStart >= reach.latest)
        }
    }

    private func step(_ weeks: Int) {
        weekStart = reach.step(weekStart, by: weeks)
    }

    private func refreshToday() {
        let newToday = WeekCalendar.day(WeekCalendar.today())
        guard newToday != today else { return }
        today = newToday
        refreshReach()
    }

    private func refreshReach() {
        let start = store.earliestRecordedDay()
        if start != recordStart { recordStart = start }
        weekStart = EditHistoryReach.from(
            recordStart: start, today: today
        ).clamped(weekStart)
    }

    private func toggle(_ habit: Habit, on day: Date) {
        do {
            switch try store.toggleCompletion(
                for: habit, on: day, allowingFuture: true
            ) {
            case .completed:
                revision &+= 1
                Haptics.completed()
            case .uncompleted:
                revision &+= 1
                Haptics.uncompleted()
            case .refused, .unchanged:
                return
            }
        } catch {
            HabitStore.report(error, operation: "editHistory")
            OperationNotices.shared.report(.mark) { toggle(habit, on: day) }
        }
    }
}

/// Weekday and date, aligned over the matrix's seven circles.
private struct EditHistoryHeader: View {
    let geometry: RowGeometry
    let week: Week

    private var initials: [String] { WeekCalendar.weekdayInitials() }
    private var dayNumbers: [String] { WeekCalendar.dayNumbers(in: week) }

    var body: some View {
        HStack(spacing: geometry.labelGap) {
            Color.clear
                .frame(width: geometry.labelWidth, height: 1)
            HStack(spacing: SlotLayout.gap(trackWidth: geometry.trackWidth)) {
                ForEach(0..<7, id: \.self) { index in
                    VStack(spacing: 0) {
                        Text(initials[index])
                        Text(dayNumbers[index])
                    }
                    .font(.system(size: geometry.textSize))
                    .foregroundStyle(GlowPalette.grey)
                    .frame(
                        width: SlotLayout.slotWidth(
                            trackWidth: geometry.trackWidth, slotCount: 7
                        )
                    )
                    .accessibilityHidden(true)
                }
            }
            .frame(width: geometry.trackWidth, alignment: .leading)
        }
    }
}

/// One factual habit/day row. Cadence never enters this type.
private struct EditHistoryRow: View {
    let habit: HabitSnapshot
    let week: Week
    let geometry: RowGeometry
    let onToggle: (Date) -> Void

    var body: some View {
        HStack(spacing: geometry.labelGap) {
            HStack(spacing: 0) {
                HabitIconView(icon: habit.icon, size: geometry.iconSize)
                    .frame(width: geometry.iconWidth)
                    .padding(.trailing, geometry.iconGap)
                Text(habit.name)
                    .font(.system(size: geometry.textSize))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(GlowPalette.color)
            .frame(width: geometry.labelWidth, alignment: .leading)

            HStack(spacing: SlotLayout.gap(trackWidth: geometry.trackWidth)) {
                ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                    let selected = habit.count(on: day) > 0
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
                        .frame(width: min(18, geometry.slotHeight), height: min(18, geometry.slotHeight))
                        .frame(
                            width: SlotLayout.slotWidth(
                                trackWidth: geometry.trackWidth, slotCount: 7
                            ),
                            height: max(36, geometry.slotHeight)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "edit-history-cell-\(habit.id.uuidString)-"
                            + DayID(day, calendar: WeekCalendar.calendar).text
                    )
                    .accessibilityLabel("\(habit.name), \(day.formatted(date: .complete, time: .omitted))")
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityHint(selected ? "Removes this completion." : "Adds a completion.")
                }
            }
            .frame(width: geometry.trackWidth, alignment: .leading)
        }
    }
}
