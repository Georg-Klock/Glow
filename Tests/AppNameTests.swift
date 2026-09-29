import Foundation
import Testing

@testable import Glow

/// What a person is told to open is the app on their Home Screen (#629).
///
/// The rename kept "the glow" as the HDR feature's name — Settings → Glow,
/// "the glow is paused" — and moved the app to Practice. Three strings a
/// person can see still named the app Glow after it: the widget's
/// unavailable state and its spoken label, and the read failure the widget's
/// configuration sheet shows. None of them is on a screen anyone reaches in
/// normal use, which is how they outlived the rename. This scans for the
/// phrasings that can only mean the app, so the feature's name stays free.
struct AppNameTests {
    private static func productionSources() -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var files: [URL] = []
        for folder in ["Glow", "GlowWidget"] {
            guard let walker = FileManager.default.enumerator(
                at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil
            ) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                files.append(url)
            }
        }
        return files
    }

    @Test("No string a person can see names the app by its retired name")
    func noRetiredAppNameInCode() throws {
        let retired = try Regex(#""[^"\n]*(Open Glow|Glow's |Glow ?Up|GlowUp)[^"\n]*""#)
        var found: [String] = []
        let sources = Self.productionSources()
        #expect(!sources.isEmpty)
        for url in sources {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                if line.contains(retired) {
                    found.append("\(url.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    @Test("The read failure names the app on the Home Screen")
    func readFailureNamesPractice() {
        let message = GlowStore.Unreadable().errorDescription ?? ""
        #expect(message.contains("Open Practice"))
        #expect(!message.contains("Glow"))
    }
}
