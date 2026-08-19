import os

/// One subsystem shared by the app and the widget extension.
///
/// Exists so the widget can be *observed* rather than eyeballed. A tap burst is
/// under a second long and renders in another process; "did you see a flash?" is
/// not a measurement, and this branch has already had one animation that looked
/// plausible and did nothing (the masked ProgressView sweep, docs/glow.md). With
/// the phone tethered:
///
///     log stream --device-name "<phone>" --predicate 'subsystem == "com.georgklock.glow"'
///
/// shows the intent's write and the provider's timeline interleaved, so what the
/// widget was asked to draw is a fact rather than an impression.
///
/// Messages are marked `.public` on purpose: they carry habit IDs and entry
/// counts, never a habit's name or anything a person wrote.
enum GlowLog {
    static let widget = Logger(subsystem: "com.georgklock.glow", category: "widget")
}
