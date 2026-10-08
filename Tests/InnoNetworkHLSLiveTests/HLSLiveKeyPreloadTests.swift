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

    @Test(
        "late cancelled tasks cannot finish a replacement with the same hint",
        arguments: [false, true], [false, true]
    )
    func lateCancellationPreservesReplacement(cancelAll: Bool, activeCallback: Bool) async throws {
        let hinted = try keyPlaylist()
        let cleared = try PlaylistResolver().resolve(
            "#EXTM3U\n#EXTINF:4,\ncurrent.ts\n",
            relativeTo: #require(URL(string: "https://media.example/live.m3u8"))
        )
        let gate = HLSLiveLateCancellationGate()
        let callbacks = HLSLiveKeyPreloadRecorder()
        let preloader: any HLSLiveEncryptionKeyPreloading
        if activeCallback {
            preloader = HLSLiveLateKeyPreloader(gate: gate)
        } else {
            preloader = callbacks
        }
        let coordinator = HLSLiveKeyPreloadCoordinator(
            preloader: preloader,
            sleep: { _ in
                if !activeCallback { try await gate.suspendUntilCancelledAndReleased() }
            },
            randomUnitInterval: { 0 }
        )
        var observedTasks: [Task<Void, Never>] = []
        do {
            await coordinator.update(after: snapshot(playlist: hinted))
            let firstTasks = await coordinator.scheduledTaskSnapshot()
            observedTasks += firstTasks
            #expect(firstTasks.count == 1)
            let first = try #require(firstTasks.first)
            try await keyPreloadEventually { await gate.enteredCount == 1 }
            if cancelAll {
                await coordinator.cancelAll()
            } else {
                await coordinator.update(after: snapshot(playlist: cleared))
            }
            try await keyPreloadEventually { await gate.cancelledIDs.contains(1) }

            // The cancelled first operation cannot return until explicitly
            // released. Start the replacement while that old task is alive.
            await coordinator.update(after: snapshot(playlist: hinted))
            let replacementTasks = await coordinator.scheduledTaskSnapshot()
            observedTasks += replacementTasks
            #expect(replacementTasks.count == 1)
            let replacement = try #require(replacementTasks.first)
            try await keyPreloadEventually { await gate.enteredCount == 2 }
            #expect(await gate.releasedIDs.isEmpty)
            await gate.release(1)
            await first.value

            // Waiting for the actual task includes coordinator.finish, not
            // merely the callback's return. The stale UUID must be ignored.
            #expect(await coordinator.scheduledTaskSnapshot().count == 1)
            await coordinator.update(after: snapshot(playlist: hinted))
            #expect(await coordinator.scheduledTaskSnapshot().count == 1)
            #expect(await gate.enteredCount == 2)
            await coordinator.cancelAll()
            try await keyPreloadEventually { await gate.cancelledIDs.contains(2) }
            await gate.release(2)
            await replacement.value
            #expect(await coordinator.scheduledTaskSnapshot().isEmpty)
            #expect(await callbacks.hints().isEmpty)

            // cancelAll also resets completed identities; a late old callback
            // must not poison the next use of the same hint.
            await coordinator.update(after: snapshot(playlist: hinted))
            let finalTasks = await coordinator.scheduledTaskSnapshot()
            observedTasks += finalTasks
            #expect(finalTasks.count == 1)
            let lastTask = try #require(finalTasks.first)
            try await keyPreloadEventually { await gate.enteredCount == 3 }
            await coordinator.cancelAll()
            try await keyPreloadEventually { await gate.cancelledIDs.contains(3) }
            await gate.release(3)
            await lastTask.value
            #expect(await coordinator.scheduledTaskSnapshot().isEmpty)
        } catch {
            await coordinator.cancelAll()
            for task in observedTasks { task.cancel() }
            await gate.close()
            for task in observedTasks { await task.value }
            throw error
        }
        await gate.close()
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

// Both phases are continuation gates. No elapsed sleep is used to arrange the
// overlap, and close() drains waiters even when a test assertion throws.
private actor HLSLiveLateCancellationGate {
    private(set) var enteredCount = 0
    private(set) var cancelledIDs: Set<Int> = []
    private(set) var releasedIDs: Set<Int> = []
    private var cancellationWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var releaseWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var isClosed = false

    func suspendUntilCancelledAndReleased() async throws {
        enteredCount += 1
        let id = enteredCount
        await withTaskCancellationHandler {
            await waitForCancellation(id)
        } onCancel: {
            Task { await self.observeCancellation(id) }
        }
        await waitForRelease(id)
        throw CancellationError()
    }

    private func waitForCancellation(_ id: Int) async {
        guard !isClosed, !cancelledIDs.contains(id) else { return }
        await withCheckedContinuation { cancellationWaiters[id] = $0 }
    }

    private func observeCancellation(_ id: Int) {
        cancelledIDs.insert(id)
        cancellationWaiters.removeValue(forKey: id)?.resume()
    }

    private func waitForRelease(_ id: Int) async {
        guard !isClosed, !releasedIDs.contains(id) else { return }
        await withCheckedContinuation { releaseWaiters[id] = $0 }
    }

    func release(_ id: Int) {
        releasedIDs.insert(id)
        releaseWaiters.removeValue(forKey: id)?.resume()
    }

    func close() {
        isClosed = true
        let pending = Array(cancellationWaiters.values) + Array(releaseWaiters.values)
        cancellationWaiters.removeAll()
        releaseWaiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private struct HLSLiveLateKeyPreloader: HLSLiveEncryptionKeyPreloading {
    let gate: HLSLiveLateCancellationGate

    func preloadEncryptionKey(for hint: HLSPreloadHint) async {
        try? await gate.suspendUntilCancelledAndReleased()
    }
}
