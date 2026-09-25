import UIKit

/// The screen the app is showing on, for reading EDR headroom (#642).
///
/// App-only: `UIApplication.shared` is unavailable to the widget extension,
/// which compiles `Glow/Glow` and `Glow/Logic` but not this folder. That is why
/// `LowPowerMonitor` lives here too.
@MainActor
enum ActiveScreen {
    /// The screen of the scene `HeadroomScreen` picks from the connected window
    /// scenes; `nil` only before any scene has connected.
    static var current: UIScreen? {
        let candidates = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map { scene in
                HeadroomScreen.Candidate(
                    activation: HeadroomScreen.Activation(scene.activationState),
                    hasKeyWindow: scene.windows.contains { $0.isKeyWindow },
                    screen: scene.screen
                )
            }
        return HeadroomScreen.pick(from: candidates)
    }
}

extension HeadroomScreen.Activation {
    init(_ state: UIScene.ActivationState) {
        switch state {
        case .foregroundActive: self = .foregroundActive
        case .foregroundInactive: self = .foregroundInactive
        case .background: self = .background
        case .unattached: self = .unattached
        @unknown default: self = .unattached
        }
    }
}
