import SwiftUI

/// What the app shows when the store could not be opened.
///
/// This screen exists because the alternative was `fatalError`, and a crash on
/// launch is indistinguishable from the app having eaten your history. It has
/// nothing to offer but a true sentence and a retry — the point is that the
/// person can read what happened, and that nothing has been deleted by the time
/// they do.
struct StoreUnavailableView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundStyle(GlowPalette.warning)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)

                Text("Your habits could not be opened")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("""
                Nothing has been deleted. The app stopped here rather than starting with an empty \
                list, because adding habits to an empty list is what would make this permanent.
                """)
                .foregroundStyle(.secondary)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.fill.tertiary)
                    }

                // Drawn rather than styled: the app's tint is pure white, and
                // `.borderedProminent` paints the label white on top of it.
                Button(action: retry) {
                    Text("Try again")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(GlowPalette.color))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)

                Text("If it keeps failing, restarting the phone is worth one attempt: a store can be held open by a process that has not finished shutting down.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .tint(GlowPalette.color)
    }
}
