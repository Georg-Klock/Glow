import Foundation
import Testing
@testable import Glow

/// #281: the local-only promise, enforced as a negative invariant rather than
/// left as a lucky alignment of defaults.
///
/// Glow is local-only today because several independent facts happen to agree:
/// no iCloud entitlement, no networking source, no third-party dependency.
/// None of them was a release-breaking invariant, and the one that is easiest
/// to lose silently is at the store API: `ModelConfiguration`'s
/// `cloudKitDatabase:` defaults to `.automatic`, so every call site that omits
/// it is asking SwiftData to find a CloudKit container — and only the absence
/// of an entitlement stops it finding one.
///
/// A source scan, the way `TestIsolationTests` asserts its claims: the
/// property is *the absence of a call*, and no runtime assertion can observe
/// an absence. The entitlement half of the invariant lives in
/// `Tools/check-project.py` and `Tools/check-release-build.py`, which reject
/// the iCloud/ubiquity keys outright; these tests hold the source half.
@Suite("Local-only contract")
struct LocalOnlyContractTests {
    /// Every production Swift source: the app target's folders and the
    /// widget's own. `Tests/` is exempt by construction — this file names the
    /// forbidden spellings constantly, and it should.
    private static func productionSources() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
        var files: [URL] = []
        for folder in ["Glow", "GlowWidget"] {
            let directory = root.appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                files.append(url)
            }
        }
        return files
    }

    /// Comment lines carry the API names legitimately; code must not.
    private static func code(of source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    @Test("Every production ModelConfiguration disables managed CloudKit")
    func storesSayNone() throws {
        let files = try Self.productionSources()
        #expect(files.count > 30, "the scan looks wrong: \(files.count) files")

        var sites = 0
        for file in files {
            let code = Self.code(of: try String(contentsOf: file, encoding: .utf8))
            var search = code.startIndex
            while let start = code.range(of: "ModelConfiguration(", range: search..<code.endIndex) {
                // The call's own argument list, by balancing the parenthesis
                // the match opened.
                var depth = 0
                var end = start.lowerBound
                for index in code.indices[start.lowerBound...] {
                    if code[index] == "(" { depth += 1 }
                    if code[index] == ")" {
                        depth -= 1
                        if depth == 0 { end = index; break }
                    }
                }
                let call = String(code[start.lowerBound...end])
                #expect(
                    call.contains("cloudKitDatabase: .none"),
                    """
                    \(file.lastPathComponent) opens a store without \
                    `cloudKitDatabase: .none`. The parameter defaults to \
                    `.automatic`, and only the missing iCloud entitlement is \
                    keeping that from meaning a sync. See #281.
                    """
                )
                sites += 1
                search = code.index(after: end)
            }
        }
        // The two known call sites: `GlowStore.container(at:readOnly:)` —
        // #283 collapsed the writable and read-only opens into that one
        // spelling, which is why this floor moved from three — and the
        // migration inventory. Fewer means the scan stopped seeing them,
        // which would make this test pass vacuously.
        #expect(sites >= 2, "only \(sites) ModelConfiguration call sites found")
    }

    /// The exact spellings #281 starts the review gate with. A match is not
    /// proof of egress — it is a reviewed rejection: either the change goes,
    /// or the allowlist below gains an entry in the same diff, with the
    /// reasoning where the next reader will find it.
    private static let forbiddenSpellings = [
        "import CloudKit", "CKContainer", "CKDatabase", "CKRecord",
        "NSPersistentCloudKitContainer", "NSUbiquitousKeyValueStore",
        "URLSession", "URLRequest", "NSURLConnection",
        "import Network", "NWConnection", "NWListener", "NWBrowser",
        "NWPathMonitor", "CFHTTPMessage", "CFReadStream", "CFWriteStream",
        "WKWebView", "SFSafariViewController",
    ]

    /// (file name, spelling) pairs a review has explicitly admitted, each with
    /// its reason here. Empty is the intended state: the audit at #281 found
    /// no production use of any spelling above.
    private static let allowed: [(file: String, spelling: String, reason: String)] = []

    @Test("No production source names a network or CloudKit API")
    func noNetworkSurface() throws {
        let files = try Self.productionSources()
        #expect(files.count > 30, "the scan looks wrong: \(files.count) files")

        for file in files {
            let code = Self.code(of: try String(contentsOf: file, encoding: .utf8))
            for spelling in Self.forbiddenSpellings {
                if Self.allowed.contains(where: {
                    $0.file == file.lastPathComponent && $0.spelling == spelling
                }) { continue }
                #expect(
                    !code.contains(spelling),
                    """
                    \(file.lastPathComponent) contains \(spelling). Glow's \
                    promise is that habit data never leaves the device except \
                    through an explicit share; if this use is deliberate, it \
                    is an allowlist entry with a reason, not a silent merge. \
                    See #281.
                    """
                )
            }
        }
    }
}
