import Foundation
import Testing
import SwiftUI
import WidgetKit
@testable import Glow

/// #210: the Widgets tab is the difference between what this app ships and
/// what a Home Screen is already holding, and getting that difference wrong
/// means telling somebody they have a widget they do not have.
@Suite("Widget placement")
struct WidgetPlacementTests {
    /// A fixed answer where the app asks WidgetKit. This is the seam the page
    /// is built on: the diff never touches `WidgetCenter`, so a test can state
    /// the Home Screen instead of arranging one.
    private struct StubPlacements: WidgetPlacementQuerying {
        let reported: [PlacedWidget]
        func placedWidgets() async throws -> [PlacedWidget] { reported }
    }

    private struct FailingPlacements: WidgetPlacementQuerying {
        struct Refused: Error {}
        func placedWidgets() async throws -> [PlacedWidget] { throw Refused() }
    }

    // MARK: - What the app ships

    @Test("Every kind, at every family it declares")
    func catalogCoversTheBundle() {
        let all = WidgetCatalog.all
        #expect(all.count == WidgetKind.allCases.reduce(0) { $0 + $1.families.count })
        for kind in WidgetKind.allCases {
            let families = all.filter { $0.kind == kind }.map(\.family)
            // The catalog reads each kind's families largest first — the
            // page's order (#312) — while `families` keeps the gallery's
            // smallest-first. Same list, reversed, nothing dropped.
            #expect(families == kind.families.reversed(), "\(kind) offers \(families)")
        }
    }

    /// One kind since #322, and it is the week's string — the month's
    /// placements froze with `GlowMonthSmall`, accepted on the issue. Small is
    /// a family again, with the month's content.
    @Test("One kind, three sizes, largest first on the page")
    func oneKindThreeSizes() {
        #expect(WidgetKind.allCases == [.week])
        #expect(WidgetKind.week.rawValue == "GlowWidget")
        #expect(WidgetKind.allNames == ["GlowWidget"])
        #expect(WidgetKind.week.families == [.systemSmall, .systemMedium, .systemLarge])
        // Large first since #312 — the page leads with its largest card.
        #expect(WidgetCatalog.all.map(\.family) == [.systemLarge, .systemMedium, .systemSmall])
    }

    // MARK: - Family, not kind (#210)

    /// The mistake this page is most able to make: one size of a kind being
    /// placed reading as the whole kind being placed.
    @Test("A placed medium says nothing about the small or the large")
    func addedMeansThisFamily() {
        let cards = WidgetCatalog.cards(placed: [
            PlacedWidget(kind: .week, family: .systemMedium)
        ])
        let placed = cards.filter(\.isPlaced).map(\.placement)
        #expect(placed == [WidgetPlacement(kind: .week, family: .systemMedium)])
        #expect(cards.count == WidgetCatalog.all.count)
    }

