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
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(GlowPalette.warning.opacity(0.16))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(GlowPalette.warning.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Low Power Mode is on. The glow is paused. Tap for details.")
    }
}
