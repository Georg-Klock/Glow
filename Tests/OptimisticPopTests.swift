import Foundation
import Testing
@testable import Glow

@Suite("Optimistic widget pop")
struct OptimisticPopTests {
    private let calendar = TestCalendar.monday
    private var week: Week {
        WeekCalendar.week(containing: TestCalendar.date(2026, 8, 19), calendar: calendar)
    }
    private var today: Date { week.days[2] }

    private func habit(target: Int, completed columns: [Int]) -> HabitSnapshot {
        HabitSnapshot(
            id: UUID(),
            name: "Water",
            icon: "drop",
            frequency: .timesPerWeek(target),
            completedDays: Set(columns.map { week.days[$0] })
        )
    }

    private func presents(
        _ habit: HabitSnapshot,
        done: Bool = true,
        level: PopPreferences.Level
    ) -> Bool {
        OptimisticPop.shouldPresent(
            requestedDone: done,
            habit: habit,
            in: week,
            today: today,
            level: level,
            calendar: calendar
        )
    }

    @Test("Off is silent even when the requested completion would meet the goal")
    func offIsSilent() {
        #expect(!presents(habit(target: 3, completed: [0, 1]), level: .off))
        #expect(!presents(habit(target: 5, completed: [0, 1]), level: .off))
    }

    @Test("Everything acknowledges every genuinely new requested completion")
    func everythingAcknowledgesARequest() {
        #expect(presents(habit(target: 5, completed: [0]), level: .everything))
        #expect(presents(habit(target: 3, completed: [0, 1]), level: .everything))
        // The unset value resolves to Everything for a fresh install.
        #expect(presents(habit(target: 5, completed: [0]), level: .unset))
    }

    @Test("Goals speaks exactly when adding today would reach the target")
    func goalsUsesTheProspectiveTotal() {
        #expect(!presents(habit(target: 4, completed: [0, 1]), level: .goals))
        #expect(presents(habit(target: 3, completed: [0, 1]), level: .goals))
        #expect(!presents(habit(target: 2, completed: [0, 1]), level: .goals))
    }

    @Test("Undo and a stale already-done request never manufacture a pop")
    func correctionsAndDuplicatesStaySilent() {
        let open = habit(target: 3, completed: [0, 1])
        #expect(!presents(open, done: false, level: .everything))

        let alreadyDone = habit(target: 3, completed: [0, 1, 2])
        for level in PopPreferences.Level.allCases {
            #expect(!presents(alreadyDone, level: level))
        }
    }

    @Test("A spacer cannot be celebrated")
    func spacerIsSilent() {
        let spacer = HabitSnapshot(
            id: UUID(), name: "", icon: "", frequency: .daily,
            completedDays: [], isSpacer: true
        )
        #expect(!presents(spacer, level: .everything))
    }

    @Test("The intent launches the eligible pop before it asks the store to write")
    func intentOrderIsOptimistic() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Glow/Store/MarkHabitIntent.swift"),
            encoding: .utf8
        )
        let pop = try #require(source.range(of: "GoalPopCentre.popIfRequestedCompletion("))
        let write = try #require(source.range(of: ".setCompletion(for: habit"))

        #expect(pop.lowerBound < write.lowerBound)
        #expect(source.components(separatedBy: "GoalPopCentre.popIfRequestedCompletion(").count == 2)
    }

    @Test("Only a control outside the foreground app asks for the Island")
    func hostedPreviewDoesNotSpendAnInvisibleActivity() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let slotToggle = try String(
            contentsOf: root.appendingPathComponent("GlowWidget/SlotToggle.swift"),
            encoding: .utf8
        )
        let widgetsView = try String(
            contentsOf: root.appendingPathComponent("Glow/Views/WidgetsView.swift"),
            encoding: .utf8
        )

        #expect(slotToggle.contains("presentsIsland: true"))
        #expect(widgetsView.contains("presentsIsland: false"))
    }
}

@Suite("Latest pop delivery")
@MainActor
struct LatestPopDeliveryTests {
    /// A deterministic stand-in for ActivityKit: every invocation announces
    /// that it started, then remains suspended until the test releases that
    /// exact invocation. No timing or task-creation order is assumed.
    @MainActor
    private final class Harness {
        private struct Pending {
            let label: String
            let continuation: CheckedContinuation<Void, Never>
        }

        private struct StartWaiter {
            let count: Int
            let continuation: CheckedContinuation<Void, Never>
        }

        private(set) var started: [String] = []
        private(set) var finished: [String] = []
        private var pending: [Pending] = []
        private var startWaiters: [StartWaiter] = []

        func perform(_ label: String) async {
            await withCheckedContinuation { continuation in
                pending.append(Pending(label: label, continuation: continuation))
                started.append(label)
                resumeSatisfiedStartWaiters()
            }
            finished.append(label)
        }

        func waitForStarts(_ count: Int) async {
            guard started.count < count else { return }
            await withCheckedContinuation { continuation in
                startWaiters.append(StartWaiter(count: count, continuation: continuation))
            }
        }

        func releaseFirst(_ label: String) {
            let index = pending.firstIndex { $0.label == label }
            #expect(index != nil, "no pending \(label) delivery")
            guard let index else { return }
            pending.remove(at: index).continuation.resume()
        }

        private func resumeSatisfiedStartWaiters() {
            var waiting: [StartWaiter] = []
            for waiter in startWaiters {
                if started.count >= waiter.count {
                    waiter.continuation.resume()
                } else {
                    waiting.append(waiter)
                }
            }
            startWaiters = waiting
        }
    }

    @Test("A slow old update cannot finish after and overwrite the newest one")
    func staleCompletionReappliesLatest() async {
        let delivery = LatestPopDelivery()
        let harness = Harness()

        let read = delivery.submit { await harness.perform("Read") }
        await harness.waitForStarts(1)

        // Water starts while Read is still suspended: it was not queued behind
        // the work it replaces.
        let water = delivery.submit { await harness.perform("Water") }
        await harness.waitForStarts(2)
        #expect(harness.started == ["Read", "Water"])

        // Let the newer update finish first, then the older one. The old task
        // sees that it became stale and must deliver Water again before exit.
        harness.releaseFirst("Water")
        await water.value
        harness.releaseFirst("Read")
        await harness.waitForStarts(3)
        #expect(harness.started == ["Read", "Water", "Water"])
        harness.releaseFirst("Water")
        await read.value

        #expect(harness.finished == ["Water", "Read", "Water"])
        #expect(harness.finished.last == "Water")
    }
}
