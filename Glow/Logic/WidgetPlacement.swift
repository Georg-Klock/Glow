import Foundation
import WidgetKit

/// One placeable widget: a kind at one family.
///
/// **The unit is the family, not the kind** (#210). `.week` is three widgets as
/// far as the Home Screen is concerned — small, medium and large are added
/// independently, and having the medium one says nothing about whether the
/// large one is there. A page that diffs kinds tells somebody they already have
/// a widget they do not have, which is worse than telling them nothing.
struct WidgetPlacement: Hashable, Identifiable, Sendable {
    let kind: WidgetKind
    let family: WidgetFamily

    var id: Self { self }

    /// The size, in the words the Home Screen's own gallery uses.
    var familyName: String {
        switch family {
        case .systemSmall: "Small"
        case .systemMedium: "Medium"
        case .systemLarge: "Large"
        // Not reachable from `WidgetKind.families`, and not worth a crash if it
        // ever becomes reachable: the raw name is ugly but true.
        default: String(describing: family)
        }
    }

    /// The card's heading on the Widgets tab (#312) — the size and the kind in
    /// one line, "Large Week Widget" — except where the previews under it are
    /// one per habit, where the heading names what the group *is*: several
    /// habits the one widget could be showing, not several widgets.
    var cardName: String {
        switch kind {
        case .week: "\(familyName) Week Widget"
        case .month: "Monthly View per Habit"
        }
    }

    /// Whether a preview of this placement is a statement about *which* habit,
    /// and therefore worth drawing more than once (#237).
    ///
    /// A property of the kind, not of the family: what makes the month worth
    /// previewing several times is `SelectWeeklyHabitIntent`, which is asked
    /// however the widget is sized. The month is small-only today, so this is
    /// exactly the Month-Small card — but the rule is the one that stays true
    /// if that changes.
    var previewsOneHabit: Bool { kind.isPerHabit }
}

/// A widget somebody has actually placed, as `WidgetCenter` reports it.
///
/// A value type rather than WidgetKit's own `WidgetInfo`, for one reason:
/// `WidgetInfo` has no public initialiser, so a test cannot make one. The kind
/// stays a `String` here because that is what comes back — including strings no
/// build of this app serves any more, such as the Today widgets #209 removed,
/// which a Home Screen can still be holding.
struct PlacedWidget: Hashable, Sendable {
    let kind: String
    let family: WidgetFamily

    init(kind: String, family: WidgetFamily) {
        self.kind = kind
        self.family = family
    }

    /// The convenience the app uses, where the kind is one this build ships.
    init(kind: WidgetKind, family: WidgetFamily) {
        self.init(kind: kind.rawValue, family: family)
    }
}

/// One preview on the Widgets tab: a widget this app ships, whether it is on
/// the Home Screen, and — where the widget shows one habit somebody picks —
/// which habit this particular preview draws.
struct WidgetCard: Hashable, Identifiable, Sendable {
    let placement: WidgetPlacement
    let isPlaced: Bool

    /// The habit this preview draws, on a placement that `previewsOneHabit`.
    ///
    /// `nil` everywhere else, and also on a per-habit placement with nothing
    /// to draw yet — somebody with no weekly habits still gets one card, so
    /// the widget's own empty state is what they see rather than a heading
    /// with nothing under it (#237).
    let habitID: UUID?

    init(placement: WidgetPlacement, isPlaced: Bool, habitID: UUID? = nil) {
        self.placement = placement
        self.isPlaced = isPlaced
        self.habitID = habitID
    }

    /// What the card *is*, not what it currently says. `isPlaced` is
    /// deliberately outside the identity: it flips whenever somebody places a
    /// widget and comes back to the app, and a row whose identity flips with
    /// it is a row SwiftUI tears down and rebuilds instead of updating.
    struct ID: Hashable, Sendable {
        let placement: WidgetPlacement
        let habitID: UUID?
    }

    var id: ID { ID(placement: placement, habitID: habitID) }
}

/// One placeable widget as the page presents it: the row of text naming it,
/// and every preview under that row.
///
/// A group rather than a flat list, because "Small" and "Added" are facts
/// about the **placement** — one month widget, on the Home Screen or not —
/// while the previews beneath are several habits that one widget could be
/// showing. Printed once per card, "Added" would claim three widgets are
/// placed when one is (#237); printed once per group, it says what
/// `WidgetCenter` actually reported.
struct WidgetCardGroup: Hashable, Identifiable, Sendable {
    let placement: WidgetPlacement
    let isPlaced: Bool
    let cards: [WidgetCard]

    var id: WidgetPlacement { placement }
}

extension WidgetCardGroup {
    /// The cards as the page lays them out: as many to a line as the Home
    /// Screen puts side by side (#274).
    ///
    /// A real Home Screen is a grid, and two Small widgets occupy the footprint
    /// of one Medium — which is a fact `WidgetMetrics` already encodes, since
    /// `smallSide` is 158 and `largeWidth` is 338. The page used to stack every
    /// preview one per line regardless, so a run of Small cards read as a
    /// column of widgets nobody's Home Screen looks like.
    ///
    /// Medium and Large fill the width and have no neighbour to sit beside, so
    /// they are lines of one and this is a no-op for them.
    ///
    /// A trailing odd card is a line of its own rather than being stretched or
    /// centred: it is one widget, at one widget's size, in the place the next
    /// one would go.
    var rows: [[WidgetCard]] {
        let width = WidgetMetrics.perRow(placement.family)
        guard width > 1 else { return cards.map { [$0] } }
        return stride(from: 0, to: cards.count, by: width).map {
            Array(cards[$0..<min($0 + width, cards.count)])
        }
    }
}

