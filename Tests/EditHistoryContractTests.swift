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

    @Test("The existing More menu presents Edit History at the displayed week")
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
        let history = try #require(menu.range(of: "Button(\"Edit History\""))
        let edit = try #require(menu.range(of: "Button(\"Edit\""))

        #expect(newHabit.lowerBound < blank.lowerBound)
        #expect(blank.lowerBound < history.lowerBound)
        #expect(history.lowerBound < edit.lowerBound)
        #expect(weekly.contains(".fullScreenCover(isPresented: $isEditingHistory)"))
        #expect(weekly.contains("EditHistoryView(initialWeek: weekStart, today: today)"))
    }

    @Test("The matrix is factual, immediate, future-capable, and checkmark-only")
    func screenContract() throws {
        let history = try source("Glow/Views/EditHistoryView.swift")

        #expect(history.contains(".navigationTitle(\"Edit History\")"))
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
