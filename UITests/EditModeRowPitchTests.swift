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

            // Native edit mode prefixes the row's own "Edit …" label with
            // "Remove, ". Ask for the whole set in one accessibility snapshot
            // rather than waiting on every row separately; the frame of this
            // combined button is the List cell SwiftUI centres its system
            // controls in, which is the geometry #546 exposed.
            let rowQuery = app.buttons.matching(NSPredicate(
                format: "label CONTAINS %@", "Edit Pitch Fixture"
            ))
            guard rowQuery.firstMatch.waitForExistence(timeout: 3) else {
                throw MissingRows(actual: 0, expected: habitCount)
            }
            let rows = rowQuery.allElementsBoundByIndex.sorted {
                $0.frame.minY < $1.frame.minY
            }
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
