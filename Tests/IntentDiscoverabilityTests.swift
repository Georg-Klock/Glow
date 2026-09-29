import Testing

@testable import Glow

/// The app's intents are the widget's plumbing, not Shortcuts actions: each is
/// addressed by identifiers a person cannot type. Both stay out of the
/// Shortcuts action list; the configuration intent already was, by default.
struct IntentDiscoverabilityTests {
    @Test func markHabitIsNotAShortcutsAction() {
        #expect(MarkHabitIntent.isDiscoverable == false)
    }

    @Test func widgetConfigurationIsNotAShortcutsAction() {
        #expect(SelectWeekLayoutIntent.isDiscoverable == false)
    }
}
