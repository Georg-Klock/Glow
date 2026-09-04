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

    /// A pinned day only when a hosted render supplies one (#386). Production
    /// passes nothing and continues to re-read `WeekCalendar.today()` on every
    /// lifecycle trigger below; the render gate needs the same screen to draw
    /// the same week after the real calendar has moved on.
    private let pinnedToday: Date?
    @State private var today: Date
    /// The first day of the week on screen, which is not always this one
    /// (#117).
    ///
    /// A date rather than an offset from today, so that midnight passing while
    /// the screen is up moves *this* week and leaves the one being looked at
    /// where it is. An offset would silently slide the whole view back a week
    /// at 00:00.
    @State private var weekStart: Date
    /// The earliest day anything is on record for, from `HabitStore`. Held
    /// rather than recomputed per redraw — see `earliestRecordedDay`.
    @State private var recordStart: Date?
    @State private var editingHabit: Habit?
    @State private var isAddingHabit = false
    @State private var isEditingHistory = false
    /// Edit mode, owned rather than left to the `NavigationStack` (#207).
    ///
    /// The list's editing controls are offered on the current week and nowhere
    /// else, so paging away has to *end* edit mode rather than merely hide the
    /// button that leaves it — a mode with no exit control is a trap, and this
    /// screen would otherwise set one every time you paged back out of Edit.
    /// Ending it needs a binding this view can write, which the stack's own is
    /// not.
    ///
    /// Injected below the stack, on the view the toolbar hangs off, so the
    /// menu's Edit item and the `List` both see this binding rather than the
    /// one the stack provides. **This is not the trap in CLAUDE.md** — that is
    /// about *reading* `@Environment(\.editMode)` from outside the stack, which
    /// is always inactive, and `EditModeTests` scans for it.
    @State private var editMode: EditMode = .inactive
    @State private var isShowingLowPowerNotice = false
    @State private var lowPower = LowPowerMonitor()
    /// Advances when `MarkHabitIntent` settles a write from the Widgets tab or
    /// a Home Screen widget while this app process is alive. The view's model
    /// container is a peer of the intent's, so a redraw is the bridge (#465).
    @State private var intentRevision = 0
    /// The pop currently on screen, or nil. See `InAppPop` and PR #275.
    @State private var pop: InAppPop.PopContent?
    /// Cancels a pop's own dismissal when a newer one replaces it, so the
    /// first tap's timer cannot cut short the second tap's pill.
    ///
    /// A box rather than a `Task` in `@State`: the task is replaced on every
    /// pop, and a `@State` assignment is a redraw. Nothing on screen depends
    /// on which task is pending — `pop` is the state the screen draws — so
    /// the handle is kept where changing it invalidates nothing. Measured as
    /// one of the three grid body passes a tap used to cost.
    @State private var popTask = TaskHolder()
    @Environment(\.accessibilityReduceMotion) private var gridReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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

    init(today: Date? = nil) {
        let initialToday = WeekCalendar.day(today ?? WeekCalendar.today())
        pinnedToday = today == nil ? nil : initialToday
        _today = State(initialValue: initialToday)
        _weekStart = State(
            initialValue: WeekCalendar.startOfWeek(containing: initialToday)
        )
    }

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

    /// This Week is now a viewer for every day except today (#543). All
    /// corrections—past or future—belong to Edit History, so the app grid uses
    /// the same strict policy as the widget regardless of which week is shown.
    /// This explicitly supersedes #116/#117's permissive pager behavior.
    private var editing: SlotEditing {
        .todayOnly
    }

    /// Whether the grid has outgrown the widget.
    ///
    /// Rows, not habits: a blank row occupies a slot on the home screen exactly
    /// as a habit does, so it counts against the same eleven.
    ///
    /// **What the line means since #188**: where a large widget *nobody has
    /// configured* stops. It used to mean where the large widget stops, full
    /// stop, and per-widget rows ended that — a configured widget shows the
    /// rows it was given, in its own order, and no line in this list can stand
    /// for all of them at once. The narrower claim is still the useful one:
    /// every widget starts unconfigured, an unconfigured one takes this list
    /// from the top, and someone who has opened the sheet already knows what
    /// their widget shows. Drawing several boundaries, one per placed widget,
    /// would be the app explaining the home screen back to itself.
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
            //
            // The panel now travels beneath the navigation bar with its rows
            // (#454). Use the same measured fade as the Widgets tab so that
            // moving material dissolves to black instead of lighting the status
            // region. Applied before the pop overlay: a pop belongs above the
            // screen treatment, not underneath it.
            .overlay(alignment: .top) { TopFade() }
            // **An overlay, not a row in the stack** (PR #275). Put in the
            // `VStack` it pushed the whole grid down for its two seconds, so
            // the row that was just tapped moved out from under the finger —
            // which is precisely the flurry #272 says has to stay fast. It
            // floats in the gap the day header already leaves instead, and
            // nothing else on the screen moves at all.
            .overlay(alignment: .top) {
                if let pop {
                    InAppPop(content: pop)
                        .padding(.horizontal, GridMetrics.horizontalPadding)
                        .transition(
                            gridReduceMotion
                                ? .opacity
                                : .move(edge: .top).combined(with: .opacity)
                        )
                }
            }
            .navigationTitle(weekTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // **Editing gets the bar to itself** (#399). The pager and the
                // readout both answer "which week", and while the list is
                // fanned open that is not the question — the week cannot be
                // changed from here anyway, because `show(week:)` ends edit
                // mode on the way out and the pager is the only thing that
                // would call it. So both go, and what is left is the one thing
                // editing needs: a way out of it.
                if !editMode.isEditing {
                    weekPager
                }
                ToolbarItem(placement: .principal) {
                    // The item stays and its *content* leaves. An absent
                    // principal item is not an empty centre — the system falls
                    // back to `navigationTitle`, which is still set (see above)
                    // and would draw "This Week" in the readout's place, which
                    // is the opposite of what #399 asks for.
                    if editMode.isEditing {
                        Color.clear.frame(width: 1, height: 1)
                    } else {
                        weekReadout
                    }
                }
                // **The two ends are one decision, not two** (#207). What the
                // trailing group holds depends on which week is on screen, so
                // the pager opposite it cannot be drawn symmetrically and
                // independently: on the current week the only way out is back,
                // and in the past the way home is on both sides.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isOnCurrentWeek {
                        // **Leaving edit mode is one tap; entering it is still
                        // two** (#399, superseding half of #320). #320 put both
                        // ends in the menu so there was one control at all
                        // times, and named the cost: Done was two taps. That is
                        // the half being reversed — the asymmetry is deliberate
                        // rather than an oversight. Entering is a decision
                        // somebody went looking for; leaving is the way out of a
                        // mode, and a mode whose exit is behind a menu reads as
                        // a mode you are stuck in.
                        //
                        // The icon is the one the menu's own item already used,
                        // which is what makes this a promotion of that item
                        // rather than a second Done beside it. The menu keeps
                        // row additions and Edit History while editing.
                        if editMode.isEditing {
                            Button {
                                withAnimation(editModeAnimation) { editMode = .inactive }
                            } label: {
                                Label("Done", systemImage: "checkmark")
                            }
                            // Per-`Label`, not on an ancestor: a label style set
                            // at a shared parent reaches every `Label` below it,
                            // content included (#393). The pager does the same.
                            .labelStyle(.iconOnly)
                        }
                        // One menu rather than a button and a menu (#320): the
                        // list actions share the one control, behind an ellipsis
                        // now that "add" no longer covers them.
                        //
                        // Not `EditButton()`: that type has no menu-item form,
                        // and its automatic Edit/Done label swap goes with it —
                        // this button swaps its own label from the state this
                        // view already owns. The menu rebuilds its content on
                        // every open, so the label is current by construction.
                        moreMenu
                    } else {
                        // Past weeks are browse-only now (#543, superseding
                        // #116/#117). Today is the quick way home; Edit History
                        // remains available beside it because that is where a
                        // correction to the displayed week belongs.
                        todayButton
                        moreMenu
                    }
                }
            }
            // Below the stack, so the menu's Edit item above toggles this
            // binding and the `List` reads the same one. See `editMode`.
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
        .fullScreenCover(isPresented: $isEditingHistory) {
            EditHistoryView(initialWeek: weekStart, today: today)
                .interactiveDismissDisabled(true)
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
        // The debug override is a defaults key in the App Group (#204), and
        // `@AppStorage` cannot bind to it — it is a `Date`. The defaults' own
        // notification is the signal, and it has to be one: Settings is a
        // sibling tab, so this view stays alive and unredrawn while the
        // override moves, and a value read once at appear would leave the
        // grid on the wrong day.
        //
        // **Compared before anything is fetched.** This notification fires
        // for every key the process writes to any defaults store, and the app
        // writes several per tap — the pop's shuffle state and the widget
        // reload's trace line, on the same turn as the tap. The handler used
        // to answer each of them with a demo-history count and two fetches
        // for the reach, so one tap on the grid ran those three queries three
        // times over, and a tap on the Widgets tab ran them five times, for a
        // day that had not moved. Now a defaults change costs one read of the
        // override, and the store is touched only when today has changed.
        //
        // Demo history used to be read here too, from the days when it was a
        // list of ids in the defaults. It is a column on the row since #140,
        // and seeding or removing it is a save — `StoreChange.committed`
        // below is its signal.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            if (pinnedToday ?? WeekCalendar.today()) != today { refreshToday() }
        }
        // **Every successful save, from this screen or any other** — a mark,
        // a demo seeded or removed in Settings, a reset, a widget tap written
        // through the app's own context. The record's start is the one thing
        // this screen derives from those events now that its editing policy is
        // permanently today-only (#543).
        .onReceive(NotificationCenter.default.publisher(for: StoreChange.committed)) { _ in
            refreshReach()
        }
        .onReceive(NotificationCenter.default.publisher(for: StoreChange.fromIntent)) { _ in
            intentRevision &+= 1
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
        _ = intentRevision
        return Habit.snapshots(of: habits, within: week.dayIDs())
    }

    private var grid: some View {
        GeometryReader { proxy in
            // **The grid sits on a panel, and the panel is what it measures
            // against** (#370). `GlowPalette.widgetSurface` is the ground the
            // widget presses its sockets into; #332 made the marks sockets and
            // #333 gave that surface to the widget, and the app's own grid was
            // left pressing them into flat black.
            //
            // The track narrows by the panel's margin rather than the panel
            // being drawn under a grid measured against the screen — a mark
            // wider than the surface it is pressed into is not a smaller
            // version of the widget, it is a different picture. This is the
            // same rule the widget follows, where the slot falls out of the
            // frame it was actually given.
            let inset = GridMetrics.horizontalPadding
            let geometry = RowGeometry(totalWidth: max(0, proxy.size.width - inset * 2))
            let snapshots = self.snapshots
            let isEditing = editMode.isEditing
            let horizontal = GridHorizontalInsets(
                isEditing: isEditing,
                padLeading: geometry.padLeading,
                padTrailing: geometry.padTrailing
            )
            // The rest day's line ends on a habit, and it ends where the widget
            // ends: the same `largeRowCapacity` that decides the boundary
            // hairline below, so the cut stops on that line rather than running
            // down a list that scrolls.
            let cut = RestCut.rows(snapshots, capacity: WidgetMetrics.largeRowCapacity)
            List {
                // **The weekday header is an ordinary row, not a section
                // header** (#398). It was one, and a `Section` brought a
                // spacing above it that the panel — one shape behind the
                // whole list — would have had to include: 22.7pt of grey
                // over the letters where the widget puts `padTop`'s 10.7,
                // which is the screen ceasing to be the widget scaled
                // (#370). Measured on an iPhone 17 Pro against the same
                // frame before the change.
                //
                // **This changes what the header does when the list
                // scrolls, and #398 said it would not.** That issue's
                // constraint — "the weekday header already scrolls fully
                // out of view with no pinning, confirmed against the
                // actual behavior" — does not hold: a `Section` header in
                // a `.plain` list is a *sticky* header, and on `main` it
                // is. Screenshotted at the bottom of a 30-row list, iPhone
                // 15 Pro / iOS 26.5: the letters sit at the top of the
                // list on their own rounded panel with the next habit
                // scrolling underneath them. As an ordinary row the header
                // cannot pin, so it now scrolls away — which is what the
                // issue asked for and what the widget does, but it is a
                // behaviour change and not the no-op the issue expected.
                //
                // The row carries no edit accessory, because `onDelete`
                // and `onMove` are the `ForEach`'s and this row is not in
                // it.
                //
                // **The header is on the panel.** A widget's
                // `containerBackground` covers its whole frame, letters
                // included, so a header floating above the surface is the
                // one thing that gives away that this is not a large
                // widget.
                //
                // **It no longer draws its own copy of the surface** (#398).
                // It had to while it was a section header, because that is
                // not an ordinary row and ignores `listRowBackground` —
                // measured, and the symptom was a panel 61pt short with its
                // top edge at the first habit instead of above the letters.
                // With one panel behind the whole list, the header only has
                // to keep its own padding, which is what `panelHeight`
                // counts as the header block.
                WeekdayHeader(geometry: geometry, week: week, today: today, snapshots: snapshots)
                    .padding(.top, geometry.padTop)
                    .padding(.leading, horizontal.rowLeading)
                    .padding(.trailing, horizontal.rowTrailing)
                    // The widget's header stands further from the first
                    // row than the rows stand from each other.
                    .padding(
                        .bottom,
                        (WidgetMetrics.headerGap - WidgetMetrics.rowGap / 2) * geometry.scale
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(Array(habits.enumerated()), id: \.element.id) { index, habit in
                    let bottomInset: CGFloat = if showsWidgetBoundary,
                                                  index == WidgetMetrics.largeRowCapacity - 1 {
                        geometry.rowInset + geometry.widgetBoundaryGap
                    } else {
                        geometry.rowInset
                    }
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
                        top: geometry.rowInset,
                        leading: horizontal.rowLeading,
                        // Every editable cell has the same ordinary bottom
                        // inset. The panel's larger bottom breathing room is
                        // a separate row below the `ForEach`; putting it in
                        // the final cell makes the native edit controls centre
                        // themselves 15.6 pixels below the habit (#546).
                        bottom: bottomInset,
                        trailing: horizontal.rowTrailing
                    ))
                    .listRowSeparator(.hidden)
                    // **Nothing behind a row any more** (#398). The panel
                    // used to be drawn here, once per row, each piece
                    // clipped square except at the two ends — edge to edge
                    // and abutting, so a continuous surface fell out of it.
                    // It also meant the surface belonged to the row: a
                    // swipe took the row's background with it and opened
                    // Edit and Delete on the `List`'s bare black, which is
                    // the bug. Sampled at the revealed band, iPhone 15 Pro
                    // / iOS 26.5: `(0,0,0)` before, `(31,31,31)` — the
                    // panel — after. The panel is now a single shape
                    // behind the whole list; see `panel`.
                    .listRowBackground(Color.clear)
                    // Everything above this line is what an unconfigured
                    // large widget shows. Below it a habit exists only in
                    // the app, and without the line nothing would say so.
                    // See `showsWidgetBoundary` for what #188 narrowed.
                    //
                    // Drawn only once there is a row beneath it, so it never
                    // appears on a fresh install and never explains a limit
                    // nobody has reached.
                    //
                    // See `RowGeometry.widgetBoundaryLineOffset` (#542) for
                    // why this is not simply half of `widgetBoundaryGap`.
                    .overlay(alignment: .bottom) {
                        if showsWidgetBoundary, index == WidgetMetrics.largeRowCapacity - 1 {
                            Rectangle()
                                .fill(GlowPalette.grey)
                                .frame(height: 0.5)
                                .offset(y: geometry.widgetBoundaryLineOffset)
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
                // The widget's bottom inset belongs to the panel, not to the
                // last editable cell (#546). `List` centres its native remove
                // and reorder controls in a cell's full height, including row
                // insets. Keeping `padBottom` on the last habit made that one
                // cell taller by `padBottom - rowInset` and moved both system
                // controls down by half the difference — 5.2pt / 15.6px on
                // the measured iPhone 17e — even though the habit label kept
                // the ordinary pitch. This inert trailing row preserves the
                // exact panel and scroll height without acquiring edit
                // controls or changing any habit's geometry.
                Color.clear
                    .frame(height: max(0, geometry.padBottom - geometry.rowInset))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)
            }
            .listStyle(.plain)
            // No floor. The row is exactly the widget's slot at the screen's
            // scale, so anything the list imposed underneath it would be a
            // departure from the geometry this screen now has to reproduce.
            .environment(\.defaultMinListRowHeight, 0)
            // The list's own ground goes, so the panel below is what shows
            // through the rows' now-clear backgrounds.
            .scrollContentBackground(.hidden)
            // **The panel, once, following the List's own scroll** (#454).
            // It stays behind the List, so a horizontal row swipe still reveals
            // material (#398). Vertically it receives the same content offset
            // as the rows, so its top and bottom corners travel with them.
            //
            // **The offset lives in the modifier, not on this screen.** See
            // `ScrollingPanel` for the measurement: as this view's own `@State`
            // it re-evaluated the whole grid on every frame of a scroll.
            .modifier(ScrollingPanel(
                panel: panel(geometry: geometry, horizontal: horizontal)
            ))
            // **The edit controls' breathing room, taken from the `List`**
            // (#400, doubled while editing by #520). The delete circle and the
            // reorder handle are the system's, laid out against the `List`'s
            // own bounds — measured, they ignore `listRowInsets` completely —
            // so the only way to move them without drawing replacements is to
            // move the bounds.
            //
            // **After `.background`, and that ordering is load-bearing.** At
            // rest, the List's trailing edge also comes in by the scaled
            // widget trailing inset so a native swipe action ends at the day
            // track (#548); the row and panel compensate in the opposite
            // direction, so neither visible thing moves. In edit mode swipe
            // actions are unavailable and the List returns to symmetric 20pt
            // bounds for the native remove/reorder controls. The visible card
            // stays at the ordinary 20pt screen margin in both modes.
            // The toolbar's existing edit transaction animates these values;
            // #522 removes that transaction under Reduce Motion.
            .padding(.leading, horizontal.listLeading)
            .padding(.trailing, horizontal.listTrailing)
            // **The collapse a removed row leaves behind** (#398), driven off
            // the count rather than out of `delete`.
            //
            // `withAnimation` around the store write does not reach this: the
            // rows are `@Query`'s, and the query publishes its new value after
            // the transaction that changed the store has closed. Measured, not
            // assumed — the row vanished between two frames with the write
            // wrapped, 21ms after the tap, and the frames are in the pull
            // request.
            //
            // The count is the right value to watch: it moves when a row is
            // added or removed and stands still when one is reordered, which
            // already has the drag's own motion, and when a mark is toggled,
            // which has `MotionPolicy`'s.
            .animation(rowRemoval, value: habits.count)
        }
    }

    /// The grid's one grey surface (#398).
    ///
    /// **As tall as the habits on it.** The
    /// panel used to be N+1 row backgrounds that abutted, which gave it that
    /// height for free. One shape has to be told how tall it is, which is
    /// `RowGeometry.panelHeight(rows:)`, reading the same numbers the rows lay
    /// themselves out with.
    ///
    /// **This is not the fix for #402, and that was measured.** Going from 31
    /// real-time blur regions to one is worth ~5% of the frame rate — inside
    /// the noise — against the ~7x that removing the sockets' inner shadows
    /// buys. It does cut the app's own CPU for a scroll by about 40%. The
    /// numbers and the method are in `docs/decisions.md`; #402 keeps the
    /// attribution and stays open.
    ///
    /// **It moves vertically with the rows and stays behind a horizontal row
    /// swipe** (#454). The native List reports its vertical content offset and
    /// this shape receives that same transform. It remains the List's
    /// background, so a cell sliding horizontally still reveals material.
    ///
    /// All four corners, where the header carried the top two and the last row
    /// the bottom two. One shape, one radius.
    ///
    /// The panel insets are the remainders after the List's own insets, not the
    /// row's content insets (#400, #520, #548). Each side sums back to the
    /// ordinary 20pt, so the panel does not follow the system controls inward.
    private func panel(
        geometry: RowGeometry,
        horizontal: GridHorizontalInsets
    ) -> some View {
        GlowPalette.widgetSurface(reduceTransparency: reduceTransparency)
            .frame(height: geometry.panelHeight(
                rows: habits.count,
                includesWidgetBoundary: showsWidgetBoundary
            ))
            .clipShape(RoundedRectangle(
                cornerRadius: GridMetrics.panelCorner, style: .continuous
            ))
            .padding(.leading, horizontal.panelLeading)
            .padding(.trailing, horizontal.panelTrailing)
        // Nothing here is readable and the marks above it are what a screen
        // reader walks. A decorative rectangle in the tree is one more stop on
        // the way to them.
        .accessibilityHidden(true)
    }

    /// Two buttons on an empty screen, and nothing else (#243).
    ///
    /// **It is the first-run choice** (#228). Nothing seeds by itself, so this
    /// screen is what a fresh install opens on, and it offers the two starting
    /// points rather than assuming one: a habit of your own, or the curated set
    /// that used to arrive unasked. An empty store means the same thing however
    /// it got that way — nobody has added anything yet, or everything has been
    /// deleted — and both deserve the same offer, which is why the flag that
    /// used to tell them apart went with the seeder.
    ///
    /// **A plain stack rather than `ContentUnavailableView`** (#243). The
    /// system's view is three slots — icon and title, description, actions —
    /// and this screen now fills one of them; leaving the other two empty is
    /// fighting the type rather than using it. What went with it is named in
    /// `docs/decisions.md`: the 54×54 slot that was the first lit thing on a
    /// fresh install, and the sentence that answered *am I stuck with these?*
    /// where the question is asked.
    ///
    /// **What a screen reader hears is what the screen says, still.** The icon
    /// carried no accessibility label to begin with — measured, it produced no
    /// element at all — so the title and the description were the whole of this
    /// screen's spoken content beyond the buttons, and they are gone from both
    /// at once. Two buttons is what a sighted user sees and two buttons is what
    /// VoiceOver reaches, so nothing here needs a label with no visible text
    /// behind it. See `EmptyStateAccessibilityTests`, which fails if an
    /// invisible third thing ever appears.
    private var emptyState: some View {
        VStack(spacing: 16) {
            // Drawn rather than styled: the app's root tint is pure white, and
            // `.borderedProminent` fills with the tint and draws the label in
            // the contrasting colour — white on white. Measured: the capsule's
            // interior was 8077 pixels of a single colour, 255,255,255, with no
            // label in it at all. Same treatment as `StoreUnavailableView`.
            // See #162.
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
            // legible — white type on the app's black reads as well as black
            // type on white does.
            Button {
                startWithDefaults()
            } label: {
                Text("Start with a Pre-Selected Set")
                    .font(.body.weight(.medium))
                    .foregroundStyle(GlowPalette.color)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        // The two lines are centred on each other, which is the part this view
        // owns (#401). They were left-aligned, and the two are never the same
        // length — "3 Weeks Ago" over "Aug 3 – Aug 9" — so the shorter line sat
        // off the centre the pair as a whole was placed on. A centred block of
        // left-aligned text is the one place in the app that did this.
        //
        // *Where the pair sits* is the system's, and #190 measured it shifting
        // left when the second line arrived. It no longer does: with #207's
        // toolbar the title's own centre is 602–604px of a 1206px screen in all
        // four states — current week, one week back, three weeks back, and at
        // the floor — so the readout stays put and only its contents change.
        // The trailing group is narrower now (one Today button, or the one menu
        // — Edit and Add at #207, folded into it by #320 — rather than two
        // controls beside a wider pager), which is the likeliest reason the item
        // stopped being squeezed.
        VStack(alignment: .center, spacing: 0) {
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
    /// way out of a place you paged into, and a tap repeated once per week
    /// between here and there is not a way out. It mattered when the pager
    /// stopped at twelve weeks and it matters more now that it does not (#186):
    /// the walk home is as long as the record, and this button is one tap from
    /// the oldest week there is exactly as it is from last week's. It was a
    /// pill over the grid in #190 and is a toolbar button in #207 — one fewer
    /// thing scrolling under the header, and it sits where the eye already goes
    /// for the screen's other actions.
    ///
    /// Plain, not prominent: the app's root tint is pure white and a
    /// `.borderedProminent` capsule under it fills white and writes its label
    /// in white (#162). A toolbar button needs no fill to be found — it is the
    /// only thing on that side of the bar.
    private var todayButton: some View {
        Button("Today") { show(week: reach.latest) }
    }

    /// The existing list menu, available from every browsed week now that it
    /// is also the door to Edit History (#543). Row-management actions remain
    /// current-week-only; the history action opens to the week being viewed.
    private var moreMenu: some View {
        Menu {
            if isOnCurrentWeek {
                Button("New Habit", systemImage: "plus") {
                    isAddingHabit = true
                }
                Button("Blank Row", systemImage: "rectangle.dashed") {
                    addSpacer()
                }
                Divider()
            }

            Button("Edit History", systemImage: "calendar.badge.clock") {
                if editMode.isEditing { editMode = .inactive }
                isEditingHistory = true
            }

            // Entering only. Done lives in the promoted toolbar button
            // (#399), so this item is absent while editing rather than reading
            // Done in a second place.
            if isOnCurrentWeek, !habits.isEmpty, !editMode.isEditing {
                Button("Edit", systemImage: "pencil") {
                    withAnimation(editModeAnimation) { editMode = .active }
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
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
    ///
    /// **The count has no ceiling any more** (#186). With the cap gone this
    /// line reads "137 weeks ago" on a record that long, which is a big number
    /// and still the right one: the number is the *distance*, and the line
    /// above it is the identity — a week that far back prints its year, so the
    /// pair reads "Oct 20 – Oct 26, 2025" over "44 weeks ago". Rounding the
    /// distance to years would lose the only precise thing this line says, and
    /// it is the line nobody has to read.
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
            // A failed save rolled back, so trying again starts clean (#282).
            OperationNotices.shared.report(.addSpacer) { addSpacer() }
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
            // One transaction, so a failure left the store empty exactly as it
            // was — which is the only state this button is offered on, so the
            // retry re-runs the same unguarded install (#282).
            OperationNotices.shared.report(.installDefaults) { startWithDefaults() }
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
        let current = pinnedToday ?? WeekCalendar.today()
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
    /// Called after every save, a toggle included, through
    /// `StoreChange.committed`. This used to say it was *not* called from
    /// `toggle`, so that un-logging the earliest completion on record while
    /// standing on its week could not yank the screen out from under the tap
    /// — and that had stopped being true on 2026-08-31 without anyone
    /// deciding it: the widget reload that every commit queues writes a
    /// trace line to the defaults, and the defaults notification called this.
    /// The subscription above keeps that behaviour where it can be seen; if
    /// the guard is wanted back, it is a decision about what a tap on the
    /// earliest week should do, not a plumbing change.
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
    /// coincidence: on the current week the bar is `<` … the ellipsis menu,
    /// and in the past it is `< >` … Today. The way home is on both sides
    /// exactly when there is a way home.
    ///
    /// **Two toolbar items, not one item holding two buttons** (#258). The bar
    /// draws one glass platter per *item*, so the `HStack` this used to be —
    /// inside a single `ToolbarItem` — put both chevrons on one platter and
    /// they read as a fused pill rather than as the two independent controls
    /// they have always been in code.
    ///
    /// This is `ToolbarContent` rather than a `View` because the items have to
    /// be declared, not returned: two buttons behind a `some View` property
    /// reach the toolbar as one opaque view whichever container they go in.
    /// Being two items is necessary and, on iOS 26, not sufficient — see the
    /// `ToolbarSpacer` below.
    @ToolbarContentBuilder
    private var weekPager: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                step(-1)
            } label: {
                Label("Previous Week", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .disabled(weekStart <= reach.earliest)
        }

        if !isOnCurrentWeek {
            // **What actually separates the platters** (#258). iOS 26 gathers
            // adjacent toolbar items at the same placement into one glass
            // container, so two `ToolbarItem`s are drawn exactly as the single
            // `HStack` was — measured in the simulator at each step, because
            // every arrangement short of this one looks like it should work.
            // `ToolbarSpacer` is the API that breaks the container.
            //
            // Availability-gated because the deployment target is iOS 18, and
            // that is the honest shape rather than a workaround: before 26
            // there is no glass platter to divide, so there is nothing for this
            // to do there.
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarLeading)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    step(1)
                } label: {
                    Label("Next Week", systemImage: "chevron.right")
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    private func step(_ weeks: Int) {
        show(week: reach.step(weekStart, by: weeks))
    }

    /// Puts a week on screen, and ends edit mode on the way out of this one.
    ///
    /// Every path that moves `weekStart` goes through here, because every one
    /// of them can strand: the menu holding Edit is only in the toolbar on the
    /// current week (#207), so paging back while editing would otherwise leave the list
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

    private func toggle(_ habit: Habit, on day: Date) {
        do {
            // This surface offers today only. The store's ordinary strict
            // guard is the second line of defense for any stale control.
            switch try store.toggleCompletion(for: habit, on: day) {
            case .completed:
                Haptics.completed()
                // **#103 said no pop here and PR #275 reverses it.** The Island
                // still will not render a Live Activity while its own app is in
                // front, which is why this draws its own rather than asking for
                // one. Same words, same preferences — see `PopPreferences` and
                // `InAppPop`.
                showPop(for: habit, on: day)
            case .uncompleted:
                Haptics.uncompleted()
            case .refused, .unchanged:
                // The grid never hands out a rest-day tap, and never a day
                // ahead unless the demo is in — but the store's answer is the
                // truth, and nothing changed, so nothing haptic and nothing to
                // reload.
                //
                // `.unchanged` cannot arrive here: `toggleCompletion` reads the
                // day and asks for its opposite, so there is always something
                // to change. It is handled beside the refusal because both mean
                // the same thing to this view — the store wrote nothing — and
                // an unreachable case is better answered than left to a
                // `default` that would also swallow a future outcome.
                return
            }
        } catch {
            HabitStore.report(error, operation: "toggleCompletion")
            // The failed save rolled back, so the day still holds what it held
            // and a retry is a fresh toggle of it — the same request the tap
            // was making. The message names no habit and no day (#282).
            OperationNotices.shared.report(.mark) { toggle(habit, on: day) }
        }
    }

    /// Puts the completion's words on screen, and takes them off again.
    ///
    /// The same thing `GoalPopCentre` does for the Island: one line, gone after
    /// `GoalPop.duration`. `PopPreferences.allows` decides whether it is wanted
    /// at all, so the two surfaces cannot disagree.
    ///
    /// **One line per tap** (#420). This used to run the routine line and then
    /// replace it with the goal's after `GoalPop.handover` when the tap met the
    /// goal — two things said inside one two-second window, and the only
    /// double-fire in the app. One pool, one line, no sequence to play.
    ///
    /// One task, cancelled and replaced. Checking off several habits quickly is
    /// the flurry this has to survive (#272): without the cancel, the first
    /// tap's dismissal would fire two seconds after *its* tap and take the
    /// second tap's pill with it.
    private func showPop(for habit: Habit, on day: Date) {
        let week = WeekCalendar.week(containing: day)
        let snapshot = habit.snapshot(within: week.dayIDs())
        let met = GoalMet.justMet(habit: snapshot, in: week)
        guard PopPreferences.allows(justMetGoal: met) else { return }

        popTask.task?.cancel()
        show(name: habit.name, habitID: habit.id, on: day)

        popTask.task = Task { @MainActor in
            try? await Task.sleep(for: GoalPop.duration)
            guard !Task.isCancelled else { return }
            withAnimation(gridReduceMotion ? nil : .easeOut(duration: 0.2)) { pop = nil }
        }
    }

    private func show(name: String, habitID: UUID, on day: Date) {
        let content = InAppPop.PopContent(
            id: UUID(),
            habitName: name,
            line: GoalPop.line()
        )
        withAnimation(gridReduceMotion ? nil : .easeOut(duration: 0.2)) { pop = content }
    }

    private func move(from source: IndexSet, to destination: Int) {
        do {
            try store.reorder(habits, from: source, to: destination)
        } catch {
            HabitStore.report(error, operation: "reorder")
            // No retry closure: the captured offsets describe a list the next
            // render re-draws from the store, where nothing moved — so the
            // honest retry is the drag itself, against what is on screen
            // (#282).
            OperationNotices.shared.report(.reorder)
        }
    }

    private func deleteAt(_ offsets: IndexSet) {
        for habit in offsets.map({ habits[$0] }) {
            delete(habit)
        }
    }

    /// The collapse a removed row leaves behind (#398).
    ///
    /// `nil` under Reduce Motion, which is `withAnimation`'s own spelling for
    /// "no frame in between" — see `MotionPolicy`, which owns the predicate the
    /// way it owns every other one on this screen.
    ///
    /// The curve is here rather than there for `HabitRowView.editFade`'s
    /// reason: what animates is a decision, how long it takes is drawing. A
    /// third of a second of `easeInOut` is the shape `List` gives a row it
    /// removes, kept rather than replaced — the ask was that the rows below
    /// close the gap smoothly, not that this screen invent a curve for it.
    private var rowRemoval: Animation? {
        MotionPolicy.collapsesRemoval(reduceMotion: gridReduceMotion)
            ? .easeInOut(duration: 0.3)
            : nil
    }

    /// The system's ordinary edit-mode transition, or an immediate snap when
    /// Reduce Motion is enabled (#522).
    private var editModeAnimation: Animation? {
        MotionPolicy.changesEditMode(reduceMotion: gridReduceMotion)
            ? .default
            : nil
    }

    private func delete(_ habit: Habit) {
        do {
            // The widget holds a rendered surface with this habit's row on it,
            // and its buttons carry the id the store has just retired. The
            // store's own commit asks for the reload that replaces that
            // surface (#134), through the one door every write goes through —
            // this used to call `WidgetCenter` directly as well, a second,
            // uncoalesced and untraced reload per deleted row on top of the
            // one the commit had already queued. See #129.
            try store.delete(habit)
        } catch {
            HabitStore.report(error, operation: "delete")
            // Destructive: no retry is offered, and `OperationNotices` would
            // drop one anyway. The delete rolled back, the row is still there,
            // and going again means the same swipe (#282).
            OperationNotices.shared.report(.delete)
        }
    }
}

/// A task handle a view can replace without redrawing.
///
/// `@State` holds the box; the box holds the task. Assigning the task changes
/// nothing SwiftUI observes, which is the point: the view draws `pop`, not
/// the timer that clears it.
@MainActor
private final class TaskHolder {
    var task: Task<Void, Never>?
}

/// The grid's panel, moved by the `List`'s own scroll offset (#454) — with
/// the offset owned here rather than by the screen.
///
/// **The offset changes on every frame of a scroll, and whatever holds it is
/// re-evaluated on every one of them.** It was `WeeklyGridView`'s own
/// `@State`, so a flick re-ran the screen's body, the `GeometryReader`
/// closure that reads the week's snapshots out of SwiftData, and every row's
/// body — measured on a 26-row grid in the simulator: one two-second drag
/// produced 38 offset updates, and each of them cost one completion fetch and
/// 52 row-body passes, 1,976 in all, for pixels that only ever move by a
/// translation. Held in a modifier, the state invalidates the modifier's own
/// body and nothing above it: the panel takes its new offset and the `List`
/// it sits behind is not asked to redraw.
///
/// The panel arrives as a value rather than being built in here, so it is
/// rebuilt when the geometry or the row count changes and not when the offset
/// does. Everything else is exactly the modifier chain the screen applied
/// directly: the same `background(alignment: .top)`, the same
/// `GeometryReader`, the same normalised offset read.
private struct ScrollingPanel<Panel: View>: ViewModifier {
    let panel: Panel

    /// The native `List`'s vertical displacement from its resting position.
    /// The rows already move by this amount; the panel behind them takes the
    /// same transform without replacing any of the List interactions.
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(alignment: .top) {
                GeometryReader { _ in
                    panel.offset(y: -offset)
                }
                // Like the List rows, the travelling card is allowed under the
                // navigation and tab bars. `TopFade` dissolves it at the top;
                // clipping this reader would strand those rows on black again.
            }
            // At rest `contentOffset.y` is the negative top inset. Adding that
            // inset gives zero; after a drag it is the exact distance by which
            // the List moved its content. This iOS 18 API observes the native
            // scroller without putting another scroller around it.
            .onScrollGeometryChange(for: CGFloat.self) { scroll in
                scroll.contentOffset.y + scroll.contentInsets.top
            } action: { _, new in
                offset = new
            }
    }
}

#Preview {
    WeeklyGridView()
        .modelContainer(for: [Habit.self, Completion.self], inMemory: true)
}
