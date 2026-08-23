import Foundation
import Testing
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

    /// The catalog is the gallery's list, so the week's three sizes are three
    /// entries and not one.
    @Test("The week is three placeable widgets, the month one")
    func weekIsThreeWidgets() {
        let week = WidgetCatalog.all.filter { $0.kind == .week }
        #expect(week.map(\.family) == [.systemSmall, .systemMedium, .systemLarge])
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
    @Test("Each family answers for itself")
    func familiesAreIndependent() {
        let cards = WidgetCatalog.cards(placed: [
            PlacedWidget(kind: .week, family: .systemSmall),
            PlacedWidget(kind: .week, family: .systemLarge),
            PlacedWidget(kind: .month, family: .systemSmall),
        ])
        let placed = Set(cards.filter(\.isPlaced).map(\.placement))
        #expect(placed == [
            WidgetPlacement(kind: .week, family: .systemSmall),
            WidgetPlacement(kind: .week, family: .systemLarge),
            WidgetPlacement(kind: .month, family: .systemSmall),
        ])
        #expect(cards.first { $0.placement.family == .systemMedium }?.isPlaced == false)
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
        #expect(cards.map(\.placement.title) == [
            "This Week, Small", "This Week, Medium", "This Week, Large",
            "This Month, Small",
        ])
    }

    // MARK: - The seam

    @Test("The diff is whatever the querier reports")
    func queriedPlacementsFeedTheDiff() async throws {
        let stub = StubPlacements(reported: [PlacedWidget(kind: .week, family: .systemSmall)])
        let cards = WidgetCatalog.cards(placed: try await stub.placedWidgets())
        #expect(cards.filter(\.isPlaced).map(\.placement)
            == [WidgetPlacement(kind: .week, family: .systemSmall)])
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
        #expect(counts == [1, 1, 1])
        #expect(previewed == [nil, nil, nil])
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
        #expect(weekPlacement == [false, false, false])
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
