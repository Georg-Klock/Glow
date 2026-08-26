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
            #expect(families == kind.families, "\(kind) offers \(families)")
        }
    }

    /// The catalog is the gallery's list, so the week's two sizes are two
    /// entries and not one. **It was three until PR #277 dropped Week-Small.**
    @Test("The week is two placeable widgets, the month one")
    func weekIsTwoWidgets() {
        let week = WidgetCatalog.all.filter { $0.kind == .week }
        #expect(week.map(\.family) == [.systemMedium, .systemLarge])
        #expect(WidgetCatalog.all.filter { $0.kind == .month }.map(\.family) == [.systemSmall])
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
            PlacedWidget(kind: .month, family: .systemSmall),
        ])
        let placed = Set(cards.filter(\.isPlaced).map(\.placement))
        #expect(placed == [
            WidgetPlacement(kind: .week, family: .systemMedium),
            WidgetPlacement(kind: .week, family: .systemLarge),
            WidgetPlacement(kind: .month, family: .systemSmall),
        ])
    }

    @Test("Two of the same size are still one Added")
    func duplicatesCollapse() {
        let cards = WidgetCatalog.cards(placed: [
            PlacedWidget(kind: .month, family: .systemSmall),
            PlacedWidget(kind: .month, family: .systemSmall),
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
            // The month widget is small only.
            PlacedWidget(kind: .month, family: .systemLarge),
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
            PlacedWidget(kind: .month, family: .systemLarge),
        ])
        #expect(cards.filter(\.isPlaced).map(\.placement)
            == [WidgetPlacement(kind: .week, family: .systemLarge)])
    }

    // MARK: - The order the page is in

    @Test("The page reads kind by kind, small to large")
    func orderFollowsTheCatalog() {
        let cards = WidgetCatalog.cards(placed: [])
        #expect(cards.map(\.placement) == WidgetCatalog.all)
        // "This Week, Small" was the first of these until PR #277.
        #expect(cards.map(\.placement.title) == [
            "This Week, Medium", "This Week, Large",
            "This Month, Small",
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
        groups.first { $0.placement.kind == .month }!
    }

    /// The axis exists on the month and does not exist on the week. #188 would
    /// give the week one; until it does, a second Week-Small preview would be
    /// the first one again.
    @Test("The month is per-habit, the week is not")
    func onlyTheMonthVaries() {
        #expect(WidgetKind.month.isPerHabit)
        #expect(!WidgetKind.week.isPerHabit)
        #expect(WidgetPlacement(kind: .month, family: .systemSmall).previewsOneHabit)
        for family in WidgetKind.week.families {
            let placement = WidgetPlacement(kind: .week, family: family)
            #expect(!placement.previewsOneHabit)
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

    /// The bound the page states. Unbounded, a fresh install's eight seeded
    /// habits would be eight full-size month renders in one section.
    @Test("More habits than the bound stop at the bound, keeping the first")
    func habitsAreBounded() {
        let habits = Self.habitIDs(9)
        let month = monthGroup(WidgetCatalog.groups(placed: [], habits: habits))
        let previewed: [UUID?] = month.cards.map(\.habitID)
        let expected: [UUID?] = Array(habits.prefix(WidgetCatalog.habitPreviewLimit))
        #expect(WidgetCatalog.habitPreviewLimit == 3)
        #expect(month.cards.count == WidgetCatalog.habitPreviewLimit)
        #expect(previewed == expected)
    }

    /// The week shows every habit at once already — "which one is this?" is not
    /// a question it asks, so having habits changes nothing about it.
    @Test("The week is one card per size however many habits there are")
    func theWeekIsUnaffectedByHabits() {
        let groups = WidgetCatalog.groups(placed: [], habits: Self.habitIDs(9))
        let week = groups.filter { $0.placement.kind == .week }
        let counts = week.map(\.cards.count)
        let previewed: [UUID?] = week.flatMap(\.cards).map(\.habitID)
        #expect(week.map(\.placement.family) == WidgetKind.week.families)
        // Two families since PR #277, not three. Compared against
        // `WidgetKind.week.families` above, so this pair moves with it.
        #expect(counts == [1, 1])
        #expect(previewed == [nil, nil])
    }

    /// "Added" answers for the Home Screen, and the Home Screen knows nothing
    /// about which habit this page chose to illustrate with. One placed month
    /// widget is one placed widget however many previews sit under the row.
    @Test("Added stays a fact about the placement, not about a preview")
    func addedIsPerPlacementNotPerCard() {
        let groups = WidgetCatalog.groups(
            placed: [PlacedWidget(kind: .month, family: .systemSmall)],
            habits: Self.habitIDs(3)
        )
        let month = monthGroup(groups)
        let weekPlacement = groups.filter { $0.placement.kind == .week }.map(\.isPlaced)
        #expect(month.isPlaced)
        #expect(month.cards.count == 3)
        #expect(month.cards.map(\.isPlaced) == [true, true, true])
        #expect(weekPlacement == [false, false])
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
            placed: [PlacedWidget(kind: .month, family: .systemSmall)],
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
        #expect(WidgetKind.month.displayName == "This Month")
    }

    /// The gallery title is the app's name and the kind's, in that order.
    @Test("The gallery title puts the app in front of the kind")
    func galleryNameCarriesTheApp() {
        #expect(WidgetKind.week.galleryName == "Glow Up: This Week")
        #expect(WidgetKind.month.galleryName == "Glow Up: This Month")
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
        // Both widgets declare both modifiers; if a rename ever makes this scan
        // match nothing it should fail rather than pass silently.
        #expect(seen >= 4, "the gallery-string scan matched \(seen) calls, expected 4")
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

    /// The sizes the previews are laid out at are the sizes the render harness
    /// renders at — one source, so a preview cannot be a layout no phone shows.
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
/// used to draw it a column. #273: which appearance the previews are drawn
/// under is a choice, because nothing reports the device's.
@Suite("Widget preview layout")
struct WidgetPreviewLayoutTests {
    private func group(_ family: WidgetFamily, cards: Int) -> WidgetCardGroup {
        let placement = WidgetPlacement(kind: .month, family: family)
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
        // #237 gives the month widget up to three cards, which is the case
        // this actually renders.
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

    @Test("Glass renders accented; Default does not")
    func appearanceDrivesTheRenderingMode() {
        // This is what makes the previews the real thing rather than a
        // drawing: `GlowPalette.grey` resolves against this value, so the
        // accented branch is the one a Home Screen runs.
        #expect(WidgetAppearance.standard.renderingMode == .fullColor)
        #expect(WidgetAppearance.glass.renderingMode == .accented)
    }

    @Test("Two appearances, because Tinted and Clear draw the same picture")
    func tintedAndClearAreOneCase() {
        // Measured, not assumed: `Glass.regular` and `Glass.clear` over the
        // page's plate came out pixel-identical inside a preview card. Two
        // segments drawing the same thing would claim a distinction the page
        // cannot make, so the one segment says both names. See
        // `WidgetAppearance`.
        #expect(WidgetAppearance.allCases.count == 2)
        #expect(WidgetAppearance.glass.displayName == "Tinted or Clear")
    }

    @Test("Only Default keeps the widget's declared background")
    func onlyDefaultKeepsTheBackground() {
        // The system drops `containerBackground` under the other appearance
        // and substitutes glass (#53), which is why the page draws a different
        // panel rather than tinting the same one.
        #expect(WidgetAppearance.standard.keepsDeclaredBackground)
        #expect(!WidgetAppearance.glass.keepsDeclaredBackground)
    }

    @Test("The grey the marks resolve to follows the appearance")
    @MainActor
    func greyFollowsTheAppearance() {
        // The whole reason `GlowPalette.grey` is a `ShapeStyle` and not a
        // `Color`: under accented the system keeps only alpha, so an opaque
        // grey would come back as a lit mark and the hierarchy would collapse
        // into one tone. Asserted here because the preview page is now a
        // second surface that can put a view into that mode.
        var environment = EnvironmentValues()
        environment.widgetRenderingMode = WidgetAppearance.glass.renderingMode
        #expect(GlowPalette.grey.resolve(in: environment) == GlowPalette.greyAccented)

        environment.widgetRenderingMode = WidgetAppearance.standard.renderingMode
        #expect(GlowPalette.grey.resolve(in: environment) == GlowPalette.greyOpaque)
    }
}
