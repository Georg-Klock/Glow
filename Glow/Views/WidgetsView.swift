import SwiftData
import SwiftUI
import WidgetKit

/// Every widget this app ships, drawn by the code that ships them: three named
/// cards, largest first — Large Week Widget, Medium Week Widget, Monthly View
/// per Habit (#312).
///
/// **There is no way to put one on a Home Screen from here** (#210). No public
/// API opens the widget gallery, scrolls it to an app, or places a widget:
/// `WidgetCenter` can invalidate, reload and *report*, and nothing else. The
/// one capability that reads like it might is `promptsForUserConfiguration()`,
/// and it is a modifier on a `WidgetConfiguration` that asks for the widget's
/// *settings* straight after somebody has already added it by hand — it is not
/// a call an app can make, and it does not add anything. Checked against the
/// iOS 26.5 SDK's `WidgetKit.swiftinterface`, not against memory. So this page
/// is built around a long-press the person performs, which is why the
/// instructions are the loudest thing on it.
///
/// **The page does not ask what is already placed** (#312). It used to: the
/// "Added" checkmarks were the one thing `WidgetCenter`'s report fed, and they
/// went with the rest of the page chrome. `WidgetCatalog`'s diff and the
/// `WidgetPlacementQuerying` seam stay, pure and tested, for whatever displays
/// the fact next; this view feeds the catalog an empty Home Screen because it
/// prints nothing either answer would change.
///
/// **The previews are the shipping views.** `WeekWidgetView` and
/// `MonthWidgetView` are compiled into the app as well as into the extension,
/// laid out at the point size WidgetKit recorded for this family on this
/// device and then scaled down to fit — so what is on this page cannot drift
/// from what is on the Home Screen. Before WidgetKit has rendered a family,
/// the authored design frame is the explicit fallback rather than a guessed
/// device table.
/// The slot size falls out of the track width, so drawing them at a
/// convenient width instead would have been a different layout, not a smaller
/// one.
///
/// **They are previews of an unconfigured widget** (#188). The week widget's
/// rows are a per-widget choice, and nothing here can know a placed widget's:
/// `WidgetCenter` reports a kind and a family and no configuration. So the
/// previews draw the app's own list, which is exactly what an unconfigured
/// widget draws — the same claim the grid's boundary hairline narrowed to, and
/// narrowed for the same reason. One preview per placed widget would be several
/// pictures of the same card, and a confidently wrong one is worse than a
/// generic one.
///
/// **So the page reads the debug day override, and says so** (#439). "Cannot
/// drift" is a claim about every day the app is willing to believe it is, not
/// only the real one, and the override is the one way the two can be made to
/// differ on purpose. `DebugTodayBanner` comes with it, for `DebugToday`'s own
/// reason: a screen that reads the override and does not admit it is the shape
/// this tool is fenced against.
///
/// The glow is real here too, and unverifiable in the simulator like every
/// other lit surface in this app.
struct WidgetsView: View {
    /// The habits the previews draw — the person's own, not a fixture. A
    /// preview of somebody else's week is a mockup with extra steps.
    @Query(filter: Habit.weekly, sort: [SortDescriptor(\Habit.sortOrder)])
    private var habits: [Habit]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The day the previews are drawn for. Same reason `WeeklyGridView` holds
    /// one: the open slot is defined as today, so today has to be re-read when
    /// the app comes back.
    ///
    /// **`WeekCalendar.today()`, not `WeekCalendar.day(Date())`** (#439). This
    /// was the one surface in the app that established today from the clock
    /// directly, so the debug day override reached every other screen and every
    /// widget and not this page — which is the page whose whole claim is that
    /// what it shows *cannot* drift from what is on the Home Screen. With an
    /// override set, that was exactly what drifted: the placed widget honoured
    /// it, the preview of it did not, and the two disagreed about which column
    /// is today. See `DebugToday`, and the banner below, which is the other
    /// half of what a screen that reads the override owes.
    /// Nil in production. A hosted render supplies a day so this entire
    /// scrolling screen, not a substitute view, can join the pixel gate with a
    /// stable calendar input (#386).
    private let pinnedToday: Date?
    /// A hosted-test observation seam for the lazy catalog. Production leaves
    /// it empty; measuring `onAppear` proves which shipping previews SwiftUI
    /// actually realised before and after a scroll without replacing the view
    /// with a test double (#478).
    private let previewDidAppear: (WidgetCard.ID) -> Void
    @State private var today: Date

