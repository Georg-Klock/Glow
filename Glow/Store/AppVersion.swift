import Foundation

/// The installed build's two version numbers, read from the bundle.
///
/// `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are declared once in
/// `project.yml` and arrive here as `CFBundleShortVersionString` and
/// `CFBundleVersion`. Settings prints them as its version line (#566) and the
/// feedback mail carries them in its body (#564), so they are read in one
/// place. #317 removed the Data footer that used to carry a version paragraph
/// and noted that putting a version line somewhere would be a new decision;
/// this is that decision, recorded in docs/decisions.md under #566.
struct AppVersion: Equatable, Sendable {
    /// `MARKETING_VERSION` — what the App Store shows.
    let marketing: String
    /// `CURRENT_PROJECT_VERSION` — the build number.
    let build: String

    init(marketing: String, build: String) {
        self.marketing = marketing
        self.build = build
    }

    /// Reads both keys off a bundle. A missing key reads as `?` rather than an
    /// empty string, so a line printed from a misconfigured bundle says so
    /// instead of printing `Version  ()`.
    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        self.init(
            marketing: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?"
        )
    }

    /// Apple's own spelling of the pair, as Settings → General → About prints
    /// it: `Version 0.1 (1)`.
    var label: String { "Version \(marketing) (\(build))" }
}
