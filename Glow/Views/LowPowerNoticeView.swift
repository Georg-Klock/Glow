import SwiftUI

/// The amber notice: Low Power Mode is on, so the glow is not.
struct LowPowerNoticeView: View {
    let headroom: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "bolt.slash.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(GlowPalette.warning)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)

                    Text("Low Power Mode is on, so the glow is off")
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("""
                    Today's unfinished slot is drawn as an HDR image — that is what lets it be brighter \
                    than the white the screen normally allows. Low Power Mode reduces how far above white \
                    iOS will go, so the slot tone-maps back to ordinary white and stops standing out.

                    Nothing is broken and nothing is lost. Every habit still logs with a tap, and the \
                    glow returns the moment Low Power Mode goes off.
                    """)
                    .foregroundStyle(.secondary)

                    LabeledContent("Headroom right now") {
                        Text(String(format: "%.1f×", headroom))
                            .monospacedDigit()
                            .foregroundStyle(headroom > 1.05 ? Color.primary : GlowPalette.warning)
                    }
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.fill.tertiary)
                    }

                    Text("Anything at or near 1.0× means the display is granting no extra brightness at all. Turn Low Power Mode off in Settings → Battery.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Glow paused")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The amber a Low Power surface is drawn in, in one place.
///
/// Two surfaces carry this now — the grid's strip and Settings' preview tile
/// (#396) — and they are the same notice in two footprints rather than two
/// notices. A second hand-typed copy of a fill, a border and their two
/// opacities is a second thing to forget the next time one of them moves, so
/// there is one, and the shape is the only thing the caller chooses.
private extension View {
    func lowPowerSurface(_ shape: some InsettableShape) -> some View {
        background { shape.fill(GlowPalette.warning.opacity(0.16)) }
            .overlay { shape.strokeBorder(GlowPalette.warning.opacity(0.45), lineWidth: 1) }
    }
}

/// What both surfaces say to VoiceOver, which is the same sentence because
/// they report the same condition and open the same sheet.
private let lowPowerAccessibilityLabel =
    "Low Power Mode is on. The glow is paused. Tap for details."

/// The persistent amber strip on the grid while Low Power Mode is on.
///
/// A modal is shown once when it switches on; this stays for as long as the
/// condition does, because the reason the app looks different is still true.
struct LowPowerBanner: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.slash.fill")
                    .foregroundStyle(GlowPalette.warning)
                Text("Low Power Mode is on — the glow is paused")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .lowPowerSurface(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lowPowerAccessibilityLabel)
    }
}

/// The amber tile Settings draws in place of its glow preview.
///
/// **Exactly the preview's own footprint** (#396), which is the whole
/// specification: under Low Power Mode the HDR tile tone-maps back to ordinary
/// white, so the one object on the screen that exists to demonstrate the
/// slider becomes a flat white lozenge that says nothing about why. The grid
/// answers the same condition with a strip across the top of it. There is no
/// room for a strip here and no reason for one — the thing that stopped
/// working is a single object, so the notice is drawn where that object was,
/// in its size and its capsule.
///
/// It replaces the tile rather than covering it. An overlay would leave the
/// misleading white underneath and only annotate it; what is true is that
/// there is no glow to preview right now.
struct LowPowerPreviewNotice: View {
    /// The preview's own size, passed in rather than repeated here: the tile
    /// this stands in for is measured by the view that draws it.
    let size: CGSize
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.slash.fill")
                Text("Glow paused")
            }
            .font(.footnote)
            .foregroundStyle(GlowPalette.warning)
            .frame(width: size.width, height: size.height)
            .lowPowerSurface(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lowPowerAccessibilityLabel)
    }
}
