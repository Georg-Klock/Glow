import AppIntents
import SwiftUI

/// WidgetKit promotes the toggle style's accessibility in an archived widget;
/// a hosted app view does not. The Widgets tab sets this environment value so
/// the same control can add an outer accessibility fallback without changing
/// the installed widget's optimistic, `configuration.isOn`-driven voice.
private struct InAppWidgetPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isInAppWidgetPreview: Bool {
        get { self[InAppWidgetPreviewKey.self] }
        set { self[InAppWidgetPreviewKey.self] = newValue }
    }
}

/// The app-side adapter for the same absolute-state operation an installed
/// widget reaches through `MarkHabitIntent`. It is synchronous deliberately:
/// `SlotToggle` yields one frame after changing its local binding, then runs
/// the bounded write on the main actor in delivery order.
struct InAppWidgetMarkAction {
    let perform: @MainActor (UUID, Date, Date, Bool) throws -> Void
}

private struct InAppWidgetMarkActionKey: EnvironmentKey {
    static let defaultValue: InAppWidgetMarkAction? = nil
}

extension EnvironmentValues {
    var inAppWidgetMarkAction: InAppWidgetMarkAction? {
        get { self[InAppWidgetMarkActionKey.self] }
        set { self[InAppWidgetMarkActionKey.self] = newValue }
    }
}

/// A widget mark that draws the state it just asked for (#292).
///
/// This is the other half of `MarkHabitIntent` carrying `done`. The intent made
/// a tap idempotent, but the pixels still waited on WidgetKit: the tap wrote
/// the store in tens of milliseconds and the mark held its old shape until the
/// provider ran and the new timeline was composited — measured at 431ms and
/// 3.17s on an iPhone 14 Pro (#121). A person who taps and sees nothing taps
/// again, which is the flurry #272 traced.
///
/// The one mechanism WidgetKit offers for pixels that do not wait is an
/// AppIntent-backed `Toggle`: the system updates its appearance *optimistically*
/// while `perform()` is still running, provided the style renders
/// `configuration.isOn` rather than anything captured from the entry. So the
/// mark is a `Toggle`, its two faces are the two marks this control can be, and
/// the system flips between them at the tap. The guaranteed reload then
/// reconciles to the store's answer — which, on a refusal (a stale surface
/// offering a rest day, a deleted habit), is how an optimistic flip is taken
/// back.
///
/// **`isOn` is the rendered state, so the intent asks for its complement** —
/// exactly the contract `MarkHabitIntent.done` was built around: a ring means
/// "make this done", a dot means "make it not done", and a duplicate delivery
/// asks for the same thing twice.
///
/// The two faces arrive as views rather than as `SlotMark`s because the three
/// call sites disagree about what a face is: a week slot's completed face
/// carries the burst cross-fade, a span's faces carry its width and its rest
/// window, and the month's are plain marks. What this type owns is the part
/// they must not each reinvent: the toggle, the style that makes it optimistic,
/// and a spoken label and hint that follow `configuration.isOn` — so VoiceOver
/// agrees with the optimistic pixels, not with the snapshot they outran.
struct SlotToggle<OnMark: View, OffMark: View>: View {
    @Environment(\.isInAppWidgetPreview) private var isInAppWidgetPreview
    @Environment(\.inAppWidgetMarkAction) private var inAppWidgetMarkAction

    /// WidgetKit owns an AppIntent toggle's requested state. An ordinary app
    /// host does not, so its binding stores the same bit locally before any
    /// persistence work begins. It is cleared after the shared operation has
    /// posted reconciliation, returning authority to the entry snapshot.
    @State private var optimisticIsDone: Bool?
    @State private var pendingRequest: Bool?
    @State private var isDelivering = false

    private let habitID: UUID
    private let isDone: Bool
    private let day: Date
    private let renderedDay: Date
    private let onLabel: String
    private let offLabel: String
    private let onMark: OnMark
    private let offMark: OffMark

    init(
        habitID: UUID,
        isDone: Bool,
        day: Date,
        renderedDay: Date,
        onLabel: String,
        offLabel: String,
        @ViewBuilder onMark: () -> OnMark,
        @ViewBuilder offMark: () -> OffMark
    ) {
        self.habitID = habitID
        self.isDone = isDone
        self.day = day
        self.renderedDay = renderedDay
        self.onLabel = onLabel
        self.offLabel = offLabel
        self.onMark = onMark()
        self.offMark = offMark()
    }

