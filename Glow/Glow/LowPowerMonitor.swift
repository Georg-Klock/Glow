import Foundation
import Observation
import UIKit

/// Watches Low Power Mode, because it switches the glow off.
///
/// This is not a guess about battery saving in general: iOS reduces extended
/// dynamic range headroom in Low Power Mode, so the HDR tile tone-maps back to
/// ordinary white and today's slot stops being distinguishable by brightness —
/// which is the app's only signal. The app keeps working; it just stops
/// glowing, and a user who does not know why would reasonably think it broke.
@Observable
@MainActor
final class LowPowerMonitor {
    private(set) var isLowPowerMode: Bool

    /// The headroom the system is currently granting, for the notice to quote.
    /// 1.0 means "no more than SDR white", which is exactly the failure being
    /// explained.
    var currentHeadroom: Double { Double(UIScreen.main.currentEDRHeadroom) }

    // Written once in init, read once in deinit. deinit is nonisolated, so
    // the property has to be too.
    //
    // `@ObservationIgnored` is what makes that expressible. Without it the
    // `@Observable` macro wraps this in generated accessors, and then
    // `nonisolated(unsafe)` lands on the wrapper rather than on the storage —
    // which is why the compiler said it had no effect, and why its own
    // suggestion of plain `nonisolated` did not compile either ("cannot be
    // applied to mutable stored properties", from inside the macro expansion).
    // Nothing observes a notification token anyway.
    @ObservationIgnored
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init() {
        isLowPowerMode = Self.readCurrentState()
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Re-reads the flag. Called on the power-state notification and whenever
    /// the app becomes active, because the notification does not arrive while
    /// the app is suspended.
    func refresh() {
        let now = Self.readCurrentState()
        if now != isLowPowerMode { isLowPowerMode = now }
    }

    private static func readCurrentState() -> Bool {
        #if DEBUG
        // Low Power Mode cannot be toggled in the Simulator, and draining a
        // real battery to check a banner is not a workflow. Launch with
        // -glow-force-low-power to see it.
        if ProcessInfo.processInfo.arguments.contains("-glow-force-low-power") {
            return true
        }
        #endif
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
