import Foundation
import InnoNetwork
import InnoNetworkHLS
import Testing

@testable import InnoNetworkHLSLive

@Suite("DVR cancellation ownership handoffs")
struct HLSCancellationHandoffTests {
    @Test("cancelled registration immediately releases its reserved snapshot slot")
    func cancellationDuringRegistration() async throws {
        let gate = DVRSnapshotReservationGate()
        let control = HLSLiveDVRRecordingControl(snapshotReservationObserver: { await gate.pause() })
        let request = HLSLiveDVRPlaybackSnapshotRequest(
            destinationDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let watchdog = Task {
            try? await ContinuousClock().sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await gate.release()
        }
        defer { watchdog.cancel() }
        let registration = Task { try await control.registerPlaybackSnapshotRequest(request) }
        await gate.waitUntilEntered()
        #expect(await gate.hasEntered)
        #expect(await control.outstandingPlaybackSnapshotRequestCount == 1)
        await request.cancel()
        await control.cancelPlaybackSnapshotRequest(request)
        await gate.release()
        try await registration.value
        await #expect(throws: CancellationError.self) { try await request.value() }
        #expect(await control.outstandingPlaybackSnapshotRequestCount == 0)
        for _ in 0..<8 {
            let next = HLSLiveDVRPlaybackSnapshotRequest(
                destinationDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
            try await control.registerPlaybackSnapshotRequest(next)
        }
        #expect(await control.outstandingPlaybackSnapshotRequestCount == 8)
        await control.finishPlaybackSnapshotRequests()
        #expect(await control.outstandingPlaybackSnapshotRequestCount == 0)
    }

    @Test("terminal snapshot receipt and failure win during registration", arguments: [false, true])
    func terminalResolutionDuringRegistration(succeeds: Bool) async throws {
        let gate = DVRSnapshotReservationGate()
        let control = HLSLiveDVRRecordingControl(snapshotReservationObserver: { await gate.pause() })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let request = HLSLiveDVRPlaybackSnapshotRequest(destinationDirectoryURL: directory)
        let receipt = HLSLiveDVRReceipt(
            directoryURL: directory, playlistURL: directory.appendingPathComponent("index.m3u8"),
            entryPlaylistURL: directory.appendingPathComponent("index.m3u8"), tracks: [],
            segmentCount: 1, recordedDuration: 1, mediaByteCount: 1, firstMediaSequence: 0, lastMediaSequence: 0
        )
        let watchdog = Task {
            try? await ContinuousClock().sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await gate.release()
        }
        defer { watchdog.cancel() }
        let registration = Task { try await control.registerPlaybackSnapshotRequest(request) }
        await gate.waitUntilEntered()
        #expect(await gate.hasEntered)
        if succeeds { await request.succeed(receipt) }
        else { await request.fail(.playbackSnapshotUnavailable) }
        await gate.release()
        try await registration.value
        if succeeds {
            #expect(try await request.value() == receipt)
        } else {
            await #expect(throws: HLSLiveDVRError.playbackSnapshotUnavailable) { try await request.value() }
        }
        #expect(await control.outstandingPlaybackSnapshotRequestCount == 0)
    }

    @Test("cancelled PART and MAP consumers cancel the task removed from the coordinator", arguments: [false, true])
    func consumedPreloadCancellation(isMap: Bool) async throws {
        let source = try #require(URL(string: "https://media.example/handoff.m3u8"))
        let kind = isMap ? "MAP" : "PART"
        let name = isMap ? "init.mp4" : "part.ts"
        let header = """
            #EXTM3U
            #EXT-X-VERSION:10
            #EXT-X-TARGETDURATION:1
            #EXT-X-MEDIA-SEQUENCE:11
            #EXT-X-PART-INF:PART-TARGET=1
            """
        let hint = try snapshot(
            header + "\n#EXT-X-PRELOAD-HINT:TYPE=\(kind),URI=\"\(name)\"", source: source
        )
        let actual = try snapshot(
            header + (isMap ? "\n#EXT-X-MAP:URI=\"init.mp4\"" : "")
                + "\n#EXT-X-PART:DURATION=1,URI=\"part.ts\",INDEPENDENT=YES", source: source
        )
        let part = try #require(actual.partialSegments.first)
        let initialization = actual.playlist.lowLatency?.initializationMaps.first.map {
            HLSLiveInitializationSegment(resource: $0.resource)
        }
        if isMap { _ = try #require(initialization) }
        let gate = DVRPreloadCancellationGate()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let client = HLSLivePlaylistClient(
            session: session,
            requestPolicy: HLSRequestPolicy { _, _ in
                try await gate.waitForCancellation()
                throw CancellationError()
            }
        )
        let configuration = HLSLiveDVRConfiguration.advanced(
            limits: HLSLiveDVRLimitPack(diskCapacityPolicy: .disabled),
            parts: HLSLiveDVRPartPack(policy: .independent),
            preloading: HLSLiveDVRPreloadPack(policy: .unencryptedMedia)
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try HLSLiveDVRWorkspace.make(for: root.appendingPathComponent("result"))
        let writer = HLSLiveDVRResourceWriter(client: client.resourceClient, configuration: configuration)
        let coordinator = try #require(writer.makePreloadCoordinator(
            workspace: workspace, context: writer.makeContext(workspace: workspace)
        ))
        // Safety release prevents a failing old implementation from hanging.
        // All ordering assertions use the entered barrier, not this timeout.
        let watchdog = Task {
            try? await ContinuousClock().sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await gate.releaseWithoutCancellation()
        }
        defer { watchdog.cancel() }
        await coordinator.update(from: hint)
        await gate.waitUntilEntered()
        #expect(await gate.hasEntered)
        await coordinator.update(from: actual)
        let destination = workspace.directoryURL.appendingPathComponent("consumed")
        let consumer = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            if let initialization, isMap {
                return await coordinator.consume(initialization, to: destination, maximumRetainedBytes: 1_024)
            }
            return await coordinator.consume(part, to: destination, maximumRetainedBytes: 1_024)
        }
        #expect(await consumer.value == nil)
        #expect(await gate.observedTaskCancellation)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let statistics = await coordinator.cancelAll()
        let kindStatistics = isMap ? statistics.initializationMaps : statistics.partialSegments
        #expect(kindStatistics.confirmedCount == 1)
        #expect(kindStatistics.cancellationCount == 1)
        #expect(kindStatistics.reuseCount == 0)
    }

    private func snapshot(_ contents: String, source: URL) throws -> HLSLivePlaylistSnapshot {
        let playlist = try HLSPlaylistParser().parse(contents, relativeTo: source).legacyPlaylist
        let parts = (playlist.lowLatency?.partialSegments ?? []).enumerated().map { index, part in
            HLSLivePartialSegment(
                mediaSequenceNumber: 11 + Int64(part.segmentIndex), partIndex: index,
                duration: part.duration, url: part.url, byteRange: part.byteRange,
                isIndependent: part.isIndependent, isGap: part.isGap, resourceContext: part.resourceContext
            )
        }
        return HLSLivePlaylistSnapshot(
            playlist: playlist, segments: [], partialSegments: parts, dateRanges: [],
            generation: 0, isDeltaUpdate: false, isEnded: false
        )
    }
}

private actor DVRSnapshotReservationGate {
    private var entered = false
    private var released = false
    private var starts: [CheckedContinuation<Void, Never>] = []
    private var blocker: CheckedContinuation<Void, Never>?

    func pause() async {
        entered = true
        starts.forEach { $0.resume() }
        starts.removeAll()
        guard !released else { return }
        await withCheckedContinuation { blocker = $0 }
    }

    var hasEntered: Bool { entered }

    func waitUntilEntered() async {
        guard !entered, !released else { return }
        await withCheckedContinuation { starts.append($0) }
    }

    func release() {
        released = true
        starts.forEach { $0.resume() }
        starts.removeAll()
        blocker?.resume()
        blocker = nil
    }
}

private actor DVRPreloadCancellationGate {
    private enum Failure: Error { case safetyRelease }
    private var entered = false
    private var released = false
    private var starts: [CheckedContinuation<Void, Never>] = []
    private var blocker: CheckedContinuation<Void, Error>?
    private(set) var observedTaskCancellation = false

    func waitForCancellation() async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                entered = true
                starts.forEach { $0.resume() }
                starts.removeAll()
                if released { continuation.resume(throwing: Failure.safetyRelease) }
                else { blocker = continuation }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    var hasEntered: Bool { entered }

    func waitUntilEntered() async {
        guard !entered, !released else { return }
        await withCheckedContinuation { starts.append($0) }
    }

    private func cancel() {
        observedTaskCancellation = true
        blocker?.resume(throwing: CancellationError())
        blocker = nil
    }

    func releaseWithoutCancellation() {
        released = true
        starts.forEach { $0.resume() }
        starts.removeAll()
        blocker?.resume(throwing: Failure.safetyRelease)
        blocker = nil
    }
}
