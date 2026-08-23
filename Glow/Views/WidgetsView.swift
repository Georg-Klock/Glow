import SwiftData
import SwiftUI
import WidgetKit

/// Every widget this app ships, drawn by the code that ships them, and which
/// of them are already on the Home Screen.
///
/// **There is no way to put one there from here** (#210). No public API opens
/// the widget gallery, scrolls it to an app, or places a widget: `WidgetCenter`
/// can invalidate, reload and *report*, and nothing else. The one capability
/// that reads like it might is `promptsForUserConfiguration()`, and it is a
/// modifier on a `WidgetConfiguration` that asks for the widget's *settings*
/// straight after somebody has already added it by hand — it is not a call an
/// app can make, and it does not add anything. Checked against the iOS 26.5
/// SDK's `WidgetKit.swiftinterface`, not against memory. So this page is built
/// around a long-press the person performs, which is why the instructions are
/// the loudest thing on it.
///
/// **The previews are the shipping views.** `WeekWidgetView` and
/// `MonthWidgetView` are compiled into the app as well as into the extension,
/// laid out at the point size the family really gets and then scaled down to
/// fit — so what is on this page cannot drift from what is on the Home Screen.
/// The slot size falls out of the track width, so drawing them at a
/// convenient width instead would have been a different layout, not a smaller
/// one.
///
/// The glow is real here too, and unverifiable in the simulator like every
/// other lit surface in this app.
struct WidgetsView: View {
    /// The habits the previews draw — the person's own, not a fixture. A
    /// preview of somebody else's week is a mockup with extra steps.
    @Query(filter: Habit.weekly, sort: [SortDescriptor(\Habit.sortOrder)])
    private var habits: [Habit]

    @Environment(\.scenePhase) private var scenePhase

    /// What `WidgetCenter` last said is on the Home Screen. Empty until the
    /// first answer arrives, which is also what a person with no widgets has —
    /// the page reads the same either way, and it says "Added" only about
    /// something it has been told about.
    @State private var placed: [PlacedWidget] = []

    /// The day the previews are drawn for. Same reason `WeeklyGridView` holds
    /// one: the open slot is defined as today, so today has to be re-read when
    /// the app comes back.
    @State private var today = WeekCalendar.day(Date())

    /// Where "already placed" comes from. A property so a preview or a test can
    /// hand in a fixed answer; the app never passes anything.
    var placements: any WidgetPlacementQuerying = WidgetCenterPlacements()

    /// The week's first day, observed — the previews are widgets, and a widget
    /// draws seven columns from this. Read here for the same reason
    /// `WeeklyGridView` reads it: a value read only inside `WeekCalendar` is a
    /// dependency SwiftUI cannot see (#134).
    @AppStorage(WeekPreferences.firstWeekdayKey, store: GlowSettings.store)
    private var firstWeekday: Int = WeekPreferences.defaultFirstWeekday