    /// An AppIntent writes through a peer SwiftData container, so `@Query`
    /// cannot observe its completion rows. The intent posts a process-local
    /// signal after it settles; changing this state makes the production views
    /// take fresh bounded snapshots and reconcile their optimistic marks.
    @State private var intentRevision = 0

    /// The shared week/month projection is retained across ordinary SwiftUI
    /// redraws. A successful write advances this revision from the one commit
    /// boundary; a peer-intent verdict still advances `intentRevision` above
    /// to reconcile its optimistic face without manufacturing another fetch.
    @State private var storeRevision = 0
    @State private var projectionCache = WidgetPreviewProjectionCache()

    /// WidgetKit's last exact frame for each family on this device. The
    /// extension writes these App Group values at its provider boundary; this
    /// view refreshes them when it is built and whenever the app becomes
    /// active. `WidgetMetrics` remains the authored fallback, not a claim that
    /// every device gets the same Home Screen frame (#544).
    @State private var widgetDisplaySizes: WidgetDisplaySize.Snapshot

    /// The week's first day, observed — the previews are widgets, and a widget
    /// draws seven columns from this. Read here for the same reason
    /// `WeeklyGridView` reads it: a value read only inside `WeekCalendar` is a
    /// dependency SwiftUI cannot see (#134).
    @AppStorage(WeekPreferences.firstWeekdayKey, store: GlowSettings.store)
    private var firstWeekday: Int = WeekPreferences.defaultFirstWeekday

    init(
        today: Date? = nil,
        previewDidAppear: @escaping (WidgetCard.ID) -> Void = { _ in }
    ) {
        let initialToday = WeekCalendar.day(today ?? WeekCalendar.today())
        pinnedToday = today == nil ? nil : initialToday
        self.previewDidAppear = previewDidAppear
        _today = State(initialValue: initialToday)
        _widgetDisplaySizes = State(initialValue: WidgetDisplaySize.snapshot())
    }

    /// The habits a per-habit preview can be drawn against, in the person's
    /// own order. `MonthStore`'s rule rather than a second one, so the previews
    /// and the widget's own habit picker cannot offer different lists.
    private var previewHabits: [Habit] { MonthStore.offered(among: habits) }