    /// Two sizes of one kind, placed, are two "Added" marks and not four.
    /// **The week's small was one of these until PR #277 removed the family**, so
    /// the pair is now medium and large.
    @Test("Each family answers for itself")
    func familiesAreIndependent() {
        let cards = WidgetCatalog.cards(placed: [
            PlacedWidget(kind: .week, family: .systemMedium),
            PlacedWidget(kind: .week, family: .systemLarge),
            PlacedWidget(kind: .week, family: .systemSmall),
        ])
        let placed = Set(cards.filter(\.isPlaced).map(\.placement))
        #expect(placed == [
            WidgetPlacement(kind: .week, family: .systemMedium),
            WidgetPlacement(kind: .week, family: .systemLarge),
            WidgetPlacement(kind: .week, family: .systemSmall),
        ])
    }

    @Test("Two of the same size are still one Added")
    func duplicatesCollapse() {
        let cards = WidgetCatalog.cards(placed: [
            PlacedWidget(kind: .week, family: .systemSmall),
            PlacedWidget(kind: .week, family: .systemSmall),
        ])
        #expect(cards.filter(\.isPlaced).count == 1)
    }

    @Test("Nothing placed is nothing added")
    func emptyHomeScreen() {
        let cards = WidgetCatalog.cards(placed: [])
        #expect(cards.count == WidgetCatalog.all.count)
        #expect(cards.allSatisfy { !$0.isPlaced })
    }

    // MARK: - What WidgetKit can report that this build does not ship

    /// A Home Screen can still be holding a widget from a build that shipped
    /// more kinds than this one — the Today widgets #209 removed are exactly
    /// that. The page has nothing to say about them, and saying nothing is not
    /// the same as crashing or inventing a row.
    @Test("A kind this build does not serve is dropped")
    func unknownKindIsIgnored() {
        let cards = WidgetCatalog.cards(placed: [
            PlacedWidget(kind: "GlowTodaySmall", family: .systemSmall),
            PlacedWidget(kind: "GlowTodayMedium", family: .systemMedium),
        ])
        #expect(cards.count == WidgetCatalog.all.count)
        #expect(cards.allSatisfy { !$0.isPlaced })
    }

    /// A family outside `supportedFamilies` cannot be placed, but the diff is
    /// asked in terms of what was reported rather than what is possible.
    @Test("A family the kind does not support is dropped")
    func unsupportedFamilyIsIgnored() {
        let cards = WidgetCatalog.cards(placed: [
            PlacedWidget(kind: .week, family: .systemExtraLarge),
        ])
        #expect(cards.allSatisfy { !$0.isPlaced })
    }

    /// The one real placement still counts when it arrives beside noise.
    @Test("A real placement survives the noise around it")
    func mixedReportKeepsWhatItShould() {
        let cards = WidgetCatalog.cards(placed: [
            PlacedWidget(kind: "GlowTodayMedium", family: .systemMedium),
            PlacedWidget(kind: .week, family: .systemLarge),
            // The month kind #322 removed, which a Home Screen can still be
            // holding — the same shape of noise as the Today widgets above.
            PlacedWidget(kind: "GlowMonthSmall", family: .systemSmall),
        ])
        #expect(cards.filter(\.isPlaced).map(\.placement)
            == [WidgetPlacement(kind: .week, family: .systemLarge)])
    }

    // MARK: - The order the page is in

    @Test("The page reads largest first, and the cards carry their names")
    func orderFollowsTheCatalog() {
        let cards = WidgetCatalog.cards(placed: [])
        #expect(cards.map(\.placement) == WidgetCatalog.all)
        // The three named cards, in the page's order (#312). The week led
        // with Medium until #312 turned the page largest-first, and "This
        // Week, Small" was the first of all of these until PR #277.
        #expect(cards.map(\.placement.cardName) == [
            "Large Week Widget", "Medium Week Widget",
            "Monthly View per Habit",
        ])
    }

    // MARK: - The seam

    @Test("The diff is whatever the querier reports")
    func queriedPlacementsFeedTheDiff() async throws {
        let stub = StubPlacements(reported: [PlacedWidget(kind: .week, family: .systemMedium)])
        let cards = WidgetCatalog.cards(placed: try await stub.placedWidgets())
        #expect(cards.filter(\.isPlaced).map(\.placement)
            == [WidgetPlacement(kind: .week, family: .systemMedium)])
    }

    /// "We could not ask" must not render as "you have no widgets". The view
    /// keeps its last answer on a failure; here the contract is only that the
    /// failure is a thrown error rather than an empty list.
    @Test("A refusal throws rather than answering nothing")
    func failureIsNotAnEmptyHomeScreen() async {
        await #expect(throws: FailingPlacements.Refused.self) {
            try await FailingPlacements().placedWidgets()
        }
    }

    // MARK: - One card per habit, where the widget is about a habit (#237)

    private static func habitIDs(_ count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }

    private func monthGroup(_ groups: [WidgetCardGroup]) -> WidgetCardGroup {
        groups.first { $0.placement.family == .systemSmall }!
    }

    /// The axis lives at the small family since #322 — where the month
    /// content is — and nowhere else: medium and large show the whole week,
    /// and their configuration (which rows, #188) is not an axis a preview
    /// can vary over.
    @Test("Small is per-habit, the wide families are not")
    func onlyTheSmallVaries() {
        #expect(WidgetKind.week.previewsOneHabit(at: .systemSmall))
        #expect(WidgetPlacement(kind: .week, family: .systemSmall).previewsOneHabit)
        for family in [WidgetFamily.systemMedium, .systemLarge] {
            #expect(!WidgetKind.week.previewsOneHabit(at: family))
            #expect(!WidgetPlacement(kind: .week, family: family).previewsOneHabit)
        }
    }

    /// Zero weekly habits is the case most able to look broken: a heading with
    /// nothing under it. The month keeps exactly one card, carrying no habit,
    /// which is what makes `MonthWidgetView` draw its own empty state.
    @Test("No habits still leaves one card under every heading")
    func noHabitsKeepsOneCardEach() {
        let groups = WidgetCatalog.groups(placed: [], habits: [])
        let counts = groups.map(\.cards.count)
        let habits: [UUID?] = groups.flatMap(\.cards).map(\.habitID)
        #expect(groups.count == WidgetCatalog.all.count)
        #expect(counts == Array(repeating: 1, count: WidgetCatalog.all.count))
        #expect(habits == Array(repeating: nil, count: WidgetCatalog.all.count))
    }

    @Test("One habit is one card")
    func oneHabitIsOneCard() {
        let habits = Self.habitIDs(1)
        let month = monthGroup(WidgetCatalog.groups(placed: [], habits: habits))
        let previewed: [UUID?] = month.cards.map(\.habitID)
        #expect(previewed == [habits[0]])
    }

    @Test("Several habits are several cards, one each, in the person's order")
    func severalHabitsAreSeveralCards() {
        let habits = Self.habitIDs(3)
        let month = monthGroup(WidgetCatalog.groups(placed: [], habits: habits))
        let previewed: [UUID?] = month.cards.map(\.habitID)
        let expected: [UUID?] = habits
        #expect(previewed == expected)
    }

    @Test("More than three habits are all shown, in the person's order")
    func everyHabitGetsAMonthCard() {
        let habits = Self.habitIDs(9)
        let month = monthGroup(WidgetCatalog.groups(placed: [], habits: habits))
        let previewed: [UUID?] = month.cards.map(\.habitID)
        let expected: [UUID?] = habits
        #expect(month.cards.count == habits.count)
        #expect(previewed == expected)
    }

    /// The week shows every habit at once already — "which one is this?" is not
    /// a question it asks, so having habits changes nothing about it.
    @Test("The week is one card per size however many habits there are")
    func theWeekIsUnaffectedByHabits() {
        let groups = WidgetCatalog.groups(placed: [], habits: Self.habitIDs(9))
        let week = groups.filter { $0.placement.family != .systemSmall }
        let counts = week.map(\.cards.count)
        let previewed: [UUID?] = week.flatMap(\.cards).map(\.habitID)
        #expect(week.map(\.placement.family) == [.systemLarge, .systemMedium])
        #expect(counts == [1, 1])
        #expect(previewed == [nil, nil])
    }

    /// "Added" answers for the Home Screen, and the Home Screen knows nothing
    /// about which habit this page chose to illustrate with. One placed month
    /// widget is one placed widget however many previews sit under the row.
    @Test("Added stays a fact about the placement, not about a preview")
    func addedIsPerPlacementNotPerCard() {
        let groups = WidgetCatalog.groups(
            placed: [PlacedWidget(kind: .week, family: .systemSmall)],
            habits: Self.habitIDs(3)
        )
        let month = monthGroup(groups)
        let wide = groups.filter { $0.placement.family != .systemSmall }.map(\.isPlaced)
        #expect(month.isPlaced)
        #expect(month.cards.count == 3)
        #expect(month.cards.map(\.isPlaced) == [true, true, true])
        #expect(wide == [false, false])
    }

    /// `ForEach` draws one row per id: two cards sharing one is a preview that
    /// silently does not appear.
    @Test("Every card on the page has its own identity")
    func cardIdentitiesAreDistinct() {
        let cards = WidgetCatalog.cards(placed: [], habits: Self.habitIDs(3))
        let ids = Set(cards.map(\.id))
        #expect(ids.count == cards.count)
        // Identity is the card, not its state — an "Added" that flips must not
        // replace the row.
        let placed = WidgetCatalog.cards(
            placed: [PlacedWidget(kind: .week, family: .systemSmall)],
            habits: Self.habitIDs(0)
        )
        let empty = WidgetCatalog.cards(placed: [], habits: Self.habitIDs(0))
        #expect(placed.map(\.id) == empty.map(\.id))
        #expect(placed.map(\.isPlaced) != empty.map(\.isPlaced))
    }

    @Test("A habit listed twice is previewed once")
    func duplicateHabitsCollapse() {
        let id = UUID()
        let month = monthGroup(WidgetCatalog.groups(placed: [], habits: [id, id, id]))
        let previewed: [UUID?] = month.cards.map(\.habitID)
        #expect(previewed == [id])
    }

    /// The flat list the page used to be is still the groups, in order.
    @Test("The flat list is the groups' cards end to end")
    func cardsAreTheGroupsFlattened() {
        let habits = Self.habitIDs(3)
        let groups = WidgetCatalog.groups(placed: [], habits: habits)
        let flat = WidgetCatalog.cards(placed: [], habits: habits)
        #expect(flat == groups.flatMap(\.cards))
        #expect(flat.count == WidgetCatalog.all.count - 1 + habits.count)
    }

    // MARK: - The words the page and the gallery share

    /// The gallery's display name is built from `displayName`, and the page
    /// shows the same string. One list, so a widget cannot be called two
    /// things.
    ///
    /// `summary` is the gallery's alone since #237 — the Widgets tab stopped
    /// printing it — but `GlowWidget` and `MonthWidget` still pass it to
    /// `.description(_:)`, so an empty one is a widget with no sentence in the
    /// gallery.
    @Test("Every kind names itself and says what it is")
    func kindsCarryTheirWords() {
        for kind in WidgetKind.allCases {
            #expect(!kind.displayName.isEmpty)
            #expect(!kind.summary.isEmpty)
            #expect(!kind.families.isEmpty)
        }
        #expect(WidgetKind.week.displayName == "This Week")
    }

    /// The gallery title is the app's name and the kind's, in that order.
    @Test("The gallery title puts the app in front of the kind")
    func galleryNameCarriesTheApp() {
        #expect(WidgetKind.week.galleryName == "Glow Up: This Week")
        for kind in WidgetKind.allCases {
            #expect(kind.galleryName.hasSuffix(kind.displayName))
        }
    }

    /// **No widget's gallery strings may be interpolated string literals** —
    /// #254, which crash-looped the extension on a physical device for the best
    /// part of an hour and left it out of the widget gallery entirely.
    ///
    /// `configurationDisplayName(_:)` and `description(_:)` are overloaded on
    /// `LocalizedStringKey` and on `StringProtocol`. A bare literal picks the
    /// first, and a `LocalizedStringKey` holding an interpolated segment is
    /// *formatted text*, which WidgetKit refuses: `WidgetKit/Text.swift` traps
    /// with "Formatted text for `…` is not supported", inside its own
    /// evaluation of the widget's body. A `String` property picks the second
    /// overload and is plain text. #210 turned two literals into interpolated
    /// ones and that is the entire bug — `.description(_:)` was never affected
    /// because `summary` was already a property.
    ///
    /// A source scan for the same reason `TestRunnerContractTests` uses them:
    /// the property is which *overload* the compiler picked, and nothing at
    /// runtime in this process can observe that. The trap is in WidgetKit, in
    /// the widget's own process, and reaching it needs a phone.
    @Test("No widget's gallery strings are interpolated literals")
    func galleryStringsAreNotFormattedText() throws {
        let widget = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GlowWidget")
        let files = try FileManager.default.contentsOfDirectory(
            at: widget, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        // The scan is only worth anything if it found the directory.
        #expect(files.count > 3, "GlowWidget looks wrong: \(files.count) files")

        var seen = 0
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let code = line.trimmingCharacters(in: .whitespaces)
                // Doc comments here name the modifiers constantly, saying what
                // must not be passed to them.
                guard !code.hasPrefix("//") else { continue }
                for modifier in [".configurationDisplayName(", ".description("] {
                    guard let call = code.range(of: modifier) else { continue }
                    seen += 1
                    let argument = code[call.upperBound...]
                    #expect(
                        !argument.contains("\\("),
                        """
                        \(file.lastPathComponent) passes an interpolated literal to \
                        \(modifier.dropFirst().dropLast()); WidgetKit traps on formatted \
                        text. Pass a String property instead (#254): \(code)
                        """
                    )
                }
            }
        }
        // The one widget declares both modifiers (#322 folded the month in);
        // if a rename ever makes this scan match nothing it should fail
        // rather than pass silently.
        #expect(seen >= 2, "the gallery-string scan matched \(seen) calls, expected 2")
    }

    /// **A widget mark is a `Toggle`, never a `Button(intent:)`** (#292).
    ///
    /// The distinction is invisible until the pixels lag: both perform the
    /// same intent, but only an AppIntent-backed `Toggle` is drawn
    /// optimistically by the system while `perform()` runs. A mark that slides
    /// back to `Button` compiles, renders identically in every still frame,
    /// and quietly reopens the seconds-long wait (#121) that made people tap
    /// their completions back off (#272). Nothing at runtime in this process
    /// can see the difference, so — like the gallery-string scan above — the
    /// source is the only place to hold it.
    @Test("The widget's marks are Toggles, not intent Buttons")
    func marksAreTogglesNotButtons() throws {
        let widget = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GlowWidget")
        let files = try FileManager.default.contentsOfDirectory(
            at: widget, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        #expect(files.count > 3, "GlowWidget looks wrong: \(files.count) files")

        var toggles = 0
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                #expect(
                    !code.contains("Button(intent"),
                    """
                    \(file.lastPathComponent) wraps a mark in Button(intent:), which \
                    renders the stale state until the provider runs. Use SlotToggle, \
                    whose style draws the state the tap requested (#292): \(code)
                    """
                )
                if code.contains("SlotToggle(") { toggles += 1 }
            }
        }
        // The week slot, the week span and the month cell. If a rename ever
        // makes this scan match nothing it should fail rather than pass
        // silently.
        #expect(toggles >= 3, "the mark scan found \(toggles) SlotToggles, expected 3")
    }

    /// The app does not wrap the production widget views in its own gesture.
    /// `SlotToggle` keeps the AppIntent adapter for WidgetKit and supplies the
    /// ordinary binding adapter an app-hosted view needs (#477). The modifiers
    /// are a source-level contract because hit testing is not represented in a
    /// still render; the hosted accessibility test performs the real control.
    @Test("The Widgets tab leaves production controls interactive")
    func inAppPreviewsKeepTheProductionControls() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let widgets = try String(
            contentsOf: root.appendingPathComponent("Glow/Views/WidgetsView.swift"),
            encoding: .utf8
        )
        let slotToggle = try String(
            contentsOf: root.appendingPathComponent("GlowWidget/SlotToggle.swift"),
            encoding: .utf8
        )
        let previewStart = try #require(widgets.range(of: "private func preview("))
        let previewTail = widgets[previewStart.lowerBound...]
        let previewEnd = try #require(previewTail.range(of: "private static var designGutter"))
        let preview = previewTail[..<previewEnd.lowerBound]

        #expect(!preview.contains(".allowsHitTesting(false)"))
        #expect(!preview.contains(".accessibilityHidden(true)"))
        #expect(widgets.contains("WeekWidgetView("))
        #expect(widgets.contains("entry: projection.weekEntry"))
        #expect(widgets.contains("MonthWidgetView(entry:"))
        let month = try String(
            contentsOf: root.appendingPathComponent("GlowWidget/MonthWidgetView.swift"),
            encoding: .utf8
        )
        #expect(month.contains("WidgetMetrics.monthTitleHeight"))
        #expect(!month.contains("WidgetMetrics.headerHeight"))
        #expect(slotToggle.contains("Toggle(isOn: isDone, intent: MarkHabitIntent("))
        #expect(slotToggle.contains("Toggle(isOn: Binding("))
        #expect(slotToggle.contains("handlesPresses: false"))
        #expect(slotToggle.contains("handlesPresses: true"))
        #expect(slotToggle.contains("Button { configuration.isOn.toggle() }"))
        #expect(slotToggle.contains("widget-preview-mark-"))
        #expect(widgets.contains("MarkHabitOperation.perform("))
    }

    /// Week and month share one bounded editing horizon now (#526). Source is
    /// the boundary here: a still render cannot reveal which day an archived
    /// AppIntent will write when its control is tapped.
    @Test("Week and month controls carry their own nonfuture day")
    func widgetDaysAreExplicitAndBounded() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }

        let week = try source("GlowWidget/WeekWidgetView.swift")
        let monthGrid = try source("Glow/Logic/MonthGrid.swift")
        let toggle = try source("GlowWidget/SlotToggle.swift")
        let intent = try source("Glow/Store/MarkHabitIntent.swift")

        #expect(week.components(separatedBy: ".week(allowingFuture: false)").count >= 3)
        #expect(monthGrid.contains("SlotEditing.week(allowingFuture: false)"))
        #expect(!monthGrid.contains("editing: .todayOnly"))
        #expect(toggle.contains("day: day"))
        #expect(toggle.contains("renderedDay: renderedDay"))
        #expect(intent.contains("@Parameter(title: \"Day\")"))
        #expect(intent.contains("@Parameter(title: \"Rendered Day\")"))
        #expect(intent.contains("guard surface == actual"))
        #expect(intent.contains("guard requested <= actual"))
    }

    /// Rasterization is selected by the host, not baked into the production
    /// widget view. The default therefore protects WidgetKit's independently
    /// baselined archive path, while the scrolling app host flattens only the
    /// socket background beneath the unchanged `SlotToggle` (#479).
    @Test("Only the scrolling app host flattens widget sockets")
    func widgetSocketFlatteningIsHostScoped() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }

        let widgets = try source("Glow/Views/WidgetsView.swift")
        let mark = try source("Glow/Views/SlotMarkView.swift")
        let toggle = try source("GlowWidget/SlotToggle.swift")

        #expect(EnvironmentValues().flattensWidgetSockets == false)
        #expect(widgets.contains(".environment(\\.flattensWidgetSockets, true)"))
        #expect(mark.contains(
            ".flattened(flattensSocket || flattensWidgetSockets)"
        ))
        #expect(mark.contains("if flattens { drawingGroup() } else { self }"))
        #expect(mark.contains(".allowsHitTesting(false)"))
        #expect(!toggle.contains("drawingGroup"), "the interactive control must stay live")
    }

    /// AppIntent writes happen through a peer container. The system's
    /// optimistic face is immediate; this local signal is what makes both live
    /// app tabs fetch the final answer afterwards, including a refusal or a
    /// duplicate delivery.
    @Test("An intent result reconciles both live app surfaces")
    func intentResultHasAReconciliationPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }

        #expect(try source("Glow/Store/MarkHabitIntent.swift").contains(
            "NotificationCenter.default.post(name: StoreChange.fromIntent"
        ))
        for path in ["Glow/Views/WidgetsView.swift", "Glow/Views/WeeklyGridView.swift"] {
            #expect(try source(path).contains(
                "NotificationCenter.default.publisher(for: StoreChange.fromIntent)"
            ))
        }
    }

    /// The stable sizes are the authored design coordinate system. Device
    /// frames are recorded separately by WidgetKit; changing one must not
    /// silently rewrite the other or its render baselines (#544).
    @Test("Each family has the size the design is authored against")
    func familySizes() {
        #expect(WidgetMetrics.size(of: .systemSmall)
            == CGSize(width: WidgetMetrics.smallSide, height: WidgetMetrics.smallSide))
        #expect(WidgetMetrics.size(of: .systemMedium)
            == CGSize(width: WidgetMetrics.largeWidth, height: WidgetMetrics.smallSide))
        #expect(WidgetMetrics.size(of: .systemLarge)
            == CGSize(width: WidgetMetrics.largeWidth, height: WidgetMetrics.largeHeight))
    }
}


