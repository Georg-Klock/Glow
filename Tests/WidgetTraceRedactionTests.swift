import Foundation
import Testing
@testable import Glow

/// #141: the trace's own doc comment said it never records a habit's name, and
/// four call sites did.
///
/// The behavioural tests below are the ordinary half. The source scan is the
/// half that matters: this is a *claim about every call site*, present and
/// future, and no unit test of `record` can make it true — the type cannot see
/// which substring of a line was somebody's habit.
@Suite("Widget trace redaction")
struct WidgetTraceRedactionTests {
    // MARK: - The redacted spellings

    @Test("A habit is named by its id, or not at all")
    func tagIsAnIdentifier() {
        let id = UUID()
        #expect(WidgetTrace.tag(id) == id.uuidString)
        #expect(WidgetTrace.tag(nil) == "unset")
    }

    @Test("A resolution records a count and ids")
    func resolutionIsCountsAndIDs() {
        let asked = [UUID(), UUID()]
        let line = WidgetTrace.resolution("query", asked: asked, got: [asked[0]])
        #expect(line == "query resolve 2 id(s) -> \(asked[0].uuidString)")
        #expect(WidgetTrace.resolution("query", asked: asked, got: []) 
            == "query resolve 2 id(s) -> none")
    }

    // MARK: - The claim itself

    /// This repository's Swift sources, found from the test file's own path.
    ///
    /// `#filePath` is the compile-time location of this file, so the four
    /// `..`s reach the checkout root on a developer machine and on CI alike.
    private var sourceFiles: [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // the checkout
        let targets = ["Glow", "GlowWidget"].map {
            root.appendingPathComponent($0, isDirectory: true)
        }
        return targets.flatMap { directory -> [URL] in
            let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil
            )
            let all = (walker?.allObjects as? [URL]) ?? []
            return all.filter { $0.pathExtension == "swift" }
        }
    }

    @Test("No trace line interpolates a habit's name")
    func noCallSiteRecordsAName() throws {
        // A whole-line check rather than a parse: every `WidgetTrace.record`
        // call in this codebase is written on one or two lines, and what is
        // being looked for — `.name` inside a traced string — is textual.
        let files = sourceFiles
        #expect(!files.isEmpty, "no sources found; the scan would pass vacuously")

        var offenders: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where line.contains("WidgetTrace.record") {
                // The call and the two lines under it, since a long call wraps.
                let window = lines[index...min(index + 2, lines.count - 1)].joined(separator: " ")
                if window.contains(".name") {
                    offenders.append(
                        "\(file.lastPathComponent):\(index + 1) \(line.trimmingCharacters(in: .whitespaces))"
                    )
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders.joined(separator: "\n"))")
    }

    @Test("The habit name on a locked surface is marked private")
    func lockScreenSurfacesRedact() throws {
        // The Live Activity is the one surface here that a locked phone shows,
        // and it prints a habit's name. `.privacySensitive()` is not something
        // a unit test can observe rendering, so this asserts the declaration —
        // which is what would go missing if someone rewrote the view.
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GlowWidget/GoalPopActivity.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let names = text.components(separatedBy: "context.state.habitName").count - 1
        let redactions = text.components(separatedBy: ".privacySensitive()").count - 1
        #expect(names > 0, "the pop stopped naming the habit; this test is stale")
        #expect(
            redactions >= names,
            "\(names) habit-name view(s), \(redactions) marked private"
        )
    }

    // MARK: - Behaviour

    @Test("The trace still records, and still trims")
    func recordingIsUnchanged() {
        // The redaction must not have broken the thing the trace is for.
        let previous = WidgetTrace.lines
        defer {
            WidgetTrace.clear()
            for line in previous { WidgetTrace.record(line) }
        }
        WidgetTrace.clear()
        for i in 0..<(WidgetTrace.keepLines + 5) { WidgetTrace.record("line \(i)") }
        #expect(WidgetTrace.lines.count == WidgetTrace.keepLines)
        #expect(WidgetTrace.lines.last?.contains("line \(WidgetTrace.keepLines + 4)") == true)
    }
}
