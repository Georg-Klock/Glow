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

            let edit = app.buttons["Edit"]
            XCTAssertTrue(edit.waitForExistence(timeout: 3), "Edit was absent at \(habitCount) rows")
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
            let frames = rows.map(\.frame)
            let ordinaryFrames = frames.enumerated().compactMap { index, frame in
                habitCount > 10 && index == 9 ? nil : frame
            }
            let shortest = try XCTUnwrap(ordinaryFrames.map(\.height).min())
            let tallest = try XCTUnwrap(ordinaryFrames.map(\.height).max())
            XCTAssertEqual(
                tallest,
                shortest,
                accuracy: 0.75,
                "ordinary edit-cell heights at \(habitCount) rows were \(frames)"
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
                XCTAssertGreaterThan(
                    frames[9].height,
                    tallest + 10,
                    "the deliberate widget boundary was not distinct: \(frames)"
                )
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
