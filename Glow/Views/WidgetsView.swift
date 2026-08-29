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
/// laid out at the point size the family really gets and then scaled down to
/// fit — so what is on this page cannot drift from what is on the Home Screen.
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
/// The glow is real here too, and unverifiable in the simulator like every
/// other lit surface in this app.
struct WidgetsView: View {
    /// The habits the previews draw — the person's own, not a fixture. A
    /// preview of somebody else's week is a mockup with extra steps.
    @Query(filter: Habit.weekly, sort: [SortDescriptor(\Habit.sortOrder)])
    private var habits: [Habit]

    @Environment(\.scenePhase) private var scenePhase

    /// The day the previews are drawn for. Same reason `WeeklyGridView` holds
    /// one: the open slot is defined as today, so today has to be re-read when
    /// the app comes back.
    @State private var today = WeekCalendar.day(Date())

    /// The week's first day, observed — the previews are widgets, and a widget
    /// draws seven columns from this. Read here for the same reason
    /// `WeeklyGridView` reads it: a value read only inside `WeekCalendar` is a
    /// dependency SwiftUI cannot see (#134).
    @AppStorage(WeekPreferences.firstWeekdayKey, store: GlowSettings.store)
    private var firstWeekday: Int = WeekPreferences.defaultFirstWeekday

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
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        instructions
                        ForEach(groups) { group in
                            card(group, width: width)
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
            today = WeekCalendar.day(Date())
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = WeekCalendar.day(Date())
        }
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
    private func card(_ group: WidgetCardGroup, width: CGFloat) -> some View {
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
            let cardWidth = perRow > 1
                ? (width - Self.gutter * CGFloat(perRow - 1)) / CGFloat(perRow)
                : width
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: Self.gutter) {
                        ForEach(row) { card in
                            preview(card, width: cardWidth)
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
    /// same `GlowPalette.widgetSurface` the widget declares as its container
    /// background. The rounded corner is drawn here because the system is not
    /// here to mask it.
    ///
    /// Not interactive. The marks are intents in the real widget and still are
    /// here, so hit testing is switched off rather than left to surprise
    /// somebody: tapping a picture of a widget should not log a habit.
    private func preview(_ card: WidgetCard, width: CGFloat) -> some View {
        let size = WidgetMetrics.size(of: card.placement.family)
        let scale = size.width > 0 ? min(1, width / size.width) : 1
        return content(for: card)
            .padding(.leading, WidgetMetrics.padLeading(for: card.placement.family))
            .padding(.trailing, WidgetMetrics.padTrailing(for: card.placement.family))
            .padding(.top, WidgetMetrics.padTop)
            .padding(.bottom, WidgetMetrics.padBottom)
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
            .background { GlowPalette.widgetSurface }
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .scaleEffect(scale, anchor: .topLeading)
            // The scaled footprint, so the layout above and below reserves what
            // is actually drawn — `scaleEffect` alone changes nothing about the
            // space the view takes.
            .frame(width: size.width * scale, height: size.height * scale)
            .allowsHitTesting(false)
            // One stop, not forty. Every mark inside carries the label it
            // carries on the Home Screen, and a preview is a picture: the
            // heading above says which widget this is.
            .accessibilityHidden(true)
    }

    /// The space between two widgets sitting side by side, from the sizes
    /// themselves: what is left of a Medium's width once two Smalls are in it.
    private static var gutter: CGFloat {
        WidgetMetrics.largeWidth - WidgetMetrics.smallSide * 2
    }

    /// A widget's own corner, at 1x. iOS masks the real thing to its continuous
    /// squircle whatever a widget asks for; here there is no system to do it,
    /// so the design file's 30 is drawn.
    private static let corner: CGFloat = 30

    @ViewBuilder
    private func content(for card: WidgetCard) -> some View {
        // Content follows the family since #322, exactly as the one kind's
        // provider decides it: small is a habit's month, the rest the week.
        if card.placement.family == .systemSmall {
            MonthWidgetView(entry: monthEntry(for: card.habitID))
        } else {
            // `familyOverride` because `widgetFamily` is read-only outside
            // WidgetKit — a `WeekWidgetView` rendered anywhere else reports
            // medium and silently drops the header. The render harness needs
            // the same door.
            WeekWidgetView(entry: weekEntry, familyOverride: card.placement.family)
        }
    }

    /// The week the week widget would draw, from the app's own live query
    /// rather than from a second read-only container.
    private var weekEntry: WeekEntry {
        let week = WeekCalendar.week(containing: today)
        return WeekEntry(
            date: today,
            week: week,
            // Bounded to the week it draws, exactly as the provider bounds it
            // (#135). This preview reads the app's own live query, which is a
            // read that already succeeded — so the entry is loaded or empty,
            // never unavailable, and `StoreRead(read:)` makes that mapping the
            // same one the provider makes (#282).
            habits: StoreRead(read: Habit.snapshots(of: habits, within: week.dayIDs()))
        )
    }

    /// The month the month widget would draw for one of the person's habits.
    ///
    /// **Several of these, one per habit** (#237). The month widget asks which
    /// habit as it is placed (the unified intent's `habit` parameter, #322),
    /// so a single preview
    /// illustrates one arbitrary answer to a question the page is trying to
    /// show you being asked. `WidgetCatalog` decides how many and which;
    /// `MonthStore.offered` decides what is eligible, so the previews and the
    /// picker cannot disagree.
    ///
    /// `nil` means "whatever an unconfigured widget would show", which is the
    /// first offered habit — the widget's own rule — and, when there are no
    /// weekly habits at all, nothing. Then `MonthWidgetView` draws its own
    /// empty state, which is the honest preview of what adding the widget
    /// today would get you.
    private func monthEntry(for habitID: UUID?) -> MonthEntry {
        let offered = previewHabits
        let chosen = habitID.map { id in offered.first { $0.id == id } } ?? offered.first
        guard let chosen, let days = MonthGrid.dayRange(containing: today),
              let snapshot = Habit.snapshots(of: [chosen], within: days).first
        else { return MonthEntry(date: today, habit: .empty) }
        return MonthEntry(date: today, habit: .loaded(snapshot))
    }
}
