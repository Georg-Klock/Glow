import CoreGraphics
import SwiftData
import SwiftUI
import UIKit

@testable import Glow

/// Full production screens for the render baseline (#386), at every size the
/// universal app is laid out for (#632, #643).
///
/// `ImageRenderer` cannot flatten either screen's `NavigationStack`; it
/// returns the same yellow invalid-configuration picture for both. Hosting the
/// real views in a window takes the compositor path the app takes. The window,
/// safe area, traits and output context are pinned here so the signature is a
/// picture of the view rather than of whichever simulator model ran the test.
///
/// ## A table of surfaces, not one
///
/// Each `Surface` is a logical size, that size's native safe area, and the two
/// size classes the system gives it, forced through `traitOverrides`. The
/// forcing is the point: a window is otherwise handed its scene's size
/// classes, so an 820pt window hosted on an iPhone would still report compact
/// width, and a 393pt window hosted on an iPad would report regular. Each frame
/// is one screen on one surface; the first two, on the 393 × 852 phone, are the
/// frames this harness rendered before the table existed.
///
/// ## What a hosted window does not reproduce
///
/// **The idiom.** A hosted window reproduces the *size* and the forced size
/// classes, not the device: `UIUserInterfaceIdiom` is whatever the simulator
/// running the test is — an iPhone, on both lanes that run this suite — so the
/// iPad frames are an iPhone drawing into an iPad-sized, regular-width window.
/// Anything that branches on idiom, and the chrome an iPad draws around an app
/// (the iPad tab bar, window controls, Stage Manager), is not covered here.
/// `GlowUITests` on a real iPad destination is the half that covers those:
/// `GLOW_DEVICE_KIND=ipad Tools/test.sh`, nightly.
@MainActor
enum HostedScreenFrames {
    /// One logical screen the app is laid out for.
    struct Surface: Equatable {
        let size: CGSize
        /// That surface's native insets. A window attached to the live test
        /// scene otherwise inherits the simulator model's insets even though
        /// its own frame is pinned (#481).
        let safeArea: UIEdgeInsets
        let horizontalSizeClass: UIUserInterfaceSizeClass
        let verticalSizeClass: UIUserInterfaceSizeClass

