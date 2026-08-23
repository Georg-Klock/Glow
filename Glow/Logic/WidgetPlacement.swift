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

    /// What to call this one placement — "This Week, Medium".
    var title: String { "\(kind.displayName), \(familyName)" }
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

/// One row of the Widgets tab: a widget this app ships, and whether it is on
/// the Home Screen.
struct WidgetCard: Hashable, Identifiable, Sendable {
    let placement: WidgetPlacement
    let isPlaced: Bool

    var id: WidgetPlacement { placement }
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
    /// `WidgetKind.allCases` by `families`. Kinds and families both come from
    /// `WidgetKind`, so this list cannot offer a widget the bundle does not
    /// declare.
    static var all: [WidgetPlacement] {
        WidgetKind.allCases.flatMap { kind in
            kind.families.map { WidgetPlacement(kind: kind, family: $0) }
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

    /// The page, top to bottom. Everything we ship, each carrying whether it is
    /// already on the Home Screen — placed widgets are shown with a checkmark
    /// rather than dropped, because seeing what is already there belongs on the
    /// same page as seeing what is not.
    static func cards(placed reported: [PlacedWidget]) -> [WidgetCard] {
        let placed = placed(among: reported)
        return all.map { WidgetCard(placement: $0, isPlaced: placed.contains($0)) }
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