/// #274: a Small widget has a neighbour on a real Home Screen, and the page
/// used to draw it a column.
@Suite("Widget preview layout")
struct WidgetPreviewLayoutTests {
    private func group(_ family: WidgetFamily, cards: Int) -> WidgetCardGroup {
        let placement = WidgetPlacement(kind: .week, family: family)
        return WidgetCardGroup(
            placement: placement,
            isPlaced: false,
            cards: (0..<cards).map {
                _ in WidgetCard(placement: placement, isPlaced: false, habitID: UUID())
            }
        )
    }

    @Test("Two Smalls to a line, because two fit in a Medium's width")
    func smallsPairUp() {
        // Not a written-down 2: `smallSide` is 158 and `largeWidth` is 338, so
        // two fit and three do not. If either number moves this moves with it.
        #expect(WidgetMetrics.perRow(.systemSmall) == 2)
        #expect(group(.systemSmall, cards: 4).rows.map(\.count) == [2, 2])
    }

    @Test("A trailing odd card is a line of its own, not a stretched one")
    func oddCardStandsAlone() {
        // Any odd count can now reach this layout (#465); three is the smallest
        // one that proves the final card keeps one widget's width.
        #expect(group(.systemSmall, cards: 3).rows.map(\.count) == [2, 1])
        #expect(group(.systemSmall, cards: 1).rows.map(\.count) == [1])
        #expect(group(.systemSmall, cards: 0).rows.isEmpty)
    }

