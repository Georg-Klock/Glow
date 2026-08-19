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
enum WidgetTrace {
    static let key = "widgetTrace"
    /// Enough for a session's worth of taps, small enough to never matter.
    static let keepLines = 60

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
