import Foundation

/// A short record of what the widget was asked to draw, kept where a tethered
/// Mac can read it back.
///
/// It exists because a widget extension is otherwise unobservable: it runs in
/// its own process, a tap burst lasts one second, and nothing can be paused.
/// "Did you see a flash?" is not a measurement, and this branch already had one
/// animation that looked plausible and did nothing (the masked `ProgressView`
/// sweep, docs/glow.md).
///
/// `GlowLog` says the same things and is the better tool where it works, but
/// only on a Mac whose `log stream` still accepts `--device-name`; newer ones
/// dropped the flag and then there is no live view into an extension at all.
///
/// **Why UserDefaults and not a file.** The obvious shape is a log file in the
/// App Group container, and it does not survive contact with `devicectl`:
/// single-file `copy from` against `appGroupDataContainer` fails outright, and
/// the whole-directory copy silently omits files at the container root — it does
/// not even bring back `Glow.store`, which certainly exists. What it does return
/// faithfully is `Library/Preferences/<group>.plist`. So the transport is the
/// group's own defaults, which is unglamorous and actually arrives.
/// `Tools/pull-widget-log.sh` reads it.
///
/// **What it records is deliberately narrow**: habit IDs, entry counts and
/// timings. Never a habit's name, never anything a person typed. It is capped,
/// and it never leaves the phone by itself.
///
/// That paragraph was a claim rather than a property until #141. Four call
/// sites — both widget providers and both entity queries — interpolated
/// `habit.name` straight into a line, and `Tools/pull-widget-log.sh` exists
/// precisely to carry the result to a Mac. A diagnostic that quietly collects
/// what a person typed is worse than no diagnostic, and a comment saying it
/// does not is worse still.
///
/// `tag` and `resolution` are how a call site names a habit now, and
/// `WidgetTraceRedactionTests` reads this repository's own sources to check
/// that nothing has gone back to interpolating a name.
enum WidgetTrace {
    static let key = "widgetTrace"
    /// Enough for a session's worth of taps, small enough to never matter.
    static let keepLines = 60

    /// How a habit is named in the trace: by id, or `unset`.
    ///
    /// The id is already the convention on the tap lines, and it is the thing
    /// worth having — every question this trace was built to answer is about
    /// *whether the right habit reached the provider*, which an id answers and
    /// a name only answers by accident.
    static func tag(_ id: UUID?) -> String {
        id?.uuidString ?? "unset"
    }

    /// Which process wrote a line, and which run of it.
    ///
    /// **Because a single tap has been seen toggling a habit twice, 13ms
    /// apart** (#272). A human cannot tap twice in 13ms, so that was one
    /// gesture performed twice — and the trace could not say whether the two
    /// performs came from one process or from two, which is the difference
    /// between a duplicated delivery and `LiveActivityIntent`'s handover from
    /// the extension into the app running both halves.
    ///
    /// The bundle extension is the ordinary way to tell an appex from its
    /// host; the pid separates two runs of the same one. Neither is anything
    /// a person typed, so this stays inside what `WidgetTrace` records.
    static var origin: String {
        let kind = Bundle.main.bundleURL.pathExtension == "appex" ? "widget" : "app"
        return "\(kind):\(ProcessInfo.processInfo.processIdentifier)"
    }

    /// One entity query's answer: how many were asked for, and which came back.
    ///
    /// Resolution is the step that silently failed under extension-only
    /// metadata, so what it needs to record is a count and a set of ids.
    static func resolution(_ label: String, asked: [UUID], got: [UUID]) -> String {
        let ids = got.isEmpty ? "none" : got.map(\.uuidString).joined(separator: ",")
        return "\(label) resolve \(asked.count) id(s) -> \(ids)"
    }

    private static var store: UserDefaults { GlowSettings.store }

    static var lines: [String] {
        store.stringArray(forKey: key) ?? []
    }

    /// Appends one stamped line, trimming to `keepLines`.
    ///
    /// Not coordinated across processes: the app and the widget can write at the
    /// same moment and one line can lose. Acceptable for a diagnostic, and
    /// cheaper than coordinating on every timeline build.
    static func record(_ message: String, at date: Date = Date()) {
        var lines = self.lines
        lines.append("\(formatter.string(from: date))  \(message)")
        if lines.count > keepLines {
            lines.removeFirst(lines.count - keepLines)
        }
        store.set(lines, forKey: key)
    }

    static func clear() {
        store.removeObject(forKey: key)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
