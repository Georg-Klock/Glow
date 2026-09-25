import Foundation
import Testing
@testable import Glow

/// #642: headroom is read from the screen the app is on, never `UIScreen.main`.
@Suite("Headroom screen")
struct HeadroomScreenTests {
    private typealias Candidate = HeadroomScreen.Candidate<String>

    @Test("No scene means no screen, and the caller's fallback")
    func emptyPicksNothing() {
        #expect(HeadroomScreen.pick(from: [Candidate]()) == nil)
    }

    @Test("One scene is always the answer, whatever its state — the iPhone case")
    func singleSceneIsPicked() {
        for activation in [
            HeadroomScreen.Activation.foregroundActive, .foregroundInactive,
            .background, .unattached,
        ] {
            for key in [true, false] {
                let only = Candidate(activation: activation, hasKeyWindow: key, screen: "phone")
                #expect(HeadroomScreen.pick(from: [only]) == "phone")
            }
        }
    }

    @Test("The active scene outranks one that is only in the foreground")
    func activeBeatsInactive() {
        let picked = HeadroomScreen.pick(from: [
            Candidate(activation: .foregroundInactive, hasKeyWindow: true, screen: "built-in"),
            Candidate(activation: .foregroundActive, hasKeyWindow: false, screen: "external"),
        ])
        #expect(picked == "external")
    }

    @Test("A launching scene outranks a backgrounded one")
    func inactiveBeatsBackground() {
        let picked = HeadroomScreen.pick(from: [
            Candidate(activation: .background, hasKeyWindow: true, screen: "old"),
            Candidate(activation: .foregroundInactive, hasKeyWindow: false, screen: "launching"),
            Candidate(activation: .unattached, hasKeyWindow: false, screen: "detached"),
        ])
        #expect(picked == "launching")
    }

    @Test("Between two active scenes the key window's screen wins")
    func keyWindowBreaksTie() {
        let picked = HeadroomScreen.pick(from: [
            Candidate(activation: .foregroundActive, hasKeyWindow: false, screen: "built-in"),
            Candidate(activation: .foregroundActive, hasKeyWindow: true, screen: "external"),
        ])
        #expect(picked == "external")
    }

    @Test("The hosted test app finds a screen, so the SDR fallback is not what it reads")
    @MainActor
    func hostedAppHasAScreen() {
        #expect(ActiveScreen.current != nil)
    }

    /// The deprecated spelling, scanned for as `LocalOnlyContractTests` scans
    /// for CloudKit: the property is an absence, and only the source shows it.
    @Test("No production source reads UIScreen.main")
    func noMainScreen() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
        var scanned = 0
        for folder in ["Glow", "GlowWidget"] {
            let directory = root.appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                scanned += 1
                let source = try String(contentsOf: url, encoding: .utf8)
                // Comments may name the API they replaced; code may not.
                let code = source
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .joined(separator: "\n")
                #expect(
                    !code.contains("UIScreen.main"),
                    """
                    \(url.lastPathComponent) reads `UIScreen.main`, which answers \
                    for the built-in screen even when the app is on an external \
                    display, and is deprecated on iPadOS. Use \
                    `ActiveScreen.current` or `EDRHeadroomSnapshot.activeScreen`. \
                    See #642.
                    """
                )
            }
        }
        #expect(scanned > 30, "the scan looks wrong: \(scanned) files")
    }
}