    private var cards: [WidgetCard] { WidgetCatalog.cards(placed: placed) }

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
                        ForEach(WidgetKind.allCases, id: \.self) { kind in
                            section(for: kind, width: width)
                        }
                    }
                    .padding(.horizontal, Self.margin)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.black)
            // Four lit previews scroll up this page, so it has Settings'
            // problem four times over: screenshotted before this was added, a
            // medium widget's marks were visible through the navigation bar
            // behind the title. `TopFade` is the measured answer, and the bar
            // is declared visible for the same reason it is there — without it
            // the bar's material dims what passes under it to grey. See #195.
            .overlay(alignment: .top) { TopFade() }
            .navigationTitle("Widgets")
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { await refresh() }
        // `getCurrentConfigurations` answers for the moment it is asked, and
        // the moment somebody places a widget is a moment this app is not
        // frontmost — so the fact this page states is exactly the kind that
        // goes stale while nothing here is running. Same trigger `WeeklyGridView`
        // uses for the day rolling over, and the day is re-read here too.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            today = WeekCalendar.day(Date())
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = WeekCalendar.day(Date())
        }
    }

    /// The page's side margin. Wider than a list's, because the previews are
    /// widgets and a widget on a Home Screen has air around it.
    private static let margin: CGFloat = 20

    /// Said once, above everything, because the steps are identical for all
    /// four widgets and repeating them per card would be the same paragraph
    /// four times.
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

    /// One kind: what it is, and each family it can be placed in.
    ///
    /// Grouped by kind rather than one flat list of four cards, because the
    /// sentence describing a widget is a property of the kind — three copies of
    /// it over the week's three sizes would read as three different widgets.
    private func section(for kind: WidgetKind, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.displayName)
                    .font(.headline)
                Text(kind.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(cards.filter { $0.placement.kind == kind }) { card in
                self.card(card, width: width)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ card: WidgetCard, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Above the preview, not below it. Under it, a caption sits
            // between two previews and belongs to neither — screenshotted,
            // "Small" read as the heading of the medium widget below it.
            HStack(spacing: 6) {
                Text(card.placement.familyName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if card.isPlaced {
                    // Placed widgets stay on the page rather than being
                    // dropped: what is already on the Home Screen belongs
                    // beside what is not.
                    Label("Added", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }
            }
            // The size and its state are one fact about one widget, so they are
            // one stop rather than two — and the preview below carries no
            // label of its own.
            .accessibilityElement(children: .combine)
            preview(card.placement, width: width)
        }
    }

    /// The production view, at the size the family really gets, scaled to fit.
    ///
    /// Everything outside the view itself is what the `WidgetConfiguration`
    /// does: the same asymmetric padding, because `contentMarginsDisabled()`
    /// means the widget applies its own, and `GlowPalette.widgetBackground`,
    /// because that is what `containerBackground` resolves to under the Default
    /// appearance. The rounded corner is drawn here because the system is not
    /// here to mask it.
    ///
    /// Not interactive. The marks are `Button(intent:)`s in the real widget and
    /// still are here, so hit testing is switched off rather than left to
    /// surprise somebody: tapping a picture of a widget should not log a habit.
    private func preview(_ placement: WidgetPlacement, width: CGFloat) -> some View {
        let size = WidgetMetrics.size(of: placement.family)
        let scale = size.width > 0 ? min(1, width / size.width) : 1
        return content(for: placement)
            .padding(.leading, WidgetMetrics.padLeading)
            .padding(.trailing, WidgetMetrics.padTrailing)
            .padding(.vertical, WidgetMetrics.padVertical)
            .frame(width: size.width, height: size.height)
            .background(GlowPalette.widgetBackground)
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            // The widget's own edge, because nothing else here draws one: the
            // background is black and so is the page, so an unstroked preview
            // is marks floating in the void with no widget around them.
            // Screenshotted before adding it. The unlit grey and the barbell's
            // thickness, both from the palette — this page introduces no
            // colour and no weight of its own.
            .overlay {
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .strokeBorder(GlowPalette.grey, lineWidth: GlowShape.barThickness)
            }
            .scaleEffect(scale, anchor: .topLeading)
            // The scaled footprint, so the layout above and below reserves what
            // is actually drawn — `scaleEffect` alone changes nothing about the
            // space the view takes.
            .frame(width: size.width * scale, height: size.height * scale)
            .allowsHitTesting(false)
            // One stop, not forty. Every mark inside carries the label it
            // carries on the Home Screen, and a preview is a picture: the row
            // under it says which widget this is and whether it is added.
            .accessibilityHidden(true)
    }

    /// A widget's own corner, at 1x. iOS masks the real thing to its continuous
    /// squircle whatever a widget asks for; here there is no system to do it,
    /// so the design file's 30 is drawn.
    private static let corner: CGFloat = 30

    @ViewBuilder
    private func content(for placement: WidgetPlacement) -> some View {
        switch placement.kind {
        case .week:
            // `familyOverride` because `widgetFamily` is read-only outside
            // WidgetKit — a `WeekWidgetView` rendered anywhere else reports
            // medium and silently drops the header. The render harness needs
            // the same door.
            WeekWidgetView(entry: weekEntry, familyOverride: placement.family)
        case .month:
            MonthWidgetView(entry: monthEntry)
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
            // (#135).
            habits: Habit.snapshots(of: habits, within: week.dayIDs())
        )
    }

    /// The month the month widget would draw, for the habit an unconfigured
    /// one shows — `MonthStore` owns which habit that is, so the preview and
    /// the widget cannot pick differently. A placed month widget can of course
    /// be showing another habit; the preview is of the widget you would add,
    /// which arrives unconfigured.
    private var monthEntry: MonthEntry {
        guard
            let habit = MonthStore.offered(among: habits).first,
            let days = MonthGrid.dayRange(containing: today)
        else { return MonthEntry(date: today, habit: nil) }
        return MonthEntry(
            date: today,
            habit: Habit.snapshots(of: [habit], within: days).first
        )
    }

    /// Asks again. A failure leaves the last answer standing rather than
    /// clearing it: "we could not ask" is not "you have no widgets", and
    /// showing the second for the first is the one wrong thing this page can
    /// say.
    private func refresh() async {
        guard let reported = try? await placements.placedWidgets() else { return }
        placed = reported
    }
}
