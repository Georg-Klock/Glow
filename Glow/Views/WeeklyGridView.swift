import SwiftData
import SwiftUI
import WidgetKit

/// The whole app: every habit's status for the current week, one tap from done.
///
/// Built on `List` rather than a hand-rolled `ScrollView` of rows, so that
/// reordering, deleting, separators, scroll behaviour and edit mode are the
/// system's implementations rather than this app's approximations of them.
struct WeeklyGridView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: [SortDescriptor(\Habit.sortOrder)]) private var habits: [Habit]

    @State private var today = WeekCalendar.day(Date())
    @State private var editingHabit: Habit?
    @State private var isAddingHabit = false
    @State private var isShowingSettings = false
    @State private var isShowingLowPowerNotice = false
    @State private var lowPower = LowPowerMonitor()
    /// Survives relaunches, so the notice appears once per time Low Power Mode
    /// is switched on rather than once per launch.
    @AppStorage("didAnnounceLowPower") private var didAnnounceLowPower = false

    private var week: Week { WeekCalendar.week(containing: today) }
    private var store: HabitStore { HabitStore(context: context) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if lowPower.isLowPowerMode {
                    LowPowerBanner { isShowingLowPowerNotice = true }
                        .padding(.horizontal, GridMetrics.horizontalPadding)
                        .padding(.bottom, 10)
                }
                if habits.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle(monthTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !habits.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                    Button("Add habit", systemImage: "plus") {
                        isAddingHabit = true
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingHabit) {
            HabitEditorView(habit: nil)
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditorView(habit: habit)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $isShowingLowPowerNotice) {
            LowPowerNoticeView(headroom: lowPower.currentHeadroom)
        }
        // Announce it once per activation, then leave the banner to carry it.
        // Re-presenting on every launch would be nagging about a condition the
        // user chose on purpose; never presenting when the app is launched
        // already in Low Power Mode would mean the explanation only ever
        // reaches people who happened to have the app open at the time.
        .onChange(of: lowPower.isLowPowerMode) { _, _ in announceLowPowerIfNeeded() }
        .task { announceLowPowerIfNeeded() }
        // The open slot is defined as "today", so the screen has to notice when
        // today changes. Both paths matter: the notification covers the app
        // being open across midnight, the scene phase covers it being resumed
        // the next morning without ever having been killed.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshToday()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshToday()
                // The power-state notification does not arrive while suspended.
                lowPower.refresh()
            }
        }
        .task { seedIfNeeded() }
    }

    private var grid: some View {
        GeometryReader { proxy in
            let geometry = RowGeometry(totalWidth: proxy.size.width)
            List {
                Section {
                    ForEach(habits) { habit in
                        HabitRowView(
                            snapshot: habit.snapshot(),
                            week: week,
                            today: today,
                            geometry: geometry
                        ) { day in
                            toggle(habit, on: day)
                        } onEdit: {
                            editingHabit = habit
                        }
                        .listRowInsets(EdgeInsets(
                            top: 6, leading: GridMetrics.horizontalPadding,
                            bottom: 6, trailing: GridMetrics.horizontalPadding
                        ))
                        .listRowSeparator(.hidden)
                        // Swipe actions rather than a long-press menu: this is
                        // where iOS users already reach for edit and delete.
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(habit)
                            }
                            Button("Edit", systemImage: "pencil") {
                                editingHabit = habit
                            }
                            .tint(.indigo)
                        }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: deleteAt)
                } header: {
                    WeekdayHeader(geometry: geometry, week: week, today: today)
                        .listRowInsets(EdgeInsets(
                            top: 0, leading: GridMetrics.horizontalPadding,
                            bottom: 8, trailing: GridMetrics.horizontalPadding
                        ))
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, GridMetrics.minimumRowHeight)
        }
    }

    /// The system's empty state, rather than a stack of centred labels.
    ///
    /// Its icon is a real slot rendered by the real code path, so the thing the
    /// app is about is the first thing on screen, and on an HDR display it
    /// glows here before there is anything to track.
    private var emptyState: some View {
        ContentUnavailableView {
            VStack(spacing: 14) {
                GlowImageView(size: CGSize(width: 54, height: 54))
                Text("No Habits")
            }
        } description: {
            Text("Add a habit and today's slot will be waiting for you.")
        } actions: {
            Button("Add Habit") { isAddingHabit = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var monthTitle: String {
        today.formatted(.dateTime.month(.wide).locale(WeekCalendar.calendar.locale ?? .current))
    }

    /// First launch starts with habits rather than an empty state. Nothing is
    /// pre-completed: see DefaultHabits.
    private func seedIfNeeded() {
        do {
            let added = try HabitSeeder(context: context).seedIfNeeded()
            if added > 0 { WidgetCenter.shared.reloadAllTimelines() }
        } catch {
            HabitStore.report(error, operation: "seedDefaults")
        }
    }

    private func announceLowPowerIfNeeded() {
        if lowPower.isLowPowerMode {
            if !didAnnounceLowPower {
                didAnnounceLowPower = true
                isShowingLowPowerNotice = true
            }
        } else {
            didAnnounceLowPower = false
        }
    }

    private func refreshToday() {
        let current = WeekCalendar.day(Date())
        if current != today { today = current }
    }

    private func toggle(_ habit: Habit, on day: Date) {
        do {
            let isNowComplete = try store.toggleCompletion(for: habit, on: day)
            if isNowComplete {
                Haptics.completed()
            } else {
                Haptics.uncompleted()
            }
            // The widget reads the same store but is not told when it changes.
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            HabitStore.report(error, operation: "toggleCompletion")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        do {
            try store.reorder(habits, from: source, to: destination)
        } catch {
            HabitStore.report(error, operation: "reorder")
        }
    }

    private func deleteAt(_ offsets: IndexSet) {
        for habit in offsets.map({ habits[$0] }) {
            delete(habit)
        }
    }

    private func delete(_ habit: Habit) {
        do {
            try store.delete(habit)
        } catch {
            HabitStore.report(error, operation: "delete")
        }
    }
}

/// M T W T F S S over the dates they stand for, aligned to a seven-slot track.
///
/// Frequency rows deliberately do not line up with these: their pills are not
/// day-pinned, so there is nothing for them to line up with.
struct WeekdayHeader: View {
    let geometry: RowGeometry
    let week: Week
    let today: Date

    private var initials: [String] { WeekCalendar.weekdayInitials() }
    private var numbers: [String] { WeekCalendar.dayNumbers(in: week) }

    var body: some View {
        HStack(spacing: GridMetrics.labelSpacing) {
            Color.clear
                .frame(width: geometry.labelWidth, height: 1)
            // Letters only. The date numbers went with them for a while and
            // were carrying nothing: the week is always the current one, so a
            // number never answers a question the letter had not already.
            HStack(spacing: SlotLayout.gap(trackWidth: geometry.trackWidth)) {
                ForEach(0..<7, id: \.self) { index in
                    let isToday = week.days[index] == today
                    let letter = Text(initials[index])
                        .font(.caption.weight(isToday ? .semibold : .regular))

                    Group {
                        // Today's letter is white with a drop shadow in the
                        // design, so it is a glow and not just a brighter grey.
                        if isToday {
                            letter.glowing(halo: GlowPalette.headerHalo)
                        } else {
                            letter.foregroundStyle(GlowPalette.headerRest)
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
    }
}

#Preview {
    WeeklyGridView()
        .modelContainer(for: [Habit.self, Completion.self], inMemory: true)
}
