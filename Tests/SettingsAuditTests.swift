import Testing
@testable import Glow

@Suite("Settings audit")
struct SettingsAuditTests {
    @Test("The export glyph is contained at the text's scale")
    func exportIconIsContained() {
        #expect(SettingsMetrics.exportIconSize == 15)
        #expect(SettingsMetrics.exportIconFrame == 18)
        #expect(SettingsMetrics.exportIconSize < SettingsMetrics.exportIconFrame)
    }
}
