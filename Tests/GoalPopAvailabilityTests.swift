import Foundation
import Testing
import UIKit
@testable import Glow

/// #661: no Dynamic Island, no goal pop — and no Live Activity request.
///
/// The rule is `GoalPopAvailability`. What makes it hold is that it sits in
/// front of every request: on an iPad, ActivityKit reports enabled and
/// accepts the request, so a path that skipped the rule would not fail — it
/// would put a card on the Lock Screen behind a permission prompt, silently.
/// That is an absence of a call, so it is held the way `LocalOnlyContractTests`
/// holds its own: by reading the source.
@Suite("Goal pop availability")
struct GoalPopAvailabilityTests {
    // MARK: - The rule

    @Test("A phone is offered the pop")
    func phoneIsOffered() {
        #expect(GoalPopAvailability.isOffered(idiom: .phone))
    }

    @Test("An iPad, a Mac, and anything unknown are not", arguments: [
        UIUserInterfaceIdiom.pad, .mac, .tv, .carPlay, .vision, .unspecified,
    ])
    func everythingElseIsNot(idiom: UIUserInterfaceIdiom) {
        #expect(!GoalPopAvailability.isOffered(idiom: idiom))
    }

    // MARK: - Every request sits behind it

    private static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
    }

    /// Every production Swift source, app and widget alike: the widget
    /// extension compiles `Glow/Store`, so `GoalPopCentre` is in both.
    private static func productionSources() -> [URL] {
        var files: [URL] = []
        for folder in ["Glow", "GlowWidget"] {
            guard let walker = FileManager.default.enumerator(
                at: root.appendingPathComponent(folder),
                includingPropertiesForKeys: nil
            ) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                files.append(url)
            }
        }
        return files
    }

    /// Comment lines name the API legitimately; code must not.
    private static func code(of source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private static var request: Regex<AnyRegexOutput> {
        try! Regex(#"request\s*\(\s*attributes\s*:"#)
    }
    private static let guardSpelling =
        "GoalPopAvailability.isOffered(\n            idiom: UIDevice.current.userInterfaceIdiom"

    /// Whether `index` falls inside an `#if DEBUG` … `#endif` block.
    private static func isDebugOnly(_ index: String.Index, in code: String) -> Bool {
        let before = code[..<index]
        guard let opened = before.range(of: "#if DEBUG", options: .backwards) else {
            return false
        }
        return before[opened.upperBound...].range(of: "#endif") == nil
    }

    @Test("Every production Activity request is GoalPopCentre's, behind the rule, or Debug-only")
    func everyRequestIsGuarded() throws {
        let files = Self.productionSources()
        #expect(files.count > 30, "the scan looks wrong: \(files.count) files")

        var centreRequests = 0
        for file in files {
            let code = Self.code(of: try String(contentsOf: file, encoding: .utf8))
            for match in code.matches(of: Self.request) {
                if file.lastPathComponent == "GoalPopCentre.swift" {
                    centreRequests += 1
                    continue
                }
                // `GlowApp.debugPop` (`-glow-debug-pop`) is the affordance that
                // measured what iPadOS does with the activity; it is compiled
                // out of Release, so no person reaches it.
                #expect(
                    Self.isDebugOnly(match.range.lowerBound, in: code),
                    "\(file.lastPathComponent) requests a Live Activity outside GoalPopCentre (#661)"
                )
            }
        }
        #expect(centreRequests == 1, "GoalPopCentre should request in exactly one place")
    }

    @Test("GoalPopCentre asks the rule before it touches ActivityKit")
    func centreGuardsFirst() throws {
        let file = Self.root.appendingPathComponent("Glow/Store/GoalPopCentre.swift")
        let code = Self.code(of: try String(contentsOf: file, encoding: .utf8))

        let pop = try #require(code.range(of: "private static func pop(name: String)"))
        let body = code[pop.upperBound...]
        let rule = try #require(
            body.range(of: Self.guardSpelling),
            "pop(name:) no longer asks GoalPopAvailability with the device's idiom"
        )
        // Before the enablement check, the running-activity update and the
        // request: on iPad none of them should be reached at all.
        for later in [
            "ActivityAuthorizationInfo()",
            "Activity<GoalPopAttributes>.activities",
            "Activity.request(",
        ] {
            let site = try #require(body.range(of: later), "\(later) is missing")
            #expect(rule.lowerBound < site.lowerBound, "\(later) comes before the #661 guard")
        }
        // And `pop(name:)` is the only way in from the two public callers.
        #expect(code.components(separatedBy: "Activity.request(").count == 2)
        #expect(code.components(separatedBy: "Activity<GoalPopAttributes>.activities.first").count == 2)
    }

    @Test("Settings draws the Encouragement section only where the pop is offered")
    func settingsSectionIsGuarded() throws {
        let file = Self.root.appendingPathComponent("Glow/Views/SettingsView.swift")
        let code = Self.code(of: try String(contentsOf: file, encoding: .utf8))

        let rule = try #require(code.range(of: "if GoalPopAvailability.isOffered("))
        for part in [#"Picker("Encouragement""#, #"Text("Encouragement")"#, "Text(popNote)"] {
            let site = try #require(code.range(of: part), "\(part) is missing")
            #expect(rule.lowerBound < site.lowerBound, "\(part) is drawn outside the #661 guard")
        }
        #expect(code.components(separatedBy: #"Text("Encouragement")"#).count == 2)
    }
}
