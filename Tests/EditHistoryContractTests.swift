import Foundation
import Testing
@testable import Glow

/// Source-level parts of #543 and #557 that a pure date/store test cannot
/// observe: where correcting history is reached and how, which projection it
/// declines, and whether an ordinary cadence surface quietly widens its
/// editing scope again.
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

    private func weeklyGrid() throws -> String {
        try source("Glow/Views/WeeklyGridView.swift")
    }

    /// The two menu items are named for what they act on (#559). They both
    /// began "Edit", one above the other, for two unrelated jobs — managing
    /// the habit list, and fixing a day that was logged wrong or missed. The
    /// history item says *Correct* because that is the job the mode exists
    /// for; the list item says *Habits* to match "New Habit" and "Blank Row"
    /// beside it. The row's swipe action is a third "Edit" — one habit's own
    /// editor — and is deliberately untouched, so the scan below is on the
    /// menu's text alone.
    @Test("The existing More menu enters Correct History on the displayed week")
    func menuAndPresentation() throws {
        let weekly = try weeklyGrid()
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

        // **A mode flag, not a presentation** (#557). The item sets the flag
        // that drives what every row draws; it does not present a second
        // hierarchy. The week is not handed over because there is no one to
        // hand it to — it is this screen's own `weekStart`, untouched.
        #expect(menu.contains("isCorrectingHistory = true"))
        #expect(!weekly.contains(".fullScreenCover("))
        #expect(!weekly.contains(".sheet(isPresented: $isCorrectingHistory"))
        #expect(!weekly.contains("EditHistoryView("))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Glow/Views/EditHistoryView.swift").path
        ), "the separate screen is back")
    }

    /// The mode is the screen adapting in place (#557): the same `List`, whose
    /// rows swap their track for `EditHistoryTrack`, a pager that consults
    /// the mode's own reach, and an exit that is a drawn white capsule rather
    /// than a control left to resolve its own contrast against the root tint
    /// (#162; CLAUDE.md, "A root `.tint()` beats anything that derives a
    /// colour from it").
    @Test("Correcting is the same List in another mode, with a drawn Done")
    func modeContract() throws {
        let weekly = try weeklyGrid()

        #expect(weekly.contains("private var mode: WeekGridMode"))
        #expect(weekly.contains("mode.reach(recordStart:"))
        #expect(weekly.contains("isCorrectingHistory: isCorrectingHistory"))
        #expect(weekly.contains(".deleteDisabled(!mode.offersHabitManagement)"))
        #expect(weekly.contains(".moveDisabled(!mode.offersHabitManagement)"))

        let done = try #require(weekly.range(of: "private var doneCorrecting"))
        let doneBody = String(weekly[done.lowerBound...].prefix(1200))
        #expect(doneBody.contains("FilledCapsuleLabel(title: \"Done\""))
        #expect(doneBody.contains(".buttonStyle(.plain)"))
        #expect(!doneBody.contains(".borderedProminent"))

        let capsule = try #require(weekly.range(of: "struct FilledCapsuleLabel"))
        let capsuleBody = String(weekly[capsule.lowerBound...].prefix(700))
        #expect(capsuleBody.contains(".foregroundStyle(.black)"))
        #expect(capsuleBody.contains("Capsule().fill(GlowPalette.color)"))

        let row = try source("Glow/Views/HabitRowView.swift")
        #expect(row.contains("} else if isCorrectingHistory {"))
        #expect(row.contains("EditHistoryTrack("))
    }

    /// The circles are factual and immediate (#543): a completion exists on
    /// this civil day or it does not, written at the tap with no draft, and
    /// never derived from the cadence projection.
    @Test("The track is factual, immediate and future-capable")
    func trackContract() throws {
        let track = try source("Glow/Views/EditHistoryTrack.swift")
        #expect(track.contains("snapshot.count(on: day) > 0"))
        #expect(!track.contains("WeekGrid."))
        #expect(!track.contains("WeekSpans."))
        #expect(!track.contains("SlotMarkView"))
        #expect(!track.contains("SlotEditing"))

        // The one write that names a day other than today, and the one place
        // the future permission is spoken. Exactly one: a second call site
        // would be a second surface widening its scope.
        let weekly = try weeklyGrid()
        #expect(weekly.components(separatedBy: "allowingFuture: true").count == 2)
        let correct = try #require(weekly.range(of: "private func correct(_ habit: Habit, on day: Date)"))
        let correctBody = String(weekly[correct.lowerBound...].prefix(600))
        #expect(correctBody.contains("allowingFuture: true"))
        #expect(!correctBody.contains("showPop("))
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
                "\(target) widened correction scope outside the correcting mode"
            )
        }
    }
}
