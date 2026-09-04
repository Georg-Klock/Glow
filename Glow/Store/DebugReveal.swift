import Observation

/// Whether Settings is showing its two debug rows — Demo history and Debug:
/// Override Today — for the rest of this app session (#566).
///
/// Both rows come off the visible Data section and sit behind Apple's own
/// gesture: seven taps on the version line, the count that reveals Developer
/// Mode under Settings → General → About. This narrows #204's decision rather
/// than reversing it. #204 argued against `#if DEBUG` because that compiles the
/// capability out of every Release archive, TestFlight included, and the phone
/// is where this app is tested; nothing here is compiled out. The rows ship in
/// every build and are reachable on every install — they stop being *offered*
/// to someone who was never meant to see them.
///
/// **In memory only, on purpose.** `DebugToday` clears its override at every
/// launch so a forgotten debug tool cannot keep affecting a real store; a
/// reveal that outlived the session it was tapped in would be the same risk one
/// level up — the entry point, rather than the override, left on by accident.
/// So this is process state: no `UserDefaults`, no App Group key, nothing a
/// relaunch has to clear. `SettingsSupportTests` scans this file for a store.
///
/// One instance for the process rather than a `@State` on the Settings screen,
/// because the reveal is a session, not a screen: leaving Settings for another
/// tab and coming back must not re-hide what was revealed.
@Observable
@MainActor
final class DebugReveal {
    /// The process's one instance, which `SettingsView` reads.
    static let shared = DebugReveal()

    /// Apple's own count — the taps on Settings → General → About that reveal
    /// Developer Mode — so the gesture is recognisable to anyone who has ever
    /// found a hidden menu on iOS, not a number invented for this app.
    static let tapsToReveal = 7

    /// Whether the two debug rows are visible. Only ever moves from false to
    /// true within a session; a relaunch is what resets it.
    private(set) var isRevealed = false

    /// Taps counted so far. Never reset short of the reveal, so seven slow
    /// taps count the same as seven quick ones — Apple's gesture does not
    /// time out either.
    private(set) var taps = 0

    /// Registers one tap on the version line. Returns whether the rows are
    /// revealed after it.
    @discardableResult
    func registerTap() -> Bool {
        guard !isRevealed else { return true }
        taps += 1
        if taps >= Self.tapsToReveal { isRevealed = true }
        return isRevealed
    }
}
