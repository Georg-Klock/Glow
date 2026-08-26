import Foundation
import Testing
@testable import Glow

/// #284: every copy of Glow's data keeps the platform's default backup and
/// file-protection attributes, and that is the policy rather than an accident.
///
/// The decision (docs/data-inventory.md, and the 2026-08-25 entry in
/// docs/decisions.md): history is phone-only and Glow makes no recovery
/// promise — but not promising recovery is not preventing it, so nothing is
/// excluded from the OS backup. And the protection class is forced, not
/// chosen: the widget must read the store while the phone is locked, which
/// only `completeUntilFirstUserAuthentication` — the default — allows.
///
/// So the enforceable invariant is an *absence*: no code moves any file off
/// the defaults. A source scan, the way #141, #168, #181 and #204 hold claims
/// a runtime assertion cannot watch — the simulator does not implement iOS
/// per-file Data Protection, so no test running there can measure what a
/// phone would enforce, and pretending to would be the worse test. What the
/// simulator *can* answer meaningfully — that a file this app writes carries
/// no backup-exclusion marker — is asserted directly.
@Suite("Backup and file-protection policy")
struct BackupPolicyTests {
    /// The checkout root, found from this file's own compile-time path.
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // the checkout
    }

    /// Every Swift source in both production targets. Tests are exempt: this
    /// file names the forbidden spellings, and a test that measures an
    /// attribute is measuring, not setting policy.
    private var productionSources: [URL] {
        ["Glow", "GlowWidget"]
            .map { root.appendingPathComponent($0, isDirectory: true) }
            .flatMap { directory -> [URL] in
                let walker = FileManager.default.enumerator(
                    at: directory, includingPropertiesForKeys: nil
                )
                let all = (walker?.allObjects as? [URL]) ?? []
                return all.filter { $0.pathExtension == "swift" }
            }
    }

    /// The spellings that would move a file off the defaults. Each is an API
    /// entry point rather than a concept, so a mention in prose cannot trip
    /// it — and comment lines are dropped anyway, since documenting the rule
    /// must not violate it.
    private static let attributeAPIs = [
        "isExcludedFromBackup",
        "NSURLIsExcludedFromBackupKey",
        "FileProtectionType",
        "NSFileProtectionKey",
        "NSFileProtectionComplete",
        "completeFileProtection",
        ".protectionKey",
    ]

    @Test("No production code sets a backup or file-protection attribute")
    func nothingMovesOffTheDefaults() throws {
        let files = productionSources
        #expect(files.count > 20, "sources not found; the scan would pass vacuously")

        var offenders: [String] = []
        for file in files {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                for api in Self.attributeAPIs where trimmed.contains(api) {
                    offenders.append("\(file.lastPathComponent):\(index + 1) \(trimmed)")
                }
            }
        }
        #expect(
            offenders.isEmpty,
            """
            an attribute API appeared; setting one is a policy change — \
            see docs/data-inventory.md before keeping it:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    @Test("No target declares a data-protection entitlement")
    func protectionClassStaysTheDefault() throws {
        // The entitlement would raise the protection class for the whole
        // container — including the store the widget must read while the
        // phone is locked. project.yml is the source; the generated
        // entitlements files are gitignored, so the scan reads what is
        // reviewed rather than what is derived from it.
        let projectYML = root.appendingPathComponent("project.yml")
        let text = try String(contentsOf: projectYML, encoding: .utf8)
        #expect(
            !text.contains("default-data-protection"),
            "a data-protection entitlement appeared; the widget reads the store while locked"
        )
        #expect(
            !text.contains("NSFileProtection"),
            "a protection class appeared in project.yml"
        )
    }

    @Test("An export carries no backup-exclusion marker")
    func exportsAreNotExcluded() throws {
        // The one attribute read the simulator answers meaningfully. The
        // export lives in tmp/, which the OS backup already skips by
        // location — the point here is that ExportStore does not *also* stamp
        // the file, because a stamped file would be evidence of code this
        // repository has decided not to have.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupPolicyTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }

        let store = ExportStore(base: base)
        let url = try store.write("date,habit\n", named: "policy-probe.csv")
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(
            values.isExcludedFromBackup != true,
            "an export was marked excluded from backup; nothing here sets attributes"
        )
    }
}