        /// The 6.1" phone every hosted frame was measured on before #643: an
        /// iPhone 17e's 393 × 852, 59pt/34pt.
        static let phone = Surface(
            size: CGSize(width: 393, height: 852),
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            horizontalSizeClass: .compact, verticalSizeClass: .regular
        )
        /// The narrowest supported phone, the iPhone SE: 375pt, just under the
        /// 378pt scale break, with a status bar and no home indicator.
        static let phoneSE = Surface(
            size: CGSize(width: 375, height: 667),
            safeArea: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0),
            horizontalSizeClass: .compact, verticalSizeClass: .regular
        )
        /// The widest phone, a Pro Max: 440pt, where the compact ceiling on the
        /// panel shows as margin.
        static let phoneProMax = Surface(
            size: CGSize(width: 440, height: 956),
            safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
            horizontalSizeClass: .compact, verticalSizeClass: .regular
        )
        /// The app in a third of an iPad in Split View: compact width at an
        /// iPad's height, the narrowest window the app can be given.
        static let iPadSplit = Surface(
            size: CGSize(width: 320, height: 1024),
            safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
            horizontalSizeClass: .compact, verticalSizeClass: .regular
        )
        /// App Review's iPad Air 11-inch, full screen in portrait (#632).
        static let iPad = Surface(
            size: CGSize(width: 820, height: 1180),
            safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
            horizontalSizeClass: .regular, verticalSizeClass: .regular
        )
        /// The same iPad in landscape, where the regular ceiling on the panel
        /// shows as margin.
        static let iPadLandscape = Surface(
            size: CGSize(width: 1180, height: 820),
            safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
            horizontalSizeClass: .regular, verticalSizeClass: .regular
        )
    }

    enum Screen {
        case weeklyGrid
        case widgets
    }

    struct Frame {
        let name: String
        let screen: Screen
        let surface: Surface
    }

    /// Every hosted frame the baseline gates. The first two predate the table
    /// and must stay what they were.
    static let frames: [Frame] = [
        Frame(name: "weekly grid screen", screen: .weeklyGrid, surface: .phone),
        Frame(name: "widgets screen", screen: .widgets, surface: .phone),
        Frame(name: "weekly grid screen iphone se", screen: .weeklyGrid, surface: .phoneSE),
        Frame(name: "weekly grid screen iphone pro max", screen: .weeklyGrid, surface: .phoneProMax),
        Frame(name: "weekly grid screen ipad split", screen: .weeklyGrid, surface: .iPadSplit),
        Frame(name: "weekly grid screen ipad", screen: .weeklyGrid, surface: .iPad),
        Frame(name: "weekly grid screen ipad landscape", screen: .weeklyGrid, surface: .iPadLandscape),
        Frame(name: "widgets screen iphone se", screen: .widgets, surface: .phoneSE),
        Frame(name: "widgets screen ipad split", screen: .widgets, surface: .iPadSplit),
        Frame(name: "widgets screen ipad", screen: .widgets, surface: .iPad),
    ]

    static var names: [String] { frames.map(\.name) }

    private static let scale: CGFloat = 2

    /// The correction that brings a window's inherited insets to `surface`'s.
    static func additionalSafeAreaInsets(
        for inherited: UIEdgeInsets, surface: Surface = .phone
    ) -> UIEdgeInsets {
        UIEdgeInsets(
            top: surface.safeArea.top - inherited.top,
            left: surface.safeArea.left - inherited.left,
            bottom: surface.safeArea.bottom - inherited.bottom,
            right: surface.safeArea.right - inherited.right
        )
    }

    private struct SafeAreaMismatch: Error, CustomStringConvertible {
        let actual: UIEdgeInsets
        let expected: UIEdgeInsets

        var description: String {
            "hosted screen safe area is \(actual); expected \(expected)"
        }
    }

    /// See #357: SwiftData leaves an observer behind for a hosted `@Query`.
    /// Keeping every container alive for the test process removes the one
    /// measured crash precondition without keeping a window on screen.
    private static var keptContainers: [ModelContainer] = []

    static func render(named name: String) throws -> CGImage? {
        guard let frame = frames.first(where: { $0.name == name }) else { return nil }
        let host = try Host(screen: frame.screen, surface: frame.surface)
        defer { host.close() }
        return host.capture()
    }

    /// One production screen in one window, kept open so a test can change the
    /// surface under it (#643) as well as capture it once.
    @MainActor
    final class Host {
        /// Held as a plain view controller so the hosted root keeps the exact
        /// view type it had before the surface table, with no extra `AnyView`.
        private let controller: UIViewController
        private let window: UIWindow
        private let container: ModelContainer
        private(set) var surface: Surface

        /// Whether this process has hosted a screen yet. See `warmUp()`.
        private static var warmed = false

        /// One throwaway render of each screen before the first one anyone
        /// captures.
        ///
        /// **The first hosted screen in a process does not draw what every
        /// later one draws** (#643), and that was measured rather than assumed.
        /// On iOS 26.5 the reference `weekly grid screen`, rendered first in
        /// its process, differs from the same frame rendered after any other
        /// hosted screen in 31 cells, by one level each; every render after
        /// the first agreed with every other. Before `HostedResizeTests` the
        /// gate's own frame was always first, so the committed signature was
        /// the first-render one and nobody could tell. With a second suite
        /// hosting screens, which one Swift Testing starts first would decide
        /// which picture the gate compares. Warming up makes every captured
        /// frame a later render, whatever ran before it.
        private static func warmUp() throws {
            guard !warmed else { return }
            warmed = true
            for screen in [Screen.weeklyGrid, .widgets] {
                let host = try Host(screen: screen, surface: .phone)
                _ = host.capture()
                host.close()
            }
        }

        init(screen: Screen, surface: Surface) throws {
            try Self.warmUp()
            let fixture = try Fixture()
            let root: AnyView
            switch screen {
            case .weeklyGrid:
                root = AnyView(
                    Glow.WeeklyGridView(today: fixture.today)
                        .modelContainer(fixture.container)
                )
            case .widgets:
                root = AnyView(
                    Glow.WidgetsView(today: fixture.today)
                        .modelContainer(fixture.container)
                )
            }
            container = fixture.container
            self.surface = surface

            let host = UIHostingController(
                rootView: root.environment(\.colorScheme, .dark)
            )
            host.safeAreaRegions = []
            host.overrideUserInterfaceStyle = UIUserInterfaceStyle.dark
            host.traitOverrides.displayScale = HostedScreenFrames.scale
            // Forced rather than inherited: the scene's size classes are the
            // simulator's, not the surface's.
            host.traitOverrides.horizontalSizeClass = surface.horizontalSizeClass
            host.traitOverrides.verticalSizeClass = surface.verticalSizeClass
            controller = host

            let frame = CGRect(origin: .zero, size: surface.size)
            window = UIWindow(frame: frame)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                window.windowScene = scene
            }
            window.overrideUserInterfaceStyle = .dark
            // This has to be installed before `rootViewController`: SwiftUI
            // reads the safe area as the NavigationStack enters the hierarchy.
            // Changing the same value after its first layout updates UIKit's
            // reported inset but leaves the model-specific navigation layout in
            // place.
            host.additionalSafeAreaInsets = HostedScreenFrames.additionalSafeAreaInsets(
                for: window.safeAreaInsets, surface: surface
            )
            window.rootViewController = host
            window.isHidden = false
            window.makeKeyAndVisible()
            host.view.frame = frame
            try settle()
        }

        /// Gives the open screen another surface, the way Stage Manager, Split
        /// View or a foldable resizes a window: the same view and its state, a
        /// new size and new size classes.
        func resize(to surface: Surface) throws {
            self.surface = surface
            let frame = CGRect(origin: .zero, size: surface.size)
            window.frame = frame
            controller.traitOverrides.horizontalSizeClass = surface.horizontalSizeClass
            controller.traitOverrides.verticalSizeClass = surface.verticalSizeClass
            controller.additionalSafeAreaInsets = HostedScreenFrames.additionalSafeAreaInsets(
                for: window.safeAreaInsets, surface: surface
            )
            controller.view.frame = frame
            try settle()
        }

        private func settle() throws {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            // `@Query`, the navigation container and both screens' `.task`s
            // settle on the main run loop. The existing accessibility harness
            // measured this same boundary at 1.5 seconds.
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            controller.view.layoutIfNeeded()
            guard controller.view.safeAreaInsets == surface.safeArea else {
                throw SafeAreaMismatch(
                    actual: controller.view.safeAreaInsets, expected: surface.safeArea
                )
            }
        }

        func capture() -> CGImage? {
            let frame = CGRect(origin: .zero, size: surface.size)
            let format = UIGraphicsImageRendererFormat()
            format.scale = HostedScreenFrames.scale
            format.opaque = true
            format.preferredRange = .standard
            var drew = false
            let image = UIGraphicsImageRenderer(size: surface.size, format: format).image { _ in
                drew = controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
            }
            guard drew else { return nil }
            return image.cgImage
        }

        func close() {
            window.rootViewController = nil
            window.isHidden = true
            window.windowScene = nil
            HostedScreenFrames.keptContainers.append(container)
        }
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
