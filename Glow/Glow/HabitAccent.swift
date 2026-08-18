import SwiftUI

/// The per-habit accent. Also the glow colour: the decision was one accent per
/// habit rather than a single app-wide glow, so a row is identifiable by colour
/// before you read its name. See docs/decisions.md.
enum HabitAccent: String, CaseIterable, Identifiable, Sendable, Codable {
    case teal, violet, amber, rose, lime, sky

    var id: String { rawValue }

    /// Linear-ish sRGB components, used both for SwiftUI and for the Core Image
    /// glow render, so the SDR shape and the HDR shape are the same colour.
    var components: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .teal: (0.16, 0.85, 0.78)
        case .violet: (0.62, 0.47, 1.00)
        case .amber: (1.00, 0.72, 0.22)
        case .rose: (1.00, 0.40, 0.56)
        case .lime: (0.62, 0.92, 0.32)
        case .sky: (0.36, 0.70, 1.00)
        }
    }

    var color: Color {
        let rgb = components
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    var displayName: String {
        switch self {
        case .teal: "Teal"
        case .violet: "Violet"
        case .amber: "Amber"
        case .rose: "Rose"
        case .lime: "Lime"
        case .sky: "Sky"
        }
    }
}
