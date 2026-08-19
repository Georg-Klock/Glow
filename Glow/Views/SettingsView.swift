import SwiftUI

/// Settings. Currently one thing, because there is currently one thing worth
/// setting: how hard the glow pushes.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(GlowSettings.key, store: GlowSettings.store)
    private var peak: Double = GlowSettings.defaultValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // A live slot, rendered by the same code path the grid
                    // uses, so the slider is judged against the real thing
                    // rather than a swatch that approximates it.
                    HStack {
                        Spacer()
                        GlowImageView(size: CGSize(width: 120, height: 40))
                            .padding(.vertical, 22)
                        Spacer()
                    }
                    .listRowBackground(Color.black)
                }

                Section {
                    Slider(
                        value: $peak,
                        in: GlowSettings.range,
                        step: 0.5
                    ) {
                        Text("Glow")
                    } minimumValueLabel: {
                        Image(systemName: "sun.min")
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.secondary)
                    }
                    .tint(GlowPalette.color)

                    LabeledContent("Brightness", value: label)
                } header: {
                    Text("Glow")
                } footer: {
                    Text(footer)
                }

                if peak <= GlowSettings.range.lowerBound {
                    Section {
                        Label("The glow is off. Today's slot still shows, just without any light.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { peak = GlowSettings.defaultValue }
                        .disabled(peak == GlowSettings.defaultValue)
                }
            }
        }
    }

    private var label: String {
        peak <= GlowSettings.range.lowerBound
            ? "Off"
            : String(format: "%.1f× brighter than white", peak)
    }

    private var footer: String {
        """
        Today's unfinished slot is drawn as an HDR image, so it can be brighter \
        than the white the screen normally allows. This sets how far above that \
        it aims for.

        How bright it actually gets is not up to the app: it depends on ambient \
        light, display brightness, thermal state, and whether Low Power Mode is \
        on. Expect it to be dramatic outdoors and subtle in a dim room. On a \
        screen without extended dynamic range, and in the widget, the slot \
        falls back to flat colour with a soft halo.
        """
    }
}
