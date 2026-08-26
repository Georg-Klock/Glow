import Foundation

/// Where an export lives between being written and being shared.
///
/// **A history file is the most sensitive thing this app can produce**, and the
/// feature's whole promise is that it leaves the device only when a person
/// makes it leave. A copy sitting in the temporary directory for the rest of
/// the install is not a breach of that promise, but it is the kind of leftover
/// the promise is supposed to rule out — so the file's lifetime is now as
/// explicit as its creation (#142).
///
/// **Its own subdirectory, and that is the safety property.** Sweeping means
/// deleting things nobody asked to keep, and a sweep of
/// `FileManager.temporaryDirectory` itself would reach files this app never
/// wrote. Everything here is scoped to one folder this type owns, and
/// `discard` refuses a URL from anywhere else.
///
/// The directory is injected so a test can point it somewhere disposable and
/// assert what is left on disk, which is the only way to test a cleanup.
struct ExportStore {
    /// The folder this type owns. Nothing outside it is ever written or removed.
    let directory: URL
    private let fileManager: FileManager

    init(
        base: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) {
        self.directory = base.appendingPathComponent("HistoryExports", isDirectory: true)
        self.fileManager = fileManager
    }

    /// Writes one export and returns where it went.
    ///
    /// Sweeps first. That is the fallback for the case no dismissal handler can
    /// cover — the app being killed while the share sheet is up — and it costs
    /// nothing, because by the time a second export is being written the first
    /// one has no reader left.
    func write(_ text: String, named name: String) throws -> URL {
        sweep()
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// One export, end to end: read, render, write — or nothing (#282).
    ///
    /// **All or nothing is the whole contract.** The snapshots arrive through
    /// a throwing closure so that a failed completion fetch stops the export
    /// *before* anything exists on disk — the old path had already flattened
    /// fetch failures into empty history by the time the file was written, so
    /// a person could share a file silently missing rows. Here the order is
    /// fixed: every habit and every completion is read, the whole text is
    /// rendered in memory, and only then does a file get a name. A throw at
    /// any step leaves the directory exactly as the sweep left it: no partial
    /// file, nothing to share, and an error the caller must surface.
    func writeHistory(
        format: HistoryExport.Format,
        exportedAt: Date,
        snapshots: () throws -> [HabitSnapshot]
    ) throws -> URL {
        let file = try HistoryExport.file(
            habits: try snapshots(), format: format, exportedAt: exportedAt
        )
        return try write(file.text, named: file.name)
    }

    /// Removes one export, if it is one of ours.
    ///
    /// Called when the share sheet goes away, whether it was used or cancelled —
    /// those are the same event as far as the file is concerned, and treating
    /// them separately is how one of them gets missed.
    func discard(_ url: URL) {
        guard owns(url) else { return }
        try? fileManager.removeItem(at: url)
    }

    /// Removes everything left behind.
    func sweep() {
        guard let left = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for file in left { try? fileManager.removeItem(at: file) }
    }

    /// Whether this URL is a file in this store's own directory.
    ///
    /// Compared by resolved path and by parent, so neither a symlink nor a
    /// `../` in the name can point `discard` at something else.
    func owns(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
            == directory.standardizedFileURL.resolvingSymlinksInPath()
    }
}