    @Test("Medium and Large fill the width, so they are lines of one")
    func wideFamiliesStayStacked() {
        #expect(WidgetMetrics.perRow(.systemMedium) == 1)
        #expect(WidgetMetrics.perRow(.systemLarge) == 1)
        #expect(group(.systemMedium, cards: 3).rows.map(\.count) == [1, 1, 1])
    }

    @Test("Every card survives the split, in order")
    func rowsLoseNothing() {
        let g = group(.systemSmall, cards: 5)
        #expect(g.rows.flatMap { $0 } == g.cards)
    }

    /// The rule still holds, and it is no longer the Widgets tab that needs it.
    ///
    /// The page used to inject `.accented` into its previews, and this test was
    /// kept for that reader. It renders `fullColor` now, matching a Default Home
    /// Screen (#369) — but the *widget* still renders accented whenever the Home
    /// Screen is set to Tinted or Clear, which is the appearance this resolution
    /// exists for. `WidgetAppearance` and its picker are gone (#312); the rule
    /// they exercised outlived both. The rest of the grey's behaviour is
    /// `WidgetBackgroundTests`.
    @Test("Accented rendering resolves the grey to the alpha-stored one")
    @MainActor
    func accentedRenderingKeepsTheHierarchy() {
        // The whole reason `GlowPalette.grey` is a `ShapeStyle` and not a
        // `Color`: under accented the system keeps only alpha, so an opaque
        // grey would come back as a lit mark and the hierarchy would collapse
        // into one tone.
        var environment = EnvironmentValues()
        environment.widgetRenderingMode = .accented
        #expect(GlowPalette.grey.resolve(in: environment) == GlowPalette.greyAccented)

        environment.widgetRenderingMode = .fullColor
        #expect(GlowPalette.grey.resolve(in: environment) == GlowPalette.greyResting)
    }
}
