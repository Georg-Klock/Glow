import WidgetKit

/// One still of the Today widget: the day, and the rings on it.
///
/// Its own file for the same reason `WeekEntry` is in one — the render tests
/// compile the widget's *views* without its configurations, and a view cannot
/// be compiled without the entry it draws. See project.yml.
struct TodayEntry: TimelineEntry {
    let date: Date
    /// Up to one habit for small, up to three for medium.
    let habits: [DayRingSnapshot]
}
