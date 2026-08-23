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

    // MARK: - The words the page and the gallery share

    /// The gallery's display name is built from `displayName`, and the page
    /// shows the same string. One list, so a widget cannot be called two
    /// things.
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
