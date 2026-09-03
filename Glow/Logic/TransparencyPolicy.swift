/// Whether a translucent surface may use material.
///
/// Reduce Transparency is a system-wide request for opaque backgrounds behind
/// content. Views read the SwiftUI environment value because it updates with
/// the setting; this pure rule keeps every surface's answer identical and
/// gives tests something firmer than a screenshot of blur.
enum TransparencyPolicy {
    static func drawsMaterial(reduceTransparency: Bool) -> Bool {
        !reduceTransparency
    }
}
