import Foundation
import Testing
@testable import Glow

/// Source-level parts of #543 that a pure date/store test cannot observe:
/// where the screen is reached, which projection it declines, and whether an
/// ordinary cadence surface quietly widens its editing scope again.
@Suite("Edit History contract")
struct EditHistoryContractTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The two menu items are named for what they act on (#559). They both
    /// began "Edit", one above the other, for two unrelated jobs — managing
    /// the habit list, and fixing a day that was logged wrong or missed. The
    /// history item says *Correct* because that is the job the screen exists
    /// for; the list item says *Habits* to match "New Habit" and "Blank Row"
    /// beside it. The row's swipe action is a third "Edit" — one habit's own
    /// editor — and is deliberately untouched, so the scan below is on the
    /// menu's text alone.
    @Test("The existing More menu presents Correct History at the displayed week")
    func menuAndPresentation() throws {
        let weekly = try source("Glow/Views/WeeklyGridView.swift")
        let menuStart = try #require(weekly.range(of: "private var moreMenu"))
        let menuEnd = try #require(weekly.range(
            of: "/// What the week on screen is called",
            range: menuStart.upperBound..<weekly.endIndex
        ))
        let menu = String(weekly[menuStart.lowerBound..<menuEnd.lowerBound])
        let newHabit = try #require(menu.range(of: "Button(\"New Habit\""))
        let blank = try #require(menu.range(of: "Button(\"Blank Row\""))
        let history = try #require(menu.range(of: "Button(\"Correct History\""))
        let edit = try #require(menu.range(of: "Button(\"Edit Habits\""))

        #expect(newHabit.lowerBound < blank.lowerBound)
        #expect(blank.lowerBound < history.lowerBound)
        #expect(history.lowerBound < edit.lowerBound)
        #expect(weekly.contains(".fullScreenCover(isPresented: $isEditingHistory)"))
        #expect(weekly.contains("EditHistoryView(initialWeek: weekStart, today: today)"))
    }

    /// The screen's title matches the menu item that opens it (#559): a menu
    /// saying one thing and the screen it opens saying another is its own
    /// confusion. The Swift symbols keep their names — `EditHistoryView` is
    /// not copy — the way `GlowOffPreviewNotice` kept its name when the words
    /// it draws moved on.
    @Test("The matrix is factual, immediate, future-capable, and checkmark-only")
    func screenContract() throws {
        let history = try source("Glow/Views/EditHistoryView.swift")

        #expect(history.contains(".navigationTitle(\"Correct History\")"))
        #expect(history.contains(".navigationBarBackButtonHidden(true)"))
        #expect(history.contains(".interactiveDismissDisabled(true)"))
        #expect(history.contains("Label(\"Done\", systemImage: \"checkmark\")"))
        #expect(history.contains("allowingFuture: true"))
        #expect(history.contains("storedRows.filter { !$0.isSpacer }"))
        #expect(history.contains("Habit.snapshots(of: habits, within: week.dayIDs())"))
        #expect(!history.contains("WeekGrid."))
        #expect(!history.contains("WeekSpans."))
        #expect(!history.contains("SlotMarkView"))
    }

    @Test("Cadence surfaces edit only today")
    func allOtherSurfacesAreTodayOnly() throws {
        let targets = [
            "Glow/Views/WeeklyGridView.swift",
            "Glow/Logic/MonthGrid.swift",
            "Glow/Logic/WidgetSpanActions.swift",
            "GlowWidget/WeekWidgetView.swift",
        ]
        for target in targets {
            let text = try source(target)
            #expect(text.contains(".todayOnly"), "\(target) has no explicit editing policy")
            #expect(
                !text.contains(".week(allowingFuture:"),
                "\(target) widened correction scope outside Edit History"
            )
        }
    }
}
