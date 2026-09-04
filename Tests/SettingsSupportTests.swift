import Foundation
import Testing
@testable import Glow

/// The two small types behind Settings' version line and its hidden rows
/// (#566).
@Suite("Settings support")
struct SettingsSupportTests {
    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - The reveal

    @Test("Seven taps reveal the debug rows, six do not")
    @MainActor
    func sevenTapsReveal() {
        let reveal = DebugReveal()
        #expect(DebugReveal.tapsToReveal == 7, "Apple's own count; changing it is a decision")
        #expect(!reveal.isRevealed)
        for _ in 1..<DebugReveal.tapsToReveal {
            #expect(!reveal.registerTap())
        }
        #expect(!reveal.isRevealed)
        #expect(reveal.registerTap())
        #expect(reveal.isRevealed)
        // Once revealed, stays revealed for the session.
        #expect(reveal.registerTap())
        #expect(reveal.isRevealed)
    }

    @Test("A fresh instance starts hidden, so a relaunch hides the rows again")
    @MainActor
    func freshInstanceIsHidden() {
        let first = DebugReveal()
        for _ in 0..<DebugReveal.tapsToReveal { first.registerTap() }
        #expect(first.isRevealed)
        #expect(!DebugReveal().isRevealed)
    }

    /// The reveal must not outlive the session it was tapped in — see the
    /// type's own header and #566. Nothing that persists may be named in it.
    @Test("The reveal is process state, not a stored default")
    func revealIsNotPersisted() throws {
        let source = try String(
            contentsOf: Self.root.appending(path: "Glow/Store/DebugReveal.swift"),
            encoding: .utf8
        )
        let code = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        #expect(!code.contains("UserDefaults"))
        #expect(!code.contains("GlowSettings.store"))
        #expect(!code.contains("@AppStorage"))
        #expect(!code.contains("FileManager"))
    }

    /// The rows are hidden by visibility in `SettingsView`, not by compiling
    /// them out — #204's reasoning about TestFlight builds still holds.
    @Test("The debug rows are hidden, not compiled out")
    func rowsAreNotBehindDebugFlag() throws {
        let source = try String(
            contentsOf: Self.root.appending(path: "Glow/Views/SettingsView.swift"),
            encoding: .utf8
        )
        // Comments name `#if DEBUG` to say why it is not used; only code counts.
        let code = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        #expect(code.contains("Toggle(\"Demo history\""))
        #expect(code.contains("Toggle(\"Debug: Override Today\""))
        #expect(code.contains("if reveal.isRevealed"))
        #expect(!code.contains("#if DEBUG"))
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
