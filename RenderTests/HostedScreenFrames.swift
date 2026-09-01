import CoreGraphics
import SwiftData
import SwiftUI
import UIKit

@testable import Glow

/// Full production screens for the render baseline (#386).
///
/// `ImageRenderer` cannot flatten either screen's `NavigationStack`; it
/// returns the same yellow invalid-configuration picture for both. Hosting the
/// real views in a window takes the compositor path the app takes. The window,
/// safe area, traits and output context are pinned here so the signature is a
/// picture of the view rather than of whichever simulator model ran the test.
@MainActor
enum HostedScreenFrames {
    static let names = ["weekly grid screen", "widgets screen"]

    private static let size = CGSize(width: 393, height: 852)
    private static let scale: CGFloat = 2

    /// See #357: SwiftData leaves an observer behind for a hosted `@Query`.
    /// Keeping every container alive for the test process removes the one
    /// measured crash precondition without keeping a window on screen.
    private static var keptContainers: [ModelContainer] = []

    static func render(named name: String) throws -> CGImage? {
        guard names.contains(name) else { return nil }
        let fixture = try Fixture()
        let root: AnyView
        switch name {
        case "weekly grid screen":
            root = AnyView(
                Glow.WeeklyGridView(today: fixture.today)
                    .modelContainer(fixture.container)
            )
        case "widgets screen":
            root = AnyView(
                Glow.WidgetsView(today: fixture.today)
                    .modelContainer(fixture.container)
            )
        default:
            return nil
        }

        let host = UIHostingController(
            rootView: root
                .environment(\.colorScheme, .dark)
        )
        host.safeAreaRegions = []
        host.overrideUserInterfaceStyle = UIUserInterfaceStyle.dark
        if #available(iOS 17.0, *) {
            host.traitOverrides.displayScale = scale
        }

        let frame = CGRect(origin: .zero, size: size)
        let window = UIWindow(frame: frame)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window.windowScene = scene
        }
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.isHidden = false
        window.makeKeyAndVisible()
        host.view.frame = frame
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // `@Query`, the navigation container and both screens' `.task`s settle
        // on the main run loop. The existing accessibility harness measured
        // this same boundary at 1.5 seconds.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        var drew = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            drew = host.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }

        window.rootViewController = nil
        window.isHidden = true
        window.windowScene = nil
        keptContainers.append(fixture.container)

        guard drew else { return nil }
        return image.cgImage
    }

    /// The exact nine-row fixture the existing app-row and widget baselines
    /// draw, converted into the production module's real SwiftData models.
    @MainActor
    private struct Fixture {
        let container: ModelContainer
        let today: Date

        init() throws {
            let entry = RenderBaselineTests.Fixture.week()
            today = entry.date
            container = try ModelContainer(
                for: Glow.GlowStore.schema,
                configurations: ModelConfiguration(
                    schema: Glow.GlowStore.schema, isStoredInMemoryOnly: true
                )
            )
            let context = container.mainContext
            for (index, snapshot) in (entry.habits.value ?? []).enumerated() {
                let frequency: Glow.Frequency
                switch snapshot.frequency {
                case .daily:
                    frequency = .daily
                case .timesPerWeek(let count):
                    frequency = .timesPerWeek(count)
                }
                let habit = Glow.Habit(
                    id: snapshot.id,
                    name: snapshot.name,
                    icon: snapshot.icon,
                    frequency: frequency,
                    createdAt: entry.week.days[0],
                    sortOrder: index,
                    isSpacer: snapshot.isSpacer
                )
                context.insert(habit)
                for day in snapshot.completedDays {
                    context.insert(Glow.Completion(day: day, habit: habit))
                }
            }
            try context.save()
        }
    }
}
