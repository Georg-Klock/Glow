import SwiftUI
import WidgetKit

/// How a Home Screen renders a widget, as the Widgets tab offers it (#273).
///
/// **The app cannot ask which appearance the Home Screen is set to.** There is
/// no trait, environment value or WidgetKit call that reports it: checked
/// against the iOS 26.5 SDK's `SwiftUICore.swiftinterface` and
/// `WidgetKit.swiftinterface`, not against memory. `widgetRenderingMode` is the
/// nearest thing, and it is populated by WidgetKit only for a widget WidgetKit
/// is rendering — inside the app it reads `.fullColor` whatever the Home Screen
/// is doing. So the page cannot match the device, and this is a choice the
/// person makes instead.
///
/// **Two cases, and Tinted and Clear are one of them.** #273 asked whether the
/// page should offer Default, Tinted and Clear separately. It should not, and
/// the reason is measured rather than argued: both put the widget into
/// `.accented` rendering, so the *content* of those two previews is the same by
/// construction, and the panel behind is the system's — composited out of a
/// wallpaper this app cannot see. Rendered with SwiftUI's own `Glass.regular`
/// against `Glass.clear` over the page's stand-in plate, the two came out
/// **pixel-identical inside a preview card**: 0.0% of pixels differing by more
/// than 6/255, maximum difference 1. Two segments that draw the same picture
/// would be the page claiming a distinction it cannot make, so the one segment
/// says both names.
enum WidgetAppearance: String, CaseIterable, Identifiable, Sendable {
    /// The Home Screen's Default appearance: the widget's own background,
    /// composited opaquely.
    case standard
    /// Tinted and Clear, which are one case here: the system drops the
    /// declared background and substitutes glass, and renders accented.
    case glass

    var id: String { rawValue }

    /// The words the Home Screen's own settings use, so somebody can find
    /// themselves in the picker.
    var displayName: String {
        switch self {
        case .standard: "Default"
        case .glass: "Tinted or Clear"
        }
    }

    /// The rendering mode the system puts a widget into under this appearance.
    ///
    /// Injected into the preview's environment, which is what makes these
    /// previews the real thing rather than a drawing of it: `GlowPalette.grey`
    /// is a `ShapeStyle` and resolves against exactly this value, so the marks
    /// switch to the alpha-stored grey here by the same line of code that runs
    /// on a Home Screen.
    var renderingMode: WidgetRenderingMode {
        switch self {
        case .standard: .fullColor
        case .glass: .accented
        }
    }

    /// Whether the system keeps the widget's declared background, or drops it
    /// and substitutes glass.
    ///
    /// `GlowWidget`'s `containerBackground` is only what a person sees under
    /// Default; under the other appearance the system removes it (#53).
    var keepsDeclaredBackground: Bool { self == .standard }
}
