import Foundation
import Testing
import WidgetKit
@testable import Glow

@Suite("Widget display size")
struct WidgetDisplaySizeTests {
    @Test("Every family keeps WidgetKit's exact frame independently")
    func exactFramesRoundTrip() throws {
        let (store, suite) = try privateStore()
        defer { store.removePersistentDomain(forName: suite) }

        WidgetDisplaySize.record(CGSize(width: 162, height: 162), for: .systemSmall, store: store)
        WidgetDisplaySize.record(CGSize(width: 342, height: 162), for: .systemMedium, store: store)
        WidgetDisplaySize.record(CGSize(width: 342, height: 358), for: .systemLarge, store: store)

        let snapshot = WidgetDisplaySize.snapshot(store: store)
        #expect(snapshot.measuredSize(of: .systemSmall) == CGSize(width: 162, height: 162))
        #expect(snapshot.measuredSize(of: .systemMedium) == CGSize(width: 342, height: 162))
        #expect(snapshot.measuredSize(of: .systemLarge) == CGSize(width: 342, height: 358))
        #expect(snapshot.smallGutter == 18)
    }

    @Test("An unobserved family falls back to the authored design frame")
    func fallbackIsDesignFrame() throws {
        let (store, suite) = try privateStore()
        defer { store.removePersistentDomain(forName: suite) }

        let snapshot = WidgetDisplaySize.snapshot(store: store)
        for family in WidgetKind.week.families {
            #expect(snapshot.referenceSize(of: family) == WidgetMetrics.size(of: family))
        }
        #expect(snapshot.smallGutter == WidgetMetrics.largeWidth - WidgetMetrics.smallSide * 2)
    }

    @Test("Invalid provider frames never replace a valid measurement")
    func invalidFramesAreRefused() throws {
        let (store, suite) = try privateStore()
        defer { store.removePersistentDomain(forName: suite) }

        let valid = CGSize(width: 344.67, height: 360)
        WidgetDisplaySize.record(valid, for: .systemLarge, store: store)
        WidgetDisplaySize.record(.zero, for: .systemLarge, store: store)
        WidgetDisplaySize.record(
            CGSize(width: CGFloat.infinity, height: 360), for: .systemLarge, store: store
        )
        #expect(WidgetDisplaySize.snapshot(store: store).measuredSize(of: .systemLarge) == valid)
    }

    @Test("The provider records displaySize on every WidgetKit path")
    func providerOwnsMeasurement() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("GlowWidget/GlowWidget.swift"),
            encoding: .utf8
        )
        #expect(
            source.components(
                separatedBy: "WidgetDisplaySize.record(context.displaySize, for: context.family)"
            ).count - 1 == 3
        )
    }

    private func privateStore() throws -> (UserDefaults, String) {
        let suite = "WidgetDisplaySizeTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        store.removePersistentDomain(forName: suite)
        return (store, suite)
    }
}