    /// The catalog is fed an empty Home Screen deliberately — see the type's
    /// note: nothing on the page displays what a queried one would change.
    private var groups: [WidgetCardGroup] {
        WidgetCatalog.groups(placed: [], habits: previewHabits.map(\.id))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                // One measurement, handed down, the way the week grid measures
                // its track once and hands it to every row. The previews scale
                // to whatever is left after the page's own margins.
                let width = max(0, proxy.size.width - Self.margin * 2)
                // Reading the intent-only revision keeps stale/refused intent
                // verdicts a redraw signal. The projection key deliberately
                // excludes it: only a committed write changes stored history.
                let _ = intentRevision
                let projection = projectionCache.projection(
                    habits: habits,
                    today: today,
                    firstWeekday: firstWeekday,
                    storeRevision: storeRevision
                )
                ScrollView {
                    // **Two stacks, and the outer one has no spacing** (#439).
                    // `DebugTodayBanner` draws nothing while the override is
                    // off, and a nothing inside a `spacing: 32` stack is still
                    // a 32pt gap above the instructions on every ordinary
                    // launch. The banner's own note says the same about padding
                    // applied from outside: what it costs when it is not there
                    // is the whole question. The 10pt below it is its own.
                    VStack(alignment: .leading, spacing: 0) {
                        // Inside the scroll rather than fixed above it. This
                        // page is one scroll from the instructions to the last
                        // preview, and `TopFade` is what dissolves whatever
                        // passes under the navigation bar — a strip pinned
                        // above the scroll would sit inside that falloff and be
                        // drawn half-dimmed. Its horizontal margin is the
                        // stack's, so it is passed nothing of its own.
                        DebugTodayBanner(horizontalPadding: 0)
                        LazyVStack(alignment: .leading, spacing: 32) {
                            instructions
                            ForEach(groups) { group in
                                card(group, width: width, projection: projection)
                            }
                        }
                    }
                    .padding(.horizontal, Self.margin)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.black)
            // Lit previews scroll up this page, so it has Settings' problem
            // several times over: screenshotted before this was added, a
            // medium widget's marks were visible through the navigation bar
            // behind the title. `TopFade` is the measured answer, and the bar
            // is declared visible for the same reason it is there — without it
            // the bar's material dims what passes under it to grey. See #195.
            .overlay(alignment: .top) { TopFade() }
            .navigationTitle("Widgets")
            .toolbarBackground(.visible, for: .navigationBar)
        }
        // The open slot is defined as today, and "today" goes stale while
        // nothing here is running. Same trigger `WeeklyGridView` uses.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshEnvironment()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshEnvironment()
        }
        // And the debug override, which is a defaults key in the App Group
        // rather than a scalar `@AppStorage` can bind to (#204). Settings is a
        // sibling tab, so this view stays alive and unredrawn while the
        // override moves — `WeeklyGridView` watches the same notification for
        // the same reason, and without it this page would only catch up the
        // next time the app was backgrounded and resumed.
        .onReceive(
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
        ) { _ in
            refreshEnvironment()
        }
        // The preview's `SlotToggle` acknowledges immediately. This signal is
        // the second half: re-read the shared store when the same intent has
        // finished, whether it saved, was delivered twice, or was refused.
        .onReceive(NotificationCenter.default.publisher(for: StoreChange.fromIntent)) { _ in
            intentRevision &+= 1
        }
        // Unlike the historically intent-named signal above, this comes from
        // the store's save boundary and covers marks made on This Week too.
        // It is the complete invalidation contract a retained projection needs.
        .onReceive(NotificationCenter.default.publisher(for: StoreChange.committed)) { _ in
            storeRevision &+= 1
        }
        // **And once on the way in, which the notification cannot cover.**
        // `onReceive` subscribes when this view appears, and this tab may never
        // have appeared: the override is set in Settings, and a tab that has
        // not been on screen yet was not listening when it moved. Screenshotted
        // — the banner said Wednesday, drawn from its own read at construction,
        // while the previews underneath it still drew Saturday's open ring.
        // `DebugTodayBanner` carries the same pair for the same reason, and
        // says so in its own note.
        .task { refreshEnvironment() }
    }

    /// Re-reads both environmental inputs the extension can change while this
    /// tab is alive. Assigning only on change avoids redrawing every lit
    /// preview for unrelated App Group writes.
    private func refreshEnvironment() {
        let current = pinnedToday ?? WeekCalendar.today()
        if current != today { today = current }
        let sizes = WidgetDisplaySize.snapshot()
        if sizes != widgetDisplaySizes { widgetDisplaySizes = sizes }
    }

    /// The page's side margin. Wider than a list's, because the previews are
    /// widgets and a widget on a Home Screen has air around it.
    private static let margin: CGFloat = 20

    /// Said once, above everything, because the steps are identical for all
    /// the widgets and repeating them per card would be the same paragraph
    /// three times.
    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adding a widget")
                .font(.headline)
            // The steps, in the order a person performs them. There is nothing
            // to tap here — see the type's note on why there cannot be.
            //
            // **One literal, deliberately.** `Text` parses markdown from a
            // `LocalizedStringKey`, which is what a string *literal* becomes;
            // two literals joined with `+` are a `String` before `Text` sees
            // them, and the `**+**` would render as four asterisks.
            Text("Long-press your Home Screen, tap the **+** in the top corner, search for Glow Up, and drag the size you want onto the screen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One named card: the heading, and every preview under it.
    ///
    /// **The heading is all the prose there is** (#237, restructured by #312).
    /// Under it there used to be a sentence saying what the widget does, then
    /// a size caption and an "Added" checkmark; the widget is drawn directly
    /// below, over the person's own habits, and the name carries the size —
    /// "Large Week Widget" — so the extra rows said what the heading and the
    /// preview already say. The month's heading names the group instead,
    /// because its several previews are several habits one widget could be
    /// showing, not several widgets (#237). The one paragraph left on the page
    /// is `instructions`, which describes a long-press no preview can
    /// demonstrate.
    private func card(
        _ group: WidgetCardGroup,
        width: CGFloat,
        projection: WidgetPreviewProjection
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.placement.cardName)
                .font(.headline)
            // Rows, not a flat stack (#274): a Small widget has a neighbour on
            // a real Home Screen and this page used to draw it a column. How
            // many fit is `WidgetMetrics.perRow`, and the split is
            // `WidgetCardGroup.rows` — both pure, both tested.
            //
            // The horizontal gap is what is left of a Medium's width once the
            // Smalls in it are placed, so two previews here sit as far apart
            // as two widgets do.
            let perRow = WidgetMetrics.perRow(group.placement.family)
            let gutter = group.placement.family == .systemSmall
                ? widgetDisplaySizes.smallGutter
                : Self.designGutter
            let cardWidth = perRow > 1
                // A `GeometryReader` can briefly propose zero while the
                // hosted screen is entering the hierarchy. A negative frame
                // is never a meaningful preview size, and SwiftUI diagnoses
                // one before the settled width arrives.
                ? max(0, (width - gutter * CGFloat(perRow - 1)) / CGFloat(perRow))
                : width
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(group.rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: gutter) {
                        ForEach(row) { card in
                            preview(card, width: cardWidth, projection: projection)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The production view, at the size the family really gets, scaled to fit.
    ///
    /// Everything outside the view itself is what the system does on a Default
    /// Home Screen: the same asymmetric padding, because
    /// `contentMarginsDisabled()` means the widget applies its own, and the
    /// same glass the widget declares as its container (`GlowPalette.widgetSurface`, over black here)
    /// background. The rounded corner is drawn here because the system is not
    /// here to mask it.
    ///
    /// Interactive since #465. These are production `SlotToggle`s, so the app
    /// gets the same AppIntent-backed optimistic frame, idempotent write and
    /// today-only scope as the Home Screen widget. The transforms around them
    /// change size, not behaviour or accessibility.
    private func preview(
        _ card: WidgetCard,
        width: CGFloat,
        projection: WidgetPreviewProjection
    ) -> some View {
        let size = widgetDisplaySizes.referenceSize(of: card.placement.family)
        let scale = size.width > 0 ? min(1, width / size.width) : 1
        return content(for: card, projection: projection)
            // The production mark remains one `SlotToggle`, but an ordinary
            // app view needs a binding-backed delivery adapter where WidgetKit
            // supplies an AppIntent adapter. Both call the same absolute-state
            // operation; this one uses the app's live context, yields the
            // optimistic frame first, and suppresses the foreground Island.
            .environment(\.isInAppWidgetPreview, true)
            // These production widget views are archived stills on the Home
            // Screen but live inside this scrolling app surface. Flatten only
            // each socket's expensive inner-shadow stack; `SlotToggle` stays
            // outside the rasterized layer and remains a real control (#479).
            .environment(\.flattensWidgetSockets, true)
            .environment(\.inAppWidgetMarkAction, InAppWidgetMarkAction {
                habitID, day, renderedDay, done in
                try MarkHabitOperation.perform(
                    habitID: habitID,
                    done: done,
                    day: day,
                    renderedDay: renderedDay,
                    presentsIsland: false,
                    context: modelContext
                )
            })
            .padding(.leading, WidgetMetrics.padLeading(for: card.placement.family))
            .padding(.trailing, WidgetMetrics.padTrailing(for: card.placement.family))
            .padding(.top, WidgetMetrics.padTop)
            .padding(.bottom, WidgetMetrics.padBottom(for: card.placement.family))
            .frame(width: size.width, height: size.height)
            // **The widget's own surface, not an imitation of one** (#369).
            //
            // `GlowPalette.widgetSurface` is what `GlowWidget` declares as its
            // container background and what the render harness renders over, so
            // this page is now the third reader of one declaration rather than
            // the one surface drawing its own. It was `Color.black` under
            // `glassEffect(.regular)`, which is a different material over a
            // different black — `widgetBackground` exists precisely because
            // `Color.black` is a system colour and free to be something other
            // than 0,0,0.
            //
            // **No rendering-mode override.** This used to inject `.accented`,
            // which is the Tinted/Clear substitution, while a Default Home
            // Screen renders `fullColor`. That is not a near-miss: accented
            // discards colour and keeps alpha, so the marks resolved through
            // `GlowPalette.greyAccented` here and through the opaque resting
            // step on the phone. Different pixels by construction. Outside
            // WidgetKit the environment's own default is `fullColor`, which is
            // the appearance being matched, so the override simply goes.
            //
            // **And no stroked edge.** iOS masks a widget to its squircle and
            // strokes nothing, so any border here is by definition a way to
            // tell a preview from the real thing. The reason one was added
            // dissolves rather than being overruled: it existed because the
            // old panel was the page's own black plus a material, leaving the
            // marks with no widget around them. `widgetSurface` gives the
            // preview a ground the page does not have, which is how the widget
            // reads on a Home Screen.
            //
            // What #273 and #312 settled — injected accented rendering, and the
            // black plate under it — was reasoned for a page previewing the
            // *Tinted/Clear* appearance. Matching Default supersedes it; see
            // docs/decisions.md.
            .background {
                GlowPalette.widgetSurface(reduceTransparency: reduceTransparency)
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .scaleEffect(scale, anchor: .topLeading)
            // The scaled footprint, so the layout above and below reserves what
            // is actually drawn — `scaleEffect` alone changes nothing about the
            // space the view takes.
            .frame(width: size.width * scale, height: size.height * scale)
            .onAppear { previewDidAppear(card.id) }
    }

    /// The space between two widgets sitting side by side, from the sizes
    /// themselves: what is left of a Medium's width once two Smalls are in it.
    private static var designGutter: CGFloat {
        WidgetMetrics.largeWidth - WidgetMetrics.smallSide * 2
    }

    /// A widget's own corner, at 1x. iOS masks the real thing to its continuous
    /// squircle whatever a widget asks for; here there is no system to do it,
    /// so the design file's 30 is drawn.
    private static let corner: CGFloat = 30

    @ViewBuilder
    private func content(
        for card: WidgetCard,
        projection: WidgetPreviewProjection
    ) -> some View {
        // Content follows the family since #322, exactly as the one kind's
        // provider decides it: small is a habit's month, the rest the week.
        if card.placement.family == .systemSmall {
            MonthWidgetView(entry: projection.monthEntry(for: card.habitID))
        } else {
            // `familyOverride` because `widgetFamily` is read-only outside
            // WidgetKit — a `WeekWidgetView` rendered anywhere else reports
            // medium and silently drops the header. The render harness needs
            // the same door.
            WeekWidgetView(
                entry: projection.weekEntry,
                familyOverride: card.placement.family
            )
        }
    }
}
