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
    @Query(filter: Habit.countedPerWeek, sort: [SortDescriptor(\Habit.sortOrder)])
    private var habits: [Habit]

    @State private var today = WeekCalendar.day(Date())
    /// Whether the invented past is in, mirrored from `DemoHistory` the way
    /// Settings mirrors it. It is what opens the days ahead — see `editing`.
    @State private var isDemoSeeded = false
    @State private var editingHabit: Habit?
    @State private var isAddingHabit = false
    @State private var isShowingLowPowerNotice = false
    @State private var lowPower = LowPowerMonitor()
    /// Survives relaunches, so the notice appears once per time Low Power Mode
    /// is switched on rather than once per launch.
    @AppStorage("didAnnounceLowPower") private var didAnnounceLowPower = false

    /// The week's first day, observed. `WeekCalendar` reads the same key, but a
    /// value read only in `WeekCalendar` is a dependency SwiftUI cannot see —
    /// so this grid kept its old columns until something else redrew it (#134).
    /// It is read in `week` below, which is what registers the dependency; the
    /// same trick `HabitRowView` uses for the rest day.
    @AppStorage(WeekPreferences.firstWeekdayKey, store: GlowSettings.store)
    private var firstWeekday: Int = WeekPreferences.defaultFirstWeekday

    private var week: Week {
        // `firstWeekday` is read, not used: reading it here is the whole point.
        _ = firstWeekday
        return WeekCalendar.week(containing: today)
    }
    private var store: HabitStore { HabitStore(context: context) }

    /// **This screen edits any day of the week it shows** (#116). Every slot is
    /// a plain button — no edit mode, no long press, no confirmation — and the
    /// cost is accepted: a stray tap on Monday changes Monday, and nothing
    /// distinguishes a correction from an original. That is what editing the
    /// past means.
    ///
    /// The days *ahead* open only with demo history in. Outside it a completion
    /// logged forward would be a claim about something that has not happened,
    /// and the app's one signal is a record of what did; with the demo in, the
    /// whole screen is an invented past already, and painting days ahead is the
    /// same job.
    private var editing: SlotEditing {
        .week(allowingFuture: isDemoSeeded)
    }

    /// Whether the grid has outgrown the widget.
    ///
    /// Rows, not habits: a blank row occupies a slot on the home screen exactly
    /// as a habit does, so it counts against the same eleven.
    private var showsWidgetBoundary: Bool {
        habits.count > WidgetMetrics.largeRowCapacity
    }

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
            // A large title, which is the system's own left-aligned style, and
            // both controls trailing, which puts them on the title's own line
            // rather than on a bar above it. Settings is a tab now.
            .navigationTitle(monthTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !habits.isEmpty {
                        EditButton()
                    }
                    // A menu rather than a second button: adding a blank row
                    // is rare next to adding a habit, and two icons in a toolbar
                    // to distinguish "new thing" from "new gap" is a puzzle.
                    Menu {
                        Button("New Habit", systemImage: "plus") {
                            isAddingHabit = true
                        }
                        Button("Blank Row", systemImage: "rectangle.dashed") {
                            addSpacer()
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
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
                refreshDemoHistory()
            }
        }
        // Demo history is a record of invented completion ids in the App
        // Group's defaults, which is not something `@AppStorage` can observe —
        // it holds no scalar to bind to. The defaults' own notification is the
        // signal, and it has to be one: Settings is a sibling tab, so this view
        // stays alive and unredrawn while the toggle moves, and a value read
        // once at appear would leave the days ahead open after the demo went
        // out.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshDemoHistory()
        }
        .task { seedIfNeeded() }
        .task { refreshDemoHistory() }
    }

    private var grid: some View {
        GeometryReader { proxy in
            let geometry = RowGeometry(totalWidth: proxy.size.width)
            // The rest day's line ends on a habit, and it ends where the widget
            // ends: the same `largeRowCapacity` that decides the boundary
            // hairline below, so the cut stops on that line rather than running
            // down a list that scrolls.
            let cut = RestCut.rows(
                habits.map { $0.snapshot() },
                capacity: WidgetMetrics.largeRowCapacity
            )
            List {
                Section {
                    ForEach(Array(habits.enumerated()), id: \.element.id) { index, habit in
                        HabitRowView(
                            snapshot: habit.snapshot(),
                            week: week,
                            today: today,
                            geometry: geometry,
                            index: index,
                            cut: cut,
                            editing: editing
                        ) { day in
                            toggle(habit, on: day)
                        } onEdit: {
                            // A blank row has nothing to edit. Opening the sheet
                            // on one would offer a name, an icon and a cadence
                            // for something that is only a position.
                            guard !habit.isSpacer else { return }
                            editingHabit = habit
                        }
                        .listRowInsets(EdgeInsets(
                            top: geometry.rowInset, leading: geometry.horizontalPadding,
                            bottom: geometry.rowInset, trailing: geometry.horizontalPadding
                        ))
                        .listRowSeparator(.hidden)
                        // Everything above this line is what the large widget
                        // shows. Below it a habit exists only in the app, and
                        // without the line nothing would say so.
                        //
                        // Drawn only once there is a row beneath it, so it never
                        // appears on a fresh install and never explains a limit
                        // nobody has reached.
                        .overlay(alignment: .bottom) {
                            if showsWidgetBoundary, index == WidgetMetrics.largeRowCapacity - 1 {
                                Rectangle()
                                    .fill(GlowPalette.grey)
                                    .frame(height: 0.5)
                                    .offset(y: 6)
                            }
                        }
                        // Swipe actions rather than a long-press menu: this is
                        // where iOS users already reach for edit and delete.
                        .swipeActions(edge: .trailing) {
                            // Explicitly red: the app's white tint at the root
                            // beats `role: .destructive`, and a swipe action
                            // tinted white is a blank pill — white glyph on a
                            // white background, invisible where it most needs
                            // to look dangerous. The editor's delete button
                            // says red out loud for the same reason; the
                            // confirmation dialog alone keeps its role colour,
                            // because alert contexts ignore the app tint.
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(habit)
                            }
                            .tint(.red)
                            if !habit.isSpacer {
                                Button("Edit", systemImage: "pencil") {
                                    editingHabit = habit
                                }
                                .tint(.indigo)
                            }
                        }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: deleteAt)
                } header: {
                    WeekdayHeader(geometry: geometry, week: week, today: today)
                        .listRowInsets(EdgeInsets(
                            top: 0, leading: geometry.horizontalPadding,
                            // The widget's header stands further from the first
                            // row than the rows stand from each other.
                            bottom: (WidgetMetrics.headerGap - WidgetMetrics.rowGap / 2) * geometry.scale,
                            trailing: geometry.horizontalPadding
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
            // Drawn rather than styled: the app's root tint is pure
            // white, and `.borderedProminent` fills with the tint and
            // draws the label in the contrasting colour — white on white.
            // Measured: the capsule's interior was 8077 pixels of a single
            // colour, 255,255,255, with no label in it at all. Same
            // treatment as `StoreUnavailableView`. See #162.
            Button { isAddingHabit = true } label: {
                Text("Add Habit")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(GlowPalette.color))
            }
            .buttonStyle(.plain)
        }
    }

    private var monthTitle: String {
        today.formatted(.dateTime.month(.wide).locale(WeekCalendar.calendar.locale ?? .current))
    }

    /// First launch starts with habits rather than an empty state. Nothing is
    /// pre-completed: see DefaultHabits.
    /// A blank row, appended at the end and dragged into place from there.
    private func addSpacer() {
        do {
            try store.addSpacer()
        } catch {
            HabitStore.report(error, operation: "addSpacer")
        }
    }

    private func seedIfNeeded() {
        do {
            let added = try HabitSeeder(context: context).seedIfNeeded()
            // Seeding writes through its own path rather than `HabitStore`,
            // so it says so itself. See `WidgetRefresh`.
            if added > 0 { WidgetRefresh.invalidate() }
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

    /// Re-reads whether the invented past is in. Compared before assigning, so
    /// an unrelated defaults change — the glow's headroom, the rest day — costs
    /// nothing.
    private func refreshDemoHistory() {
        let seeded = DemoHistory(context: context).isSeeded
        if seeded != isDemoSeeded { isDemoSeeded = seeded }
    }

    private func toggle(_ habit: Habit, on day: Date) {
        do {
            // The same permission the grid drew with. The store guards the
            // future itself, so a row rendered before the demo went out cannot
            // write a day it was offered a moment ago.
            switch try store.toggleCompletion(
                for: habit, on: day, allowingFuture: isDemoSeeded
            ) {
            case .completed:
                Haptics.completed()
                // No pop here, deliberately: the Island does not render an
                // activity while its own app is in front. The haptic above is
                // what this screen has to say about it. See `GoalPopCentre`
                // and #103.
            case .uncompleted:
                Haptics.uncompleted()
            case .refused:
                // The grid never hands out a rest-day tap, and never a day
                // ahead unless the demo is in — but the store's answer is the
                // truth, and nothing changed, so nothing haptic and nothing to
                // reload.
                return
            }
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
            // The widget holds a rendered surface with this habit's row on it,
            // and its buttons carry the id the store has just retired. Reloading
            // replaces that surface; the store refuses the write either way, so
            // this is about not offering a button that does nothing. See #129.
            WidgetCenter.shared.reloadAllTimelines()
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
        HStack(spacing: geometry.labelGap) {
            Color.clear
                .frame(width: geometry.labelWidth, height: 1)
            HStack(spacing: SlotLayout.gap(trackWidth: geometry.trackWidth)) {
                ForEach(0..<7, id: \.self) { index in
                    let isToday = week.days[index] == today
                    // Letter and date, in the app only. The widget has no room
                    // for a second line and does not need one: you read the
                    // widget for a second, and the app when you want to know
                    // which Tuesday. The letter is the widget's letter at the
                    // screen's scale; the date steps down from it.
                    let column = VStack(spacing: 1) {
                        Text(initials[index])
                            .font(.system(size: geometry.textSize))
                        Text(numbers[index])
                            .font(.system(size: geometry.textSize - 2))
                            .monospacedDigit()
                    }

                    Group {
                        // Today is white with a drop shadow in the design, so it
                        // is a glow and not just a brighter grey.
                        if isToday {
                            column.glowing(halo: GlowPalette.headerHalo)
                        } else {
                            column.foregroundStyle(GlowPalette.grey)
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