/// Everything this app can put on a Home Screen, and the diff against what is
/// already there.
///
/// Pure, and deliberately so: the page's one piece of reasoning is "which of
/// the widgets we ship is this person missing", and that is a set difference
/// over two lists rather than anything the view or `WidgetCenter` needs to be
/// present for. What the view supplies is the second list; where it comes from
/// is `WidgetPlacementQuerying`'s problem.
enum WidgetCatalog {
    /// Every placeable configuration, in the order the page shows them:
    /// `WidgetKind.allCases`, each kind's families **largest first** (#312) —
    /// the Large Week card leads the page. `families` itself stays smallest to
    /// largest, which is the gallery's own order; the reversal is this page's.
    /// Kinds and families both come from `WidgetKind`, so this list cannot
    /// offer a widget the bundle does not declare.
    static var all: [WidgetPlacement] {
        WidgetKind.allCases.flatMap { kind in
            kind.families.reversed().map { WidgetPlacement(kind: kind, family: $0) }
        }
    }

    /// Which of the widgets we ship the reported placements cover.
    ///
    /// Anything reported that is not in `all` is dropped rather than shown:
    /// a kind this build no longer serves (`GlowTodaySmall`, #209) and a family
    /// outside `supportedFamilies` are both things a Home Screen can be holding
    /// and this page has nothing to say about. Dropping them is what keeps the
    /// answer a statement about *this* build.
    static func placed(among reported: [PlacedWidget]) -> Set<WidgetPlacement> {
        let ours = Set(all)
        return Set(reported.compactMap { reported -> WidgetPlacement? in
            guard let kind = WidgetKind(rawValue: reported.kind) else { return nil }
            let candidate = WidgetPlacement(kind: kind, family: reported.family)
            return ours.contains(candidate) ? candidate : nil
        })
    }

    /// How many habits one per-habit widget is previewed against (#237).
    ///
    /// **The bound is three, and the reason is that the card demonstrates a
    /// choice rather than enumerating a list.** Three is the smallest count
    /// that reads as a series — one is an example, two is a pair and invites
    /// "why those two", three is plainly "one of yours, you pick". Above that
    /// the cost is real and the argument stops improving: each preview is a
    /// production `MonthWidgetView` laid out at the family's true 158pt and
    /// then scaled, so the section grows about 170pt per habit. Three keeps
    /// This Month near a screen; the eight habits a fresh install seeds would
    /// make it about 1,400pt — the same widget, longer than the rest of the
    /// page put together, which teaches nothing the third card did not.
    static let habitPreviewLimit = 3

    /// The page, top to bottom: everything we ship, grouped by placement, each
    /// group carrying whether it is already on the Home Screen — placed widgets
    /// are shown with a checkmark rather than dropped, because seeing what is
    /// already there belongs on the same page as seeing what is not.
    ///
    /// `habits` is the ordered list a per-habit widget could be showing — the
    /// person's own, which is why it arrives as a parameter read at the view
    /// boundary rather than being fetched here. Empty is a real answer and
    /// yields one card with no habit, not zero cards.
    static func groups(placed reported: [PlacedWidget], habits: [UUID] = []) -> [WidgetCardGroup] {
        let placed = placed(among: reported)
        // Two cards with one id is a `ForEach` drawing one row and warning
        // about it. The ids come from a fetch and so should already be
        // distinct; this makes "should" not load-bearing.
        var seen = Set<UUID>()
        let distinct = habits.filter { seen.insert($0).inserted }
        return all.map { placement in
            let isPlaced = placed.contains(placement)
            let cards: [WidgetCard]
            if placement.previewsOneHabit, !distinct.isEmpty {
                cards = distinct.prefix(habitPreviewLimit).map {
                    WidgetCard(placement: placement, isPlaced: isPlaced, habitID: $0)
                }
            } else {
                cards = [WidgetCard(placement: placement, isPlaced: isPlaced)]
            }
            return WidgetCardGroup(placement: placement, isPlaced: isPlaced, cards: cards)
        }
    }

    /// Every preview on the page, flat and in order.
    static func cards(placed reported: [PlacedWidget], habits: [UUID] = []) -> [WidgetCard] {
        groups(placed: reported, habits: habits).flatMap(\.cards)
    }
}

/// Where the "already placed" list comes from.
///
/// The seam exists because `WidgetCenter` is a live system service with no
/// stand-in: it answers for whatever is on the Home Screen of the device the
/// code is running on, which a test has no way to arrange. Behind this protocol
/// a test supplies a fixed list and asserts the diff; in the app,
/// `WidgetCenterPlacements` asks WidgetKit.
protocol WidgetPlacementQuerying: Sendable {
    func placedWidgets() async throws -> [PlacedWidget]
}