    @ViewBuilder
    var body: some View {
        if isInAppWidgetPreview, let inAppWidgetMarkAction {
            inAppControl(action: inAppWidgetMarkAction)
                // The hosted app accessibility tree does not promote the
                // labels inside a custom AppIntent toggle style. Use the same
                // strings at the control boundary there, driven by the same
                // optimistic bit as the pixels.
                .accessibilityLabel(displayedIsDone ? onLabel : offLabel)
                .accessibilityHint(SlotVoice.hint(isDone: displayedIsDone))
                // Repeated deliberately across preview sizes. The process-level
                // touch gate chooses the first visible copy, then proves a
                // screen-coordinate tap reaches this shipping control (#494).
                .accessibilityIdentifier(
                    "widget-preview-mark-\(habitID.uuidString)-"
                        + DayID(day, calendar: WeekCalendar.calendar).text
                )
        } else {
            installedWidgetControl
        }
    }

    /// WidgetKit's archived adapter. Its `configuration.isOn` is the system's
    /// optimistic state and remains independent of the app-hosted path.
    private var installedWidgetControl: some View {
        Toggle(isOn: isDone, intent: MarkHabitIntent(
            habitID: habitID,
            done: !isDone,
            day: day,
            renderedDay: renderedDay,
            presentsIsland: true
        )) {
            // Never drawn: the style below draws the mark and ignores its
            // label, and what VoiceOver reads is the style's own
            // `accessibilityLabel`, which is the one that can follow `isOn`.
            EmptyView()
        }
        .toggleStyle(SlotMarkToggleStyle(
            onMark: onMark, offMark: offMark, onLabel: onLabel, offLabel: offLabel,
            handlesPresses: false
        ))
    }

    /// An ordinary binding is the app adapter WidgetKit does not provide.
    /// Both adapters still hand `SlotMarkToggleStyle` one `isOn` bit, so the
    /// optimistic pixels and VoiceOver state have one definition.
    private func inAppControl(action: InAppWidgetMarkAction) -> some View {
        Toggle(isOn: Binding(
            get: { displayedIsDone },
            set: { requested in request(requested, through: action) }
        )) {
            EmptyView()
        }
        .toggleStyle(SlotMarkToggleStyle(
            onMark: onMark, offMark: offMark, onLabel: onLabel, offLabel: offLabel,
            handlesPresses: true
        ))
    }

    private var displayedIsDone: Bool { optimisticIsDone ?? isDone }

    /// Coalesces input that arrives before the previous frame's bounded write
    /// begins, then serialises any request that arrives while reconciliation
    /// is being drawn. Absolute-state writes make duplicates harmless; this
    /// delivery loop additionally guarantees the last requested state is the
    /// last one handed to the store.
    private func request(_ requested: Bool, through action: InAppWidgetMarkAction) {
        optimisticIsDone = requested
        pendingRequest = requested
        guard !isDelivering else { return }
        isDelivering = true

        Task { @MainActor in
            // Give SwiftUI the optimistic frame before opening SwiftData.
            await Task.yield()
            while let next = pendingRequest {
                pendingRequest = nil
                try? action.perform(habitID, day, renderedDay, next)
                // Let the notification-driven entry redraw land, and accept a
                // newer tap before deciding that this control is settled.
                await Task.yield()
            }
            optimisticIsDone = nil
            isDelivering = false
        }
    }
}

/// Renders `configuration.isOn` and nothing captured beside it.
///
/// That property is load-bearing, not stylistic: WidgetKit's optimistic update
/// works by flipping `isOn` under the style before the intent has run, so a
/// style that keys off the entry's own state — the way the old `Button` label
/// did — draws the stale mark either way and the optimism buys nothing. Both
/// faces must therefore be resolvable from the archived view, which they are:
/// they are built from the entry and chosen by `isOn`.
private struct SlotMarkToggleStyle<OnMark: View, OffMark: View>: ToggleStyle {
    let onMark: OnMark
    let offMark: OffMark
    let onLabel: String
    let offLabel: String
    /// WidgetKit owns delivery for an archived AppIntent toggle. An ordinary
    /// SwiftUI host does not: a custom ToggleStyle must change the supplied
    /// binding when its rendered face is pressed (#494).
    let handlesPresses: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if handlesPresses {
            Button { configuration.isOn.toggle() } label: {
                mark(configuration: configuration)
            }
            .buttonStyle(.plain)
        } else {
            mark(configuration: configuration)
        }
    }

    private func mark(configuration: Configuration) -> some View {
        Group {
            if configuration.isOn {
                onMark
            } else {
                offMark
            }
        }
        // Spoken from `isOn`, same as drawn from it, so the announcement and
        // the pixels cannot disagree during the optimistic window. The system
        // adds the toggle's own on/off value from the same bit. Reduce Motion
        // changes none of this: the flip is a state change, not motion, so the
        // acknowledgement survives it — the burst is what Reduce Motion skips,
        // and that is the provider's business (`WidgetBurst`).
        .accessibilityLabel(configuration.isOn ? onLabel : offLabel)
        .accessibilityHint(SlotVoice.hint(isDone: configuration.isOn))
    }
}
