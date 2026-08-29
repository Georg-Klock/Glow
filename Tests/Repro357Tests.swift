import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import Glow

/// TEMPORARY — investigation harness for #357. Not for merge.
@MainActor
@Suite(.serialized)
struct Repro357Tests {
    typealias Screen = EmptyStateAccessibilityTests.Screen

    /// Does the hosted screen actually go away when the test that built it ends?
    @Test func measureWhetherTheScreenOutlivesItsTest() throws {
        weak var weakHost: UIViewController?
        weak var weakWindow: UIWindow?
        weak var weakContainer: AnyObject?

        var mountedAfterTearDown = -1
        try {
            let screen = try Screen()
            weakHost = screen.host
            weakWindow = screen.window
            weakContainer = screen.container as AnyObject
            screen.tearDown()
            mountedAfterTearDown = screen.contentElements().count
        }()

        for step in 0..<10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            print(
                "REPRO357 liveness step \(step): host=\(weakHost != nil) "
                    + "window=\(weakWindow != nil) container=\(weakContainer != nil) "
                    + "mounted=\(mountedAfterTearDown)"
            )
        }
        let verdict: String =
            "liveness after teardown: host=\(weakHost != nil) window=\(weakWindow != nil) "
            + "container=\(weakContainer != nil) mounted=\(mountedAfterTearDown)"
        Issue.record(Comment(rawValue: verdict))
    }

    /// A defaults-change notification after the screen was torn down and released.
    /// `WeeklyGridView` subscribes to `UserDefaults.didChangeNotification`
    /// process-wide and answers it with `refreshDemoHistory()` →
    /// `DemoHistory.inventedCount()` → `ModelContext.fetchCount`, which is the
    /// stack in `Glow-2026-08-28-174334.ips`.
    @Test func aDefaultsNotificationAfterTearDown() throws {
        for round in 0..<15 {
            try {
                let screen = try Screen()
                screen.tearDown()
            }()
            print("REPRO357 defaults round \(round)")
            NotificationCenter.default.post(
                name: UserDefaults.didChangeNotification, object: UserDefaults.standard
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
    }

    /// The exact shape of the reported flake: a screen torn down and released,
    /// then a *new* screen performing the curated-set save.
    @Test func aSaveAfterAPriorScreenWasTornDown() throws {
        for round in 0..<12 {
            try {
                let previous = try Screen()
                previous.tearDown()
            }()
            let screen = try Screen()
            defer { screen.tearDown() }
            print("REPRO357 save round \(round)")
            let button = try #require(screen.element(labelled: "Start with a Pre-Selected Set"))
            #expect(button.accessibilityActivate())
            screen.settle()
            #expect(
                try screen.container.mainContext.fetch(FetchDescriptor<Habit>()).count
                    == DefaultHabits.all.count
            )
        }
    }

    /// What `tearDown()`'s own comment says took the host down: three live
    /// screens at once, then a save.
    @Test func threeLiveScreensAndASave() throws {
        for round in 0..<6 {
            var screens: [Screen] = []
            for _ in 0..<3 { screens.append(try Screen()) }
            defer { for screen in screens { screen.tearDown() } }
            print("REPRO357 three-live round \(round)")
            let button = try #require(screens[2].element(labelled: "Start with a Pre-Selected Set"))
            #expect(button.accessibilityActivate())
            screens[2].settle()
        }
    }
}
