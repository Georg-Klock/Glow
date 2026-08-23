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
    @Query(filter: Habit.weekly, sort: [SortDescriptor(\Habit.sortOrder)])
    private var habits: [Habit]

    @State private var today = WeekCalendar.today()
    /// The first day of the week on screen, which is not always this one
    /// (#117).
    ///
    /// A date rather than an offset from today, so that midnight passing while
    /// the screen is up moves *this* week and leaves the one being looked at
    /// where it is. An offset would silently slide the whole view back a week
    /// at 00:00.
    @State private var weekStart = WeekCalendar.startOfWeek(containing: WeekCalendar.today())
    /// The earliest day anything is on record for, from `HabitStore`. Held
    /// rather than recomputed per redraw — see `earliestRecordedDay`.
    @State private var recordStart: Date?
    /// Whether the invented past is in, mirrored from `DemoHistory` the way
    /// Settings mirrors it. It is what opens the days ahead — see `editing`.
    @State private var isDemoSeeded = false
    @State private var editingHabit: Habit?
    @State private var isAddingHabit = false
    /// Edit mode, owned rather than left to the `NavigationStack` (#207).
    ///
    /// The list's editing controls are offered on the current week and nowhere
    /// else, so paging away has to *end* edit mode rather than merely hide the
    /// button that leaves it — a mode with no exit control is a trap, and this
    /// screen would otherwise set one every time you paged back out of Edit.
    /// Ending it needs a binding this view can write, which the stack's own is
    /// not.
    ///
    /// Injected below the stack, on the view the toolbar hangs off, so
    /// `EditButton` and the `List` both see this binding rather than the one
    /// the stack provides. **This is not the trap in CLAUDE.md** — that is
    /// about *reading* `@Environment(\.editMode)` from outside the stack, which
    /// is always inactive, and `EditModeTests` scans for it.
    @State private var editMode: EditMode = .inactive
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
    /// install has only this one: back is disabled against it, forward is not
    /// drawn at all, and the toolbar never leaves its current-week shape.
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
                // Above the Low Power strip, because it is the more
                // consequential of the two: one explains why the marks look
                // dimmer, the other says the app is writing to a day that is
                // not today. See `DebugTodayBanner`.
                DebugTodayBanner(horizontalPadding: GridMetrics.horizontalPadding)
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
            // The title is drawn rather than set (#190): two lines, what the
            // week is called over the half that name leaves out, which
            // `navigationTitle` has no shape for. The large title goes with it
            // — the system's collapse-on-scroll belongs to `navigationTitle`
            // alone and a principal view does not inherit it. That is the trade
            // the issue accepts: a fixed-size header that says which week, in
            // exchange for a large one that said which month.
            //
            // The title is still set, and still says the same thing. Nothing
            // draws it — the principal item takes the centre — but it is what
            // a `NavigationLink` pushed from here would name its back button,
            // and what the system reads when the toolbar is not on screen.
            .navigationTitle(weekTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    weekPager
                }
                ToolbarItem(placement: .principal) {
                    weekReadout
                }
                // **The two ends are one decision, not two** (#207). What the
                // trailing group holds depends on which week is on screen, so
                // the pager opposite it cannot be drawn symmetrically and
                // independently: on the current week the only way out is back,
                // and in the past the way home is on both sides.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isOnCurrentWeek {
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
                    } else {
                        // **Not new editing scope** (#207). Every day of the
                        // week on screen is still a tap target — #116 and #117
                        // are untouched. What is gone from a past week is the
                        // *list*: reordering, deleting and adding are
                        // properties of the list itself, and doing them while
                        // looking at three weeks ago means nothing they do not
                        // already mean today. In their place, the one action a
                        // past week has: getting back.
                        todayButton
                    }
                }
            }
            // Below the stack, so `EditButton` above toggles this binding and
            // the `List` reads the same one. See `editMode`.
            .environment(\.editMode, $editMode)
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
            // And the debug override, which is a defaults key in the same
            // store (#204). Settings is a sibling tab, so this view stays
            // alive and unredrawn while the override moves — the same reason
            // demo history needs a notification rather than a value read once
            // at appear.
            //
            // Through `refreshToday`, which also carries the pager's other
            // end: switching the demo on puts ten weeks of past on record and
            // switching it off takes them back out, and both move how far back
            // this screen can go. That is `refreshReach`, which `refreshToday`
            // calls — this handler used to call it directly.
            refreshToday()
        }
        // **This screen writes nothing to the store unasked.** Seeding went in
        // #228 and the per-day sweep went to `GlowApp` in #239, so the empty
        // state below is a real answer about what the store holds rather than a
        // frame before something fills or empties it. Both left for the same
        // reason: the store is reached without this view being reached. The
        // system's widget configurator is another process entirely, reading the
        // same file with no screen of this app involved at all — and even
        // inside the app, "This Week is the landing tab" is a default anyone
        // can change (#238 moved the tab order around it once already), which
        // makes it a poor thing for a one-time sweep to depend on.
        //
        // `refreshReach` is unconditional and has to stay that way: it is the
        // only thing that reads `recordStart`, and the sweep that used to
        // trigger a second call is now over before this view exists.
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
    ///
    /// **It is the first-run choice now** (#228). Nothing seeds by itself any
    /// more, so this screen is what a fresh install opens on, and it offers the
    /// two starting points rather than assuming one: a habit of your own, or
    /// the curated set that used to arrive unasked. An empty store means the
    /// same thing however it got that way — nobody has added anything yet, or
    /// everything has been deleted — and both deserve the same offer, which is
    /// why the flag that used to tell them apart went with the seeder.
    private var emptyState: some View {
        ContentUnavailableView {
            VStack(spacing: 14) {
                GlowImageView(size: CGSize(width: 54, height: 54))
                Text("No Habits")
            }
        } description: {
            // The second sentence answers the one hesitation a pre-selected set
            // raises — *am I stuck with these?* — where it is asked, rather
            // than on a confirmation screen after the tap.
            Text(
                "Add a habit and today's slot will be waiting for you. "
                    + "Start with the pre-selected set and you can rename, "
                    + "retarget, reorder or delete any of them."
            )
        } actions: {
            VStack(spacing: 16) {
                // Drawn rather than styled: the app's root tint is pure
                // white, and `.borderedProminent` fills with the tint and
                // draws the label in the contrasting colour — white on white.
                // Measured: the capsule's interior was 8077 pixels of a single
                // colour, 255,255,255, with no label in it at all. Same
                // treatment as `StoreUnavailableView`. See #162.
                Button { isAddingHabit = true } label: {
                    Text("Add Your First Habit")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(GlowPalette.color))
                }
                .buttonStyle(.plain)

                // Plain text, not a second capsule: #162's trap is a filled
                // background taking the tint, and there is no fill here. The
                // secondary action does not need the primary's weight to be
                // legible — white type on the app's black reads as well as
                // black type on white does.
                Button {
                    startWithDefaults()
                } label: {
                    Text("Start with a Pre-Selected Set")
                        .font(.body.weight(.medium))
                        .foregroundStyle(GlowPalette.color)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Which week you are on: what it is called, and under it the half the
    /// name leaves out.
    ///
    /// A readout rather than a control, so nothing competes with the pager for
    /// the toolbar's leading slot and nothing sits over the marks.
    ///
    /// **The one paging VoiceOver can reach is this.** The header is
    /// `accessibilityHidden` — seven letters over seven numbers is a table read
    /// aloud, which is what #137 declined to speak — and a chevron is a small
    /// target to hunt for, so the readout is adjustable: swipe up for a later
    /// week, down for an earlier one. It reaches *both* directions whatever
    /// shape the pager has taken, which matters more now that the pager is
    /// asymmetric and the forward chevron is absent from the current week
    /// (#207). Each step clamps, so the adjustment stops where the buttons do.
    private var weekReadout: some View {
        // The two lines are left-aligned to each other, which is the part this
        // view owns. *Where the pair sits* is the system's, and #190 measured
        // it shifting left when the second line arrived. It no longer does:
        // with #207's toolbar the title's own centre is 602–604px of a 1206px
        // screen in all four states — current week, one week back, three weeks
        // back, and at the floor — so the readout stays put and only its
        // contents change. The trailing group is narrower now (one Today
        // button, or Edit and Add, rather than Edit and Add beside a wider
        // pager), which is the likeliest reason the item stopped being
        // squeezed.
        VStack(alignment: .leading, spacing: 0) {
            Text(weekTitle)
                .font(.headline)
            if let weekSubtitle {
                Text(weekSubtitle)
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

    /// Back to this week in one step, in the slot Edit and Add vacate.
    ///
    /// One jump rather than a walk back through the weeks between: this is the
    /// way out of a place you paged into, and repeating a tap eleven times is
    /// not a way out. It was a pill over the grid in #190 and is a toolbar
    /// button in #207 — one fewer thing scrolling under the header, and it sits
    /// where the eye already goes for the screen's other actions.
    ///
    /// Plain, not prominent: the app's root tint is pure white and a
    /// `.borderedProminent` capsule under it fills white and writes its label
    /// in white (#162). A toolbar button needs no fill to be found — it is the
    /// only thing on that side of the bar.
    private var todayButton: some View {
        Button("Today") { show(week: reach.latest) }
    }

    /// What the week on screen is called: how long ago it was, until that stops
    /// being an answer, and then the days it covers (#207).
    ///
    /// **A relative phrase is what you actually asked**, for the three weeks
    /// anybody names that way. Beyond them "five weeks ago" is arithmetic
    /// nobody does in their head from a date, and a date is what identifies the
    /// week — so the ladder hands over to `weekRangeTitle`, which #190 built,
    /// and the distance moves to the line underneath.
    private var weekTitle: String {
        switch weeksBack {
        case 0: return "This Week"
        case 1: return "Last Week"
        case 2: return "Two Weeks Ago"
        default: return weekRangeTitle
        }
    }

    /// The half `weekTitle` leaves out: the dates when the title is a phrase,
    /// the distance when the title is the dates.
    ///
    /// Nothing on the current week — "This Week" over the lit column is the
    /// whole answer, and the dates are already under the weekday letters.
    private var weekSubtitle: String? {
        switch weeksBack {
        case 0: return nil
        case 1, 2: return weekRangeTitle
        default: return WeekCalendar.weeksBackTitle(for: weekStart, latest: reach.latest)
        }
    }

    private var weeksBack: Int {
        WeekCalendar.weeksBack(from: weekStart, latest: reach.latest)
    }

    private var weekRangeTitle: String {
        WeekCalendar.weekRangeTitle(for: week, today: today)
    }

    /// A blank row, appended at the end and dragged into place from there.
    private func addSpacer() {
        do {
            try store.addSpacer()
        } catch {
            HabitStore.report(error, operation: "addSpacer")
        }
    }

    /// The empty state's second choice: the curated set, on a tap (#228).
    ///
    /// `resetToDefaults` rather than a revived seeder, because it is the same
    /// insert — #193 split `addAll` out so this path and Settings' reset share
    /// one definition, and duplicating it here to spell the call "seed" would
    /// give the app two ways to install one list. The name describes a reset
    /// because that is what it does to a store with something in it; this
    /// button is only ever offered when the store is empty, where resetting and
    /// seeding are the same act.
    ///
    /// No confirmation: nothing is being thrown away. The typed gate in
    /// Settings guards a store that holds a person's habits, and this one
    /// cannot be reached while it does.
    private func startWithDefaults() {
        do {
            try store.resetToDefaults()
            // The record starts where the first habit does, so a store that was
            // empty a moment ago now has one. The widget hears about it from
            // `HabitStore`'s own commit.
            refreshReach()
        } catch {
            HabitStore.report(error, operation: "startWithDefaults")
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
        let current = WeekCalendar.today()
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
        show(week: WeekReach.from(recordStart: start, today: today).clamped(weekStart))
    }

    /// **Asymmetric** (#207): back is always there, forward only exists once
    /// there is something to come forward from.
    ///
    /// A forward chevron on the current week is a control that can never do
    /// anything — the reach stops here — and #117 drew it disabled, which is a
    /// permanently dim button explaining a boundary nobody was pushing at. Back
    /// keeps its disabled state, because that one *is* pushing at a boundary:
    /// a fresh install has no record to page into, and a chevron that vanished
    /// instead would leave the leading slot empty and the reach unmentioned.
    ///
    /// Sharing a shape with the trailing group is the point rather than a
    /// coincidence: on the current week the bar is `<` … Edit Add, and in the
    /// past it is `< >` … Today. The way home is on both sides exactly when
    /// there is a way home.
    private var weekPager: some View {
        HStack(spacing: 8) {
            Button {
                step(-1)
            } label: {
                Label("Previous Week", systemImage: "chevron.left")
            }
            .disabled(weekStart <= reach.earliest)

            if !isOnCurrentWeek {
                Button {
                    step(1)
                } label: {
                    Label("Next Week", systemImage: "chevron.right")
                }
            }
        }
        .labelStyle(.iconOnly)
    }

    private func step(_ weeks: Int) {
        show(week: reach.step(weekStart, by: weeks))
    }

    /// Puts a week on screen, and ends edit mode on the way out of this one.
    ///
    /// Every path that moves `weekStart` goes through here, because every one
    /// of them can strand: `EditButton` is only in the toolbar on the current
    /// week (#207), so paging back while editing would otherwise leave the list
    /// in a mode with nothing on screen to leave it by — rows fanned open, the
    /// week track faded (#164), and no Done. Ending the mode is the honest
    /// resolution rather than keeping a button the week does not otherwise
    /// have: what edit mode edits is the list, and the list is a current-week
    /// affordance.
    private func show(week newStart: Date) {
        guard newStart != weekStart else { return }
        weekStart = newStart
        if newStart < reach.latest, editMode.isEditing {
            editMode = .inactive
        }
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

    /// The same read the rows make, for the same reason and with the same
    /// standing: this header is built inside `WeeklyGridView`'s
    /// `NavigationStack`, not by the struct that constructs one, so the value
    /// the toolbar's `EditButton` toggles is the value it sees. See
    /// `HabitRowView.isEditing` for the distinction, and CLAUDE.md's entry on
    /// `@Environment(\.editMode)` for the case where it does not hold.
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
        // No gesture. #190 put a discrete horizontal drag here and #207 took it
        // back out in favour of the toolbar's buttons, so this header is once
        // again seven letters over seven numbers and nothing else. What the
        // drag would have been worth was never measured: no drag of any kind
        // recognises under the simulator's synthetic input — this app's own
        // shipped row `swipeActions` do not open under it either — so it would
        // have shipped on an assumption. See docs/decisions.md and #205.
    }
}

#Preview {
    WeeklyGridView()
        .modelContainer(for: [Habit.self, Completion.self], inMemory: true)
}
