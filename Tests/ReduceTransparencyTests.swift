import Foundation
import Testing
@testable import Glow

@Suite("Reduce Transparency")
struct ReduceTransparencyTests {
    @Test("Material is replaced by an opaque surface when requested")
    func materialPolicy() {
        #expect(TransparencyPolicy.drawsMaterial(reduceTransparency: false))
        #expect(!TransparencyPolicy.drawsMaterial(reduceTransparency: true))
    }

    @Test("Every translucent shipping surface reads the setting")
    func everySurfaceIsGuarded() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let expected = [
            "Glow/Views/WeeklyGridView.swift",
            "Glow/Views/WidgetsView.swift",
            "Glow/Views/SymbolPickerView.swift",
            "GlowWidget/GlowWidget.swift",
        ]

        for path in expected {
            let source = try String(
                contentsOf: root.appendingPathComponent(path),
                encoding: .utf8
            )
            #expect(
                source.contains("accessibilityReduceTransparency"),
                "\(path) does not read Reduce Transparency"
            )
        }
    }
}
