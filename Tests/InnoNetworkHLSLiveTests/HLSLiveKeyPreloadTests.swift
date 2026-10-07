import Foundation
import InnoNetworkHLS
import Testing

@testable import InnoNetworkHLSLive

@Suite("HLS live key preloading")
struct HLSLiveKeyPreloadTests {
    @Test("key preloads are spread across the projected first-use window")
    func spreadsKeyPreloadAcrossWindow() async throws {
        let sourceURL = try #require(
            URL(string: "https://media.example/live.m3u8")
        )
        let playlist = try PlaylistResolver().resolve(
            """
            #EXTM3U
            #EXT-X-PROGRAM-DATE-TIME:2026-08-06T12:00:00Z
            #EXTINF:4,
            current.ts
            #EXT-X-PRELOAD-HINT:TYPE=KEY,URI="next.key",METHOD=AES-128,DATE-OF-FIRST-USE="2026-08-06T12:00:08Z"
            """,
            relativeTo: sourceURL
        )
        let hint = try #require(
            playlist.lowLatency?.preloadHints.first
        )
        let preloader = HLSLiveKeyPreloadRecorder()
        let sleeps = HLSLiveSleepRecorder()
        let coordinator = HLSLiveKeyPreloadCoordinator(
            preloader: preloader,
            sleep: { duration in
                await sleeps.record(duration)
            },
            randomUnitInterval: { 0.5 }
        )
        let snapshot = HLSLivePlaylistSnapshot(
            playlist: playlist,
            segments: [
                HLSLiveSegment(
                    sequenceNumber: 0,
                    duration: 4,
                    url: sourceURL,
                    byteRange: nil,
                    beginsDiscontinuity: false,
                    isGap: false
                )
            ],
            partialSegments: [],
            dateRanges: [],
            generation: 0,
            isDeltaUpdate: false,
            isEnded: false
        )

        await coordinator.update(after: snapshot)
        await coordinator.update(after: snapshot)
        do {
            try await keyPreloadEventually { !(await preloader.hints()).isEmpty }
        } catch {
            await coordinator.cancelAll()
            throw error
        }

        #expect(await sleeps.durations() == [.seconds(2)])
        #expect(await preloader.hints() == [hint])
        await coordinator.cancelAll()
    }

    @Test("removing hints and cancelAll observably cancel pending sleeps", arguments: [false, true])
    func cancelsPendingKeyPreload(cancelAll: Bool) async throws {
        let hinted = try keyPlaylist()
        let cleared = try PlaylistResolver().resolve(
            "#EXTM3U\n#EXTINF:4,\ncurrent.ts\n",
            relativeTo: #require(URL(string: "https://media.example/live.m3u8"))
        )
        let preloader = HLSLiveKeyPreloadRecorder()
        let pendingSleep = HLSLiveKeyCancellationProbe()
        let coordinator = HLSLiveKeyPreloadCoordinator(
            preloader: preloader,
            sleep: { _ in try await pendingSleep.suspend() },
            randomUnitInterval: { 1 }
        )
        await coordinator.update(after: snapshot(playlist: hinted))
        do {
            // Cancellation must hit an actually registered sleep, not merely
            // remove a task before the scheduler has run it.
            try await keyPreloadEventually { await pendingSleep.enteredCount == 1 }
            if cancelAll {
                await coordinator.cancelAll()
            } else {
                await coordinator.update(after: snapshot(playlist: cleared))
            }
            try await keyPreloadEventually { await pendingSleep.cancelledCount == 1 }
            #expect(await preloader.hints().isEmpty)

            // An identical hint can be scheduled again after cancellation.
            await coordinator.update(after: snapshot(playlist: hinted))
            try await keyPreloadEventually { await pendingSleep.enteredCount == 2 }
            await coordinator.cancelAll()
            try await keyPreloadEventually { await pendingSleep.cancelledCount == 2 }
            #expect(await preloader.hints().isEmpty)
        } catch {
            await coordinator.cancelAll()
            throw error
        }
    }

    @Test("removing hints and cancelAll propagate cancellation into active callbacks", arguments: [false, true])
    func cancelsActiveKeyPreload(cancelAll: Bool) async throws {
        let hinted = try keyPlaylist()
        let cleared = try PlaylistResolver().resolve(
            "#EXTM3U\n#EXTINF:4,\ncurrent.ts\n",
            relativeTo: #require(URL(string: "https://media.example/live.m3u8"))
        )
        let preloader = HLSLiveCancellableKeyPreloader()
        let coordinator = HLSLiveKeyPreloadCoordinator(
            preloader: preloader,
            sleep: { _ in },
            randomUnitInterval: { 0 }
        )
        await coordinator.update(after: snapshot(playlist: hinted))
        do {
            try await keyPreloadEventually { await preloader.probe.enteredCount == 1 }
            if cancelAll {
                await coordinator.cancelAll()
            } else {
                await coordinator.update(after: snapshot(playlist: cleared))
            }
            try await keyPreloadEventually { await preloader.probe.cancelledCount == 1 }
            await coordinator.update(after: snapshot(playlist: hinted))
            try await keyPreloadEventually { await preloader.probe.enteredCount == 2 }
            await coordinator.cancelAll()
            try await keyPreloadEventually { await preloader.probe.cancelledCount == 2 }
        } catch {
            await coordinator.cancelAll()
            throw error
        }
    }

    private func keyPlaylist() throws -> HLSPlaylist {
        try PlaylistResolver().resolve(
            """
            #EXTM3U
            #EXT-X-PRELOAD-HINT:TYPE=KEY,URI="next.key",METHOD=AES-128
            """,
            relativeTo: #require(URL(string: "https://media.example/live.m3u8"))
        )
    }

    private func snapshot(
        playlist: HLSPlaylist
    ) -> HLSLivePlaylistSnapshot {
        HLSLivePlaylistSnapshot(
            playlist: playlist,
            segments: [],
            partialSegments: [],
            dateRanges: [],
            generation: 0,
            isDeltaUpdate: false,
            isEnded: false
        )
    }
}

private actor HLSLiveKeyPreloadRecorder:
    HLSLiveEncryptionKeyPreloading
{
    private var recordedHints: [HLSPreloadHint] = []

    func preloadEncryptionKey(
        for hint: HLSPreloadHint
    ) {
        recordedHints.append(hint)
    }

    func hints() -> [HLSPreloadHint] {
        recordedHints
    }
}

private actor HLSLiveSleepRecorder {
    private var recordedDurations: [Duration] = []

    func record(_ duration: Duration) {
        recordedDurations.append(duration)
    }

    func durations() -> [Duration] {
        recordedDurations
    }
}

// An actor-owned observation of entry and CancellationError avoids fixed yields
// and proves that cancellation reached the suspended operation.
private actor HLSLiveKeyCancellationProbe {
    private(set) var enteredCount = 0
    private(set) var cancelledCount = 0

    func suspend() async throws {
        enteredCount += 1
        do {
            try await ContinuousClock().sleep(for: .seconds(3_600))
        } catch is CancellationError {
            cancelledCount += 1
            throw CancellationError()
        }
    }
}

private struct HLSLiveCancellableKeyPreloader: HLSLiveEncryptionKeyPreloading {
    let probe = HLSLiveKeyCancellationProbe()

    func preloadEncryptionKey(for hint: HLSPreloadHint) async {
        try? await probe.suspend()
    }
}

private func keyPreloadEventually(
    _ condition: @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()) {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else {
            throw HLSLiveKeyObservationTimeout()
        }
        await Task.yield()
    }
}

private struct HLSLiveKeyObservationTimeout: Error {}
