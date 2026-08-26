import Foundation
import Testing
@testable import Glow

/// #132: both executables are independently shipped, and both use a
/// required-reason API.
///
/// These read the **built bundles**, not the repository. A manifest that exists
/// in the source tree and does not reach the `.app` or the `.appex` is the
/// failure this issue is about — the file is only a declaration once it is
/// inside the thing being shipped.
@Suite("Privacy manifests")
struct PrivacyManifestTests {
    private struct Manifest {
        let tracking: Bool
        let trackingDomains: [String]
        let collected: [Any]
        let reasons: [String: [String]]

        init(_ url: URL) throws {
            let data = try Data(contentsOf: url)
            let plist = try PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: Any] ?? [:]
            tracking = plist["NSPrivacyTracking"] as? Bool ?? true
            trackingDomains = plist["NSPrivacyTrackingDomains"] as? [String] ?? []
            collected = plist["NSPrivacyCollectedDataTypes"] as? [Any] ?? []
            var found: [String: [String]] = [:]
            for entry in plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? [] {
                if let type = entry["NSPrivacyAccessedAPIType"] as? String {
                    found[type] = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
                }
            }
            reasons = found
        }
    }

    /// The host app's own bundle — the tests run inside it.
    private var appBundle: URL { Bundle.main.bundleURL }

    /// Every appex this app ships.
    private var extensions: [URL] {
        let plugIns = appBundle.appendingPathComponent("PlugIns", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: plugIns, includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.pathExtension == "appex" }
    }

    private func check(_ bundle: URL, _ label: String) throws {
        let url = bundle.appendingPathComponent("PrivacyInfo.xcprivacy")
        #expect(
            FileManager.default.fileExists(atPath: url.path),
            "\(label) ships no privacy manifest"
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let manifest = try Manifest(url)

        // Declared accurately: UserDefaults is the only required-reason family
        // either target touches, and both of its reasons are real here — the
        // App Group's defaults and the app's own.
        let userDefaults = manifest.reasons["NSPrivacyAccessedAPICategoryUserDefaults"]
        #expect(userDefaults != nil, "\(label) does not declare UserDefaults")
        #expect(userDefaults?.contains("1C8F.1") == true, "\(label) is missing the App Group reason")
        #expect(userDefaults?.contains("CA92.1") == true, "\(label) is missing the app's own reason")

        // And nothing over-declared. A manifest claiming a family the code does
        // not use is as wrong as one omitting a family it does.
        #expect(
            manifest.reasons.count == 1,
            "\(label) declares \(manifest.reasons.keys.sorted()); the audit found only UserDefaults"
        )

        // The product statement as *declared*. This is a consistency check on
        // what the manifests say, not proof of what any code does — a future
        // dependency could perform network work without touching a manifest.
        // What notices code changing is the local-only gate (#281):
        // LocalOnlyContractTests on the source, and the entitlement denylists
        // in Tools/check-project.py and Tools/check-release-build.py.
        #expect(!manifest.tracking, "\(label) declares tracking")
        #expect(manifest.trackingDomains.isEmpty)
        #expect(manifest.collected.isEmpty, "\(label) declares collected data")
    }

    @Test("The app ships an accurate manifest")
    func appManifest() throws {
        try check(appBundle, "the app")
    }

    @Test("Every extension ships its own")
    func extensionManifests() throws {
        // An appex is independently shipped, so the app's manifest does not
        // cover it — and this is the one that is easy to forget, because the
        // app's is what a reviewer looks at first.
        let found = extensions
        #expect(!found.isEmpty, "no appex found; this test would pass vacuously")
        for appex in found {
            try check(appex, appex.lastPathComponent)
        }
    }
}
