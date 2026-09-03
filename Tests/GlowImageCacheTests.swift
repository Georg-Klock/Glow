import Foundation
import Testing
@testable import Glow

@MainActor
@Suite("Glow image cache")
struct GlowImageCacheTests {
    @Test("A cold tile is prepared before body can read it")
    func preparationPopulatesTheLookup() async throws {
        let cache = GlowImageCache()
        let peak = 3.0

        #expect(cache.cachedTile(peak: peak) == nil)
        let prepared = try #require(await cache.prepare(peak: peak))
        #expect(cache.cachedTile(peak: peak) === prepared)
    }

    @Test("Launch warming covers every reachable slider stop")
    func sliderStopsAreFiniteAndComplete() async {
        let cache = GlowImageCache()

        #expect(GlowSettings.sliderStops == [1, 2, 3, 4, 5, 6, 7, 8])
        await cache.prepare(peaks: GlowSettings.sliderStops)
        for peak in GlowSettings.sliderStops {
            #expect(cache.cachedTile(peak: peak) != nil)
        }
    }

    @Test("The view body can look up a tile but cannot encode one")
    func viewBodyContainsNoRenderer() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "Glow/Glow/GlowImageCache.swift"),
            encoding: .utf8
        )
        let body = try #require(
            source.split(separator: "private struct GlowTile: View", maxSplits: 1).last
        )

        #expect(body.contains("cachedTile(peak: peak)"))
        #expect(body.contains(".task(id: key)"))
        #expect(!body.contains("renderer.imageData"))
        #expect(!body.contains("heif10Representation"))
    }

    @Test("The headroom poll does not publish an unchanged sample")
    func headroomPollGuardsItsStateWrite() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "Glow/Views/SettingsView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("if sampled != headroom { headroom = sampled }"))
        #expect(!source.contains("headroom = .mainScreen"))
    }
}
