import SwiftData
import SwiftUI
import WidgetKit

/// The whole app: every habit's status for a week, one tap from done.
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
    /// The first day of the week on screen, which is not always this one
    /// (#117).
    ///
    /// A date rather than an offset from today, so that midnight passing while
    /// the screen is up moves *this* week and leaves the one being looked at
    /// where it is. An offset would silently slide the whole view back a week
    /// at 00:00.
    @State private var weekStart = WeekCalendar.startOfWeek(containing: Date())
    /// The earliest day anything is on record for, from `HabitStore`. Held
    /// rather than recomputed per redraw — see `earliestRecordedDay`.
    @State private var recordStart: Date?
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
        return WeekCalendar.week(containing: weekStart)
    }
    private var store: HabitStore { HabitStore(context: context) }

    /// Which weeks there are to visit. Derived from the record, so a fresh
    /// install has only this one: the swipe clamps against its own ends and
    /// the pill has nowhere to send you, so neither does anything (#190).
    private var reach: WeekReach {
        WeekReach.from(recordStart: recordStart, today: today)
    }

    private var isOnCurrentWeek: Bool { weekStart >= reach.latest }

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
    ///
    /// **It does not change with the week on screen** (#117). An earlier week
    /// is edited exactly as this one is, because the surface is the same
    /// surface; all seven of its columns happen to be past, so all seven carry
    /// an action and `allowingFuture` decides nothing. Widening the reach was a
    /// change to which weeks exist — `WeekReach` — not to what a tap may do.
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
            // The title is drawn rather than set (#190): two lines, the week's
            // dates over how far back it is, which `navigationTitle` has no
            // shape for. The large title goes with it — the system's
            // collapse-on-scroll belongs to `navigationTitle` alone and a
            // principal view does not inherit it. That is the trade the issue
            // accepts: a fixed-size header that says which week, in exchange
            // for a large one that said which month.
            //
            // The title is still set, and still says the same thing. Nothing
            // draws it — the principal item takes the centre — but it is what
            // a `NavigationLink` pushed from here would name its back button,
            // and what the system reads when the toolbar is not on screen.
            .navigationTitle(weekRangeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The chevrons are back, and deliberately temporary. #190
                // replaced them with a header swipe, and that swipe **could not
                // be verified**: no drag of any kind recognises under this
                // simulator's synthetic input — the app's own shipped row
                // `swipeActions` do not open either, which is the control that
                // makes the negative meaningless. See #205.
                //
                // Without a working gesture the pill is unreachable, because it
                // only appears once you have already paged away. That would
                // make #117's reach-back — which shipped working — unreachable
                // in the next build. A toolbar item is a cheap insurance
                // premium against that; delete this block the moment a device
                // confirms the swipe. See #211.
                ToolbarItem(placement: .topBarLeading) {
                    weekPager
                }
                ToolbarItem(placement: .principal) {
                    weekReadout
                }
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
            // The same signal carries the pager's other end: switching the demo
            // on puts ten weeks of past on record and switching it off takes
            // them back out, and both move how far back this screen can go.
            refreshReach()
        }
        .task { seedIfNeeded() }
        .task { refreshDemoHistory() }
        .task { refreshReach() }
    }

    /// Every row's week, read once per redraw and only for the week shown.
    ///
    /// This used to be two whole-history reads per redraw — `snapshot()` mapped
    /// over the habits for the cut, and `snapshot()` again inside the loop for
    /// each row — so a screen of seven days cost every completion of every
    /// habit, twice, on every keystroke that redrew it. Nothing here asks about
    /// a day outside `week`: `WeekGrid`, `WeekSpans`, `WeekDots` and `GoalMet`
    /// all count inside the week they are given. See #135.
    ///
    /// `week` follows `weekStart`, so paging back (#117) reads that week and
    /// costs what this one does. A pager over whole histories would have made
    /// every step back the most expensive thing the screen does.
    private var snapshots: [HabitSnapshot] {
        Habit.snapshots(of: habits, within: week.dayIDs())
    }

    private var grid: some View {
        GeometryReader { proxy in
            let geometry = RowGeometry(totalWidth: proxy.size.width)
            let snapshots = self.snapshots
            // The rest day's line ends on a habit, and it ends where the widget
            // ends: the same `largeRowCapacity` that decides the boundary
            // hairline below, so the cut stops on that line rather than running
            // down a list that scrolls.
            let cut = RestCut.rows(snapshots, capacity: WidgetMetrics.largeRowCapacity)
            List {
                Section {
                    // Between the header and the first row, inside the list
                    // rather than above it: it belongs to the week on screen,
                    // so it scrolls with the week's rows and leaves the
                    // toolbar alone. Outside the `ForEach`, so reordering and
                    // deletion still index the habits and nothing else.
                    if !isOnCurrentWeek {
                        thisWeekPill
                            .listRowInsets(EdgeInsets(
                                top: 0, leading: geometry.horizontalPadding,
                                bottom: 10, trailing: geometry.horizontalPadding
                            ))
                            .listRowSeparator(.hidden)
                    }
                    ForEach(Array(habits.enumerated()), id: \.element.id) { index, habit in
                        HabitRowView(
                            snapshot: snapshots[index],
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
                    WeekdayHeader(
                        geometry: geometry, week: week, today: today, onPage: step
                    )
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

    /// Which week you are on: its dates, and under them how far back it is.
    ///
    /// The chevrons that used to sit opposite Edit and Add are gone (#190) —
    /// the swipe on `WeekdayHeader` pages, and the pill below returns. What
    /// replaces them here is a readout rather than a control, so nothing new
    /// competes for the toolbar's leading slot and nothing sits over the marks.
    ///
    /// **The one control VoiceOver is left is this.** The chevrons were also
    /// the only paging a rotor could reach, and a drag on a header that is
    /// `accessibilityHidden` reaches nobody — so the readout is adjustable:
    /// swipe up for a later week, down for an earlier one, the same direction
    /// the gesture goes. That is one element saying one thing, which is not
    /// what #137 declined to speak; the seven letters over seven numbers are
    /// still a table read aloud and still hidden.
    private var weekReadout: some View {
        // The two lines are left-aligned to each other, which is the part this
        // view owns. *Where the pair sits* is the system's, and it is not one
        // place: measured on the simulator, the item is centred while it is one
        // line, leading once the second line arrives, and centred again in edit
        // mode. So the readout does shift left as you leave this week — at the
        // same moment the pill appears and the subtitle does, which is a state
        // change and not a wobble. A `frame(maxWidth:alignment:)` around it
        // changes none of the three; the toolbar sizes the item to fit and
        // places it itself.
        VStack(alignment: .leading, spacing: 0) {
            Text(weekRangeTitle)
                .font(.headline)
            if let weeksBackTitle {
                Text(weeksBackTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Adjust to page through earlier weeks.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }

    /// Back to this week in one step, drawn only when you are not on it.
    ///
    /// Drawn rather than styled, for the reason the empty state's button gives
    /// and `StoreUnavailableView`'s repeats: the app's root tint is pure white,
    /// and a `.borderedProminent` capsule under it fills white and writes its
    /// label in white. See #162.
    ///
    /// One step rather than a walk back through the weeks between: the pill is
    /// the way out of a place you paged into, and repeating a tap eleven times
    /// is not a way out.
    private var thisWeekPill: some View {
        Button {
            weekStart = reach.latest
        } label: {
            HStack(spacing: 6) {
                Text("This Week")
                Image(systemName: "arrow.forward")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(GlowPalette.color))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("This Week")
    }

    private var weekRangeTitle: String {
        WeekCalendar.weekRangeTitle(for: week, today: today)
    }

    private var weeksBackTitle: String? {
        WeekCalendar.weeksBackTitle(for: weekStart, latest: reach.latest)
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
            if added > 0 {
                WidgetRefresh.invalidate()
                // The record starts where the first habit does, so a store that
                // was empty a moment ago now has one.
                refreshReach()
            }
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
        refreshReach()
    }

    /// Re-reads how far back the record goes, and pulls the week on screen back
    /// inside it.
    ///
    /// Both ends move: the newest week moves at midnight, and the oldest moves
    /// when the record does — a demo switched on ten weeks of past, a demo
    /// switched off takes them away again. Clamping here is what stops the view
    /// standing on a week that has stopped existing.
    ///
    /// Not called from `toggle`: logging a day cannot open a week the pager did
    /// not already reach, and un-logging the earliest completion on record
    /// while you are standing on its week would otherwise yank the screen out
    /// from under the tap that did it.
    private func refreshReach() {
        let start = store.earliestRecordedDay()
        if start != recordStart { recordStart = start }
        let clamped = WeekReach.from(recordStart: start, today: today).clamped(weekStart)
        if clamped != weekStart { weekStart = clamped }
    }

    /// Moves the week on screen, clamped into the reach.
    /// Two chevrons: back through the weeks the record reaches, forward to
    /// this one. **Temporary, and only here because #190's swipe is
    /// unverified** — see the note on the toolbar and #211.
    ///
    /// Kept exactly as #117 shipped it rather than rewritten, so removing it is
    /// a clean deletion rather than an untangling.
    private var weekPager: some View {
        HStack(spacing: 8) {
            Button {
                step(-1)
            } label: {
                Label("Previous Week", systemImage: "chevron.left")
            }
            .disabled(weekStart <= reach.earliest)

            Button {
                step(1)
            } label: {
                Label("Next Week", systemImage: "chevron.right")
            }
            .disabled(isOnCurrentWeek)
        }
        .labelStyle(.iconOnly)
    }

    private func step(_ weeks: Int) {
        let next = reach.step(weekStart, by: weeks)
        guard next != weekStart else { return }
        weekStart = next
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
    /// Paging, in weeks: −1 back, +1 forward. The header owns the gesture and
    /// nothing else about the pager — where it may go is `WeekReach`'s answer,
    /// given by the screen.
    let onPage: (Int) -> Void

    /// The same read the rows make, for the same reason and with the same
    /// standing: this header is built inside `WeeklyGridView`'s
    /// `NavigationStack`, not by the struct that constructs one, so the value
    /// the toolbar's `EditButton` toggles is the value it sees. See
    /// `HabitRowView.isEditing` for the distinction, and `TodayView` for the
    /// case where it does not hold.
    @Environment(\.editMode) private var editMode
    private var isEditing: Bool { editMode?.wrappedValue.isEditing ?? false }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // The pager's gesture, and the only place in the grid that carries one
        // (#190): the rows' own `swipeActions` own a horizontal drag that
        // starts on a row, and this does not touch them.
        //
        // Discrete rather than interactive — past the threshold it jumps a
        // week, exactly as a chevron tap did. Nothing tracks the finger, so
        // there is no half-dragged week to abandon.
        //
        // Vertical drags belong to the list. `minimumDistance` keeps a tap on
        // nothing from paging, and the comparison below hands anything more
        // vertical than horizontal back — the List's own scroll recognizer
        // reads that one, and a gesture that ended more up than sideways was
        // never a page.
        //
        // **`simultaneousGesture` rather than `gesture`, and unverified either
        // way.** The competing recognizer is a scroll view's pan, which claims
        // the touch stream first; simultaneous recognition does not ask it to
        // give the stream up. Which of the two the simulator would have shown
        // is unknown, because *no* drag can be exercised there: the same
        // synthetic swipes that page Calendar.app leave this app's own shipped
        // row `swipeActions` unopened, so a header gesture that does not fire
        // under automation is evidence about the harness and not about the
        // code. See #205 and docs/decisions.md.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    // A header faded out is a header nobody can aim at, so
                    // while edit mode has it the gesture rests with it.
                    guard !isEditing else { return }
                    guard abs(value.translation.width) > abs(value.translation.height)
                    else { return }
                    onPage(value.translation.width < 0 ? 1 : -1)
                }
        )
    }
}

#Preview {
    WeeklyGridView()
        .modelContainer(for: [Habit.self, Completion.self], inMemory: true)
}
