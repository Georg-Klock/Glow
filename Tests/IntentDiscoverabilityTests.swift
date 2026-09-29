import Testing

@testable import Glow

/// The widget's tap is plumbing, not a Shortcuts action: it is addressed by a
/// habit's UUID and an archived day, which nobody can type.
///
/// Only `MarkHabitIntent` is asserted here. `SelectWeekLayoutIntent`, the
/// widget's configuration, is also absent from Shortcuts, but not through this
/// property: its `isDiscoverable` still reports the protocol default `true`,
/// and it is the metadata extractor that leaves configuration intents out of
/// the action list (read back from the built app's `extract.actionsdata`).
struct IntentDiscoverabilityTests {
    @Test func markHabitIsNotAShortcutsAction() {
        #expect(MarkHabitIntent.isDiscoverable == false)
    }
}
