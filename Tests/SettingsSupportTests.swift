import Foundation
import Testing
@testable import Glow

/// Settings' version line (#566), and the absence of the debug rows it used to
/// reveal (#628).
@Suite("Settings support")
struct SettingsSupportTests {
    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - No debug controls

    /// Demo history and Debug: Override Today are out of the app (#628), not
    /// hidden: guideline 2.3.1(a) does not allow hidden features, which is what
    /// the seven-tap reveal of #566 made them. Scanned rather than rendered,
    /// because the property is an absence.
    @Test("Settings offers no debug controls, hidden or otherwise")
    func noDebugControls() throws {
        let source = try String(
            contentsOf: Self.root.appending(path: "Glow/Views/SettingsView.swift"),
            encoding: .utf8
        )
        // Comments may say what used to be here; only code counts.
        let code = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        #expect(!code.contains("Demo history"))
        #expect(!code.contains("Override Today"))
        let version = try #require(code.range(of: "Text(Self.version.label)"))
        let after = code[version.upperBound...].drop { $0.isWhitespace }
        #expect(!after.hasPrefix(".onTapGesture"), "the version line is plain text")
        #expect(!FileManager.default.fileExists(
            atPath: Self.root.appending(path: "Glow/Store/DebugReveal.swift").path
        ))
    }

    // MARK: - The version

    @Test("The version line spells the pair the way About does")
    func versionLabel() {
        #expect(AppVersion(marketing: "0.1", build: "1").label == "Version 0.1 (1)")
    }

    @Test("The bundle read finds both keys in the host app")
    func versionReadsTheBundle() {
        // GlowTests is hosted by the app, so `Bundle.main` is Glow's own
        // bundle and both keys are the ones project.yml declares.
        let version = AppVersion()
        #expect(version.marketing != "?")
        #expect(version.build != "?")
        #expect(!version.marketing.isEmpty)
        #expect(!version.build.isEmpty)
    }

    @Test("A bundle without the keys reads as unknown, not empty")
    func missingKeysReadAsUnknown() throws {
        // A bundle with no Info.plist at all: any directory will do.
        let empty = try #require(Bundle(url: FileManager.default.temporaryDirectory))
        let version = AppVersion(bundle: empty)
        #expect(version.label == "Version ? (?)")
    }
}
