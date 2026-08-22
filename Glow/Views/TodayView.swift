import SwiftData
import SwiftUI
import WidgetKit

/// Today: the several-times-a-day habits, and nothing else.
///
/// This screen is the small and medium widget at app size — rings, one per
/// habit, each a day's repetitions as arcs. There is no history here and no
/// week: a per-day habit's count resets with the day, so the only question the
/// screen answers is "what is left today", asked by the glow.
///
/// The weekly cadences live in This Week and never appear here, which is the
/// either/or the model is built on: a habit is counted across a week or within
/// a day, never both.
struct TodayView: View {
    @Query(filter: Habit.countedPerDay, sort: [SortDescriptor(\Habit.sortOrder)])
    private var habits: [Habit]

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    /// Owned here and handed *down*, rather than read from the environment.
    ///
    /// `@Environment(\.editMode)` read at this level is always inactive: the
    /// `EditButton` lives in the toolbar of the `NavigationStack` inside this
    /// body, so the value it toggles belongs to that container's environment,
    /// below where this struct reads. The button animated to Done while every
    /// tap still counted a repetition. Owning the state and injecting it puts
    /// the button and the rings on the same value.
    @State private var editMode: EditMode = .inactive

    @State private var today = WeekCalendar.day(Date())
    @State private var isAddingHabit = false
    @State private var editingHabit: Habit?

    private var store: HabitStore { HabitStore(context: context) }
    private var isEditing: Bool { editMode.isEditing }

    /// Three rings to a row, like the medium widget. Sized so a full row sits
    /// inside an iPhone's width with the margins the widget would have.
    private static let ringDiameter: CGFloat = 92
    private static let columns = 3
    private static let rowSpacing: CGFloat = 28
    private static let columnSpacing: CGFloat = 20

    var body: some View {
        NavigationStack {
            Group {
                if habits.isEmpty {
                    emptyState
                } else {
                    rings
                }
            }
            .navigationTitle(title)
            // The same title treatment and the same trailing pair as This
            // Week, so the two tabs wear one piece of chrome rather than two
            // that resemble each other.
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !habits.isEmpty {
                        EditButton()
                    }
                    // A plain button, not This Week's menu: a blank row holds a
                    // position in the week grid, and there is no grid here to
                    // hold a position in.
                    Button("New Habit", systemImage: "plus") {
                        isAddingHabit = true
                    }
                }
            }
            .environment(\.editMode, $editMode)
        }
        .sheet(isPresented: $isAddingHabit) {
            // Opened on the per-day kind, so adding from Today makes something
            // that appears on Today. The editor is the same one This Week
            // opens; only the kind it starts on differs.
            HabitEditorView(habit: nil, newHabitKind: .day)
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditorView(habit: habit)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = WeekCalendar.day(Date())
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = WeekCalendar.day(Date()) }
        }
    }

    /// The system's empty state, with the way out of it — the same shape This
    /// Week uses, so an empty Today is not a dead end.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Habits", systemImage: "circle.dotted")
        } description: {
            Text("A habit done several times a day shows up here as a ring.")
        } actions: {
            // Drawn rather than styled: the app's root tint is pure
            // white, and `.borderedProminent` fills with the tint and
            // draws the label in the contrasting colour — white on white.
            // Measured: the capsule's interior was 8077 pixels of a single
            // colour, 255,255,255, with no label in it at all. Same
            // treatment as `StoreUnavailableView`. See #162.
            Button { isAddingHabit = true } label: {
                Text("Add Habit")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(GlowPalette.color))
            }
            .buttonStyle(.plain)
        }
    }

    /// Rows of three, centred — the medium widget's layout, stacked. A plain
    /// stack rather than a grid so a final row of one or two rings centres the
    /// way the widget would centre them, instead of hugging the leading edge.
    private var rings: some View {
        ScrollView {
            VStack(spacing: Self.rowSpacing) {
                ForEach(rows, id: \.first?.id) { row in
                    HStack(alignment: .top, spacing: Self.columnSpacing) {
                        ForEach(row) { habit in cell(habit) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }

    private var rows: [[Habit]] {
        stride(from: 0, to: habits.count, by: Self.columns).map {
            Array(habits[$0..<min($0 + Self.columns, habits.count)])
        }
    }

    private func cell(_ habit: Habit) -> some View {
        let target = habit.timesPerDay
        let done = habit.snapshot().count(on: today)
        let isOpen = done < target

        // Editing changes what the ring is for rather than adding a second
        // control beside it: out of edit mode a tap counts, in edit mode it
        // opens the habit. Deleting already lives in that editor, so nothing
        // here has to invent a delete affordance of its own.
        return Button {
            if isEditing {
                editingHabit = habit
            } else {
                tap(habit, done: done, target: target)
            }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    DayRingView(target: target, done: done, diameter: Self.ringDiameter)
                    HabitIconView(icon: habit.icon, size: Self.ringDiameter * 0.3)
                }
                // The same rule as everywhere: a due name glows, a handled one
                // rests. The weight never changes, so completing does not
                // reflow.
                let name = Text(habit.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if isOpen {
                    name.glowing(halo: GlowPalette.labelHalo)
                } else {
                    name.foregroundStyle(GlowPalette.grey)
                }
            }
            .frame(width: Self.ringDiameter + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(habit.name)
        .accessibilityValue("\(done) of \(target) done today")
        .accessibilityHint(
            isEditing ? "Edit this habit" : (isOpen ? "Adds one" : "Starts the day over")
        )
    }

    /// A tap is one more; a tap on a full ring starts the day over. The rule
    /// is `DayRing.countAfterTap`, applied by the store — this only reports
    /// what happened to a thumb that cannot see under itself.
    private func tap(_ habit: Habit, done: Int, target: Int) {
        do {
            let count = try store.recordTap(for: habit, on: today)
            // A reset is a correction, and should not feel like progress.
            if count == 0 && done > 0 { Haptics.uncompleted() } else { Haptics.completed() }
            // No pop here, deliberately. The Island does not render an
            // activity while its own app is in front, so a goal met on this
            // screen would request one, show nobody anything, and end it two
            // seconds later. The ring closing *is* this screen's
            // acknowledgement. See `GoalPopCentre` and #103.
        } catch {
            HabitStore.report(error, operation: "recordTap")
        }
    }

    private var title: String {
        today.formatted(
            .dateTime.weekday(.wide).day().month(.wide)
                .locale(WeekCalendar.calendar.locale ?? .current)
        )
    }
}
