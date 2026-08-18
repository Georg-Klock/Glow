import UIKit

/// Touch feedback for completing and un-completing.
///
/// The glow is a visual signal and it lives under your thumb at the moment you
/// tap, which is exactly where a finger hides it. A tap you can feel confirms
/// the log landed without needing to see the slot.
@MainActor
enum Haptics {
    static func completed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Deliberately lighter than completing. Undoing is a correction, not an
    /// achievement, and it should not feel like one.
    static func uncompleted() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
