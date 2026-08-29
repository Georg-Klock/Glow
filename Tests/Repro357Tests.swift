import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import Glow

/// TEMPORARY — investigation harness for #357. Not for merge.
///
/// Four arms, each selected on its own with `-only-testing`, so exactly one
/// variable moves between them. What every arm ends in is the same save:
/// `WeeklyGridView.startWithDefaults()` → `HabitStore.commit()`, which is the
/// frame under `postNotificationName` in every crash report.
@MainActor
@Suite(.serialized)
struct Repro357Tests {
    typealias Screen = EmptyStateAccessibilityTests.Screen

    static let rounds = Int(ProcessInfo.processInfo.environment["REPRO357_ROUNDS"] ?? "6") ?? 6

    private func save(on screen: Screen, round: Int) throws {
        print("REPRO357 round \(round)")
        let button = try #require(screen.element(labelled: "Start with a Pre-Selected Set"))
        #expect(button.accessibilityActivate())
        screen.settle()
    }

    /// Does the hosted screen, its window and its container actually go away?
    /// Printed for both teardowns, so the claim is measured rather than argued.
    @Test func liveness() throws {
        for mode in [Screen.TearDown.dropWindowOnly, .unmount] {
            weak var weakHost: UIViewController?
            weak var weakWindow: UIWindow?
            weak var weakContainer: AnyObject?
            var mounted = -1
            try {
                let screen = try Screen(keepContainer: false)
                weakHost = screen.host
                weakWindow = screen.window
                weakContainer = screen.container as AnyObject
                screen.tearDown(mode)
                mounted = screen.contentElements().count
            }()
            for _ in 0..<10 { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
            print(
                "REPRO357 liveness \(mode): host=\(weakHost != nil) window=\(weakWindow != nil) "
                    + "container=\(weakContainer != nil) mounted=\(mounted)"
            )
        }
    }

    /// ARM A — one screen at a time, unmounted at the end of its round, and its
    /// container *not* kept. The shape the fixed suite has.
    @Test func armAOneScreenUnmountedContainerReleased() throws {
        for round in 0..<Self.rounds {
            let screen = try Screen(keepContainer: false)
            defer { screen.tearDown(.unmount) }
            try save(on: screen, round: round)
        }
    }

    /// ARM B — a prior screen left *mounted* (main's teardown drops the window
    /// only) while the next screen saves. Two live `WeeklyGridView`s, two
    /// containers. Containers kept, so container lifetime cannot be the cause.
    @Test func armBPriorScreenStillMounted() throws {
        for round in 0..<Self.rounds {
            let previous = try Screen(keepContainer: true)
            previous.tearDown(.dropWindowOnly)
            let screen = try Screen(keepContainer: true)
            defer { screen.tearDown(.dropWindowOnly) }
            try save(on: screen, round: round)
        }
    }

    /// ARM C — a prior screen *unmounted*, its container kept alive, then the
    /// next screen saves. Arm B with the one variable — whether the prior
    /// screen is still subscribed — turned off.
    @Test func armCPriorScreenUnmountedContainerKept() throws {
        for round in 0..<Self.rounds {
            let previous = try Screen(keepContainer: true)
            previous.tearDown(.unmount)
            let screen = try Screen(keepContainer: true)
            defer { screen.tearDown(.unmount) }
            try save(on: screen, round: round)
        }
    }

    /// ARM D — arm C with the containers released instead of kept. Isolates the
    /// `kept` array: if C survives and D does not, holding the container is
    /// load-bearing; if both survive, it is not.
    @Test func armDPriorScreenUnmountedContainerReleased() throws {
        for round in 0..<Self.rounds {
            try {
                let previous = try Screen(keepContainer: false)
                previous.tearDown(.unmount)
            }()
            let screen = try Screen(keepContainer: false)
            defer { screen.tearDown(.unmount) }
            try save(on: screen, round: round)
        }
    }

    /// ARM F — `main`'s exact shape: a prior screen torn down the way `main`
    /// tears one down (window dropped, graph left mounted) and *nothing* held.
    /// The control: whatever rate this arm shows is the flake's own rate.
    @Test func armFMainShape() throws {
        for round in 0..<Self.rounds {
            try {
                let previous = try Screen(keepContainer: false)
                previous.tearDown(.dropWindowOnly)
            }()
            let screen = try Screen(keepContainer: false)
            defer { screen.tearDown(.dropWindowOnly) }
            try save(on: screen, round: round)
        }
    }

    /// ARM E — three live screens at once, then a save on the third. What
    /// `tearDown()`'s own comment on `main` says took the host down.
    @Test func armEThreeLiveScreens() throws {
        for round in 0..<Self.rounds {
            var screens: [Screen] = []
            for _ in 0..<3 { screens.append(try Screen(keepContainer: true)) }
            defer { for screen in screens { screen.tearDown(.dropWindowOnly) } }
            try save(on: screens[2], round: round)
        }
    }
}
