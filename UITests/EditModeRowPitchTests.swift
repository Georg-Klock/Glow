import XCTest

@MainActor
final class EditModeRowPitchTests: XCTestCase {
    func testOrdinaryRowPitchStaysUniformAtEightThroughElevenHabits() throws {
        for habitCount in 8...11 {
            let app = XCUIApplication()
            app.launchArguments.append("-glow-edit-pitch-ui-test=\(habitCount)")
            app.launch()
            defer { app.terminate() }

            let more = app.buttons["More"]
            XCTAssertTrue(more.waitForExistence(timeout: 3), "More was absent at \(habitCount) rows")
            more.tap()

            let edit = app.buttons["Edit Habits"]
            XCTAssertTrue(edit.waitForExistence(timeout: 3), "Edit Habits was absent at \(habitCount) rows")
            edit.tap()
            XCTAssertTrue(
                app.buttons["Done"].waitForExistence(timeout: 3),
                "edit mode did not open at \(habitCount) rows"
            )

            // The List cell is the geometry #546 exposed: it is what SwiftUI
            // centres its system controls in. Found through the app's own
            // "Edit …" label inside it rather than through the system's edit
            // chrome, whose wording differs by runtime and on iOS 18 repeats
            // the habit's name inside the reorder handle (#555); see
            // `EditModeRows.swift`.
            guard app.editRow(containing: "Pitch Fixture").waitForExistence(timeout: 3) else {
                throw MissingRows(actual: 0, expected: habitCount)
            }
            let rows = app.editRows(containing: "Pitch Fixture")
            guard rows.count == habitCount else {
                throw MissingRows(actual: rows.count, expected: habitCount)
            }
            // **Every habit's cell is the same height, index 9 included**
            // (#621). This test used to exclude that one and then assert it
            // was more than 10pt taller than the rest — it was encoding the
            // defect: the boundary's empty row was an extra bottom inset on
            // whichever habit reached `largeRowCapacity - 1`, so that habit's
            // cell was half a boundary taller and `List` centred its delete
            // control 15.9pt below its own label. The gap is its own row now,
            // so no habit's cell knows about it.
            let frames = rows.map(\.frame)
            let shortest = try XCTUnwrap(frames.map(\.height).min())
            let tallest = try XCTUnwrap(frames.map(\.height).max())
            XCTAssertEqual(
                tallest,
                shortest,
                accuracy: 0.75,
                "edit-cell heights at \(habitCount) rows were \(frames)"
            )

            let leadingCentres = frames.prefix(min(habitCount, 9)).map(\.midY)
            let leadingPitches = zip(leadingCentres, leadingCentres.dropFirst())
                .map { $1 - $0 }
            let smallestPitch = try XCTUnwrap(leadingPitches.min())
            let largestPitch = try XCTUnwrap(leadingPitches.max())
            XCTAssertEqual(
                largestPitch,
                smallestPitch,
                accuracy: 0.75,
                "ordinary edit-row pitches at \(habitCount) rows were \(leadingPitches)"
            )

            if habitCount > 10 {
                // The gap is still there and still one row's worth — it is
                // between the two habits now rather than inside one of them,
                // so it shows in the *pitch* across the boundary and in no
                // cell's height.
                let acrossTheBoundary = frames[10].midY - frames[9].midY
                XCTAssertGreaterThan(
                    acrossTheBoundary,
                    largestPitch + 10,
                    "the widget boundary left no gap between rows 9 and 10: \(frames)"
                )
                // And the habits either side of it are ordinary cells.
                XCTAssertEqual(frames[9].height, shortest, accuracy: 0.75)
                XCTAssertEqual(frames[10].height, shortest, accuracy: 0.75)
            }
        }
    }

    private struct MissingRows: Error, CustomStringConvertible {
        let actual: Int
        let expected: Int

        var description: String {
            "found \(actual) edit rows; expected \(expected)"
        }
    }
}
