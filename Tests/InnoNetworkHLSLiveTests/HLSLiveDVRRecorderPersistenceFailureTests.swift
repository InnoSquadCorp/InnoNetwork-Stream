import Foundation
import InnoNetworkHLS
import Testing

@testable import InnoNetworkHLSLive

// These tests use the same URLProtocol registry and serialization boundary as
// the other network-backed live tests. They exercise recorder error cleanup,
// not just the checkpoint store in isolation.
extension HLSLivePlaylistClientTests {
    @Test(
        "rolling recorder preserves a recoverable boundary when checkpoint persistence fails",
        arguments: DVRRecorderPersistenceBoundary.allCases
    )
    func rollingRecorderRecoversAfterPersistenceFailure(at boundary: DVRRecorderPersistenceBoundary) async throws {
        let fixture = try DVRPersistenceRecorderFixture()
        defer { fixture.cleanup() }
        fixture.registerPlaylist(through: 4, at: fixture.sourceURL)
        for sequence in 1...4 { fixture.registerMedia(sequence) }
        let probe = DVRRecorderPersistenceProbe()
        let failing = fixture.recorder(
            persistence: fixture.failingPersistence(at: boundary, sequence: 3, probe: probe))

        await #expect(throws: HLSLiveDVRError.storageFailed) {
            try await failing.record(from: fixture.sourceURL, to: fixture.destinationURL)
        }
        #expect(probe.failureCount == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.destinationURL.path))
        let checkpoint = try fixture.readCheckpoint()
        let expectedSequences: [Int64] = boundary == .beforeReplacement ? [1, 2] : [2, 3]
        #expect(checkpoint.primary.segments.map(\.sequenceNumber) == expectedSequences)
        try fixture.validateFiles(checkpoint)
        // The recorder must not evict sequence 1 before save succeeds, even
        // when replacement happened and its following fsync threw.
        for sequence in 1...3 {
            #expect(try Data(contentsOf: fixture.resourceURL(sequence)) == fixture.media(sequence))
        }
        let orphan = boundary == .beforeReplacement ? 3 : 1
        let resumedSourceURL = fixture.sourceURL.appending(queryItems: [URLQueryItem(name: "resume", value: "1")])
        fixture.registerPlaylist(through: 4, at: resumedSourceURL)
        if boundary == .beforeReplacement { fixture.registerMedia(3) }
        let resumed = fixture.recorder(
            requestPolicy: HLSRequestPolicy { request, _ in
                if request.url == resumedSourceURL {
                    // resume() prunes untracked files before its first network
                    // request. Observe the real recorder's cleanup, rather
                    // than calling the store's resume() from the test.
                    #expect(!FileManager.default.fileExists(atPath: fixture.resourceURL(orphan).path))
                    try fixture.validateFiles(checkpoint)
                }
                return request
            })
        let receipt = try await resumed.resume(from: resumedSourceURL, to: fixture.destinationURL)
        #expect(receipt.firstMediaSequence == 3)
        #expect(receipt.lastMediaSequence == 4)
        #expect(receipt.segmentCount == 2)
        #expect(receipt.retentionStatistics.evictedPrimarySegmentCount == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.rootURL.path))
        let resources = fixture.destinationURL.appendingPathComponent("resources")
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: resources.path).sorted()
                == ["sequence-3.ts", "sequence-4.ts"])
        for sequence in 3...4 {
            #expect(
                try Data(contentsOf: resources.appendingPathComponent("sequence-\(sequence).ts"))
                    == fixture.media(sequence))
        }
        let local = try HLSLocalPlaybackSource(
            packageDirectoryURL: receipt.directoryURL, entryPlaylistURL: receipt.entryPlaylistURL)
        _ = try HLSLocalPlaybackPackageSnapshot(source: local)
        let requests = HLSLiveURLProtocol.capturedRequests().compactMap(\.url)
        #expect(requests.contains(resumedSourceURL))
        let mediaRequests = requests.filter { $0.pathExtension == "ts" }.map(\.lastPathComponent)
        let expectedRequests =
            boundary == .beforeReplacement
            ? ["segment-1.ts", "segment-2.ts", "segment-3.ts", "segment-3.ts", "segment-4.ts"]
            : ["segment-1.ts", "segment-2.ts", "segment-3.ts", "segment-4.ts"]
        #expect(mediaRequests == expectedRequests)
    }

    @Test(
        "failure at the first recorder checkpoint removes incomplete recovery and permits a fresh retry",
        arguments: DVRRecorderPersistenceBoundary.allCases
    )
    func firstRecorderCheckpointFailureCleansRecovery(at boundary: DVRRecorderPersistenceBoundary) async throws {
        let fixture = try DVRPersistenceRecorderFixture()
        defer { fixture.cleanup() }
        fixture.registerPlaylist(through: 1, at: fixture.sourceURL)
        fixture.registerMedia(1)
        let probe = DVRRecorderPersistenceProbe()
        let failing = fixture.recorder(
            persistence: fixture.failingPersistence(at: boundary, sequence: 1, probe: probe))
        await #expect(throws: HLSLiveDVRError.storageFailed) {
            try await failing.record(from: fixture.sourceURL, to: fixture.destinationURL)
        }
        #expect(probe.failureCount == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.destinationURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.store.rootURL.path))
        let fresh = fixture.recorder()
        await #expect(throws: HLSLiveDVRError.recoveryUnavailable) {
            try await fresh.resume(from: fixture.sourceURL, to: fixture.destinationURL)
        }
        fixture.registerPlaylist(through: 1, at: fixture.sourceURL)
        fixture.registerMedia(1)
        let receipt = try await fresh.record(from: fixture.sourceURL, to: fixture.destinationURL)
        #expect(receipt.firstMediaSequence == 1)
        #expect(receipt.lastMediaSequence == 1)
        #expect(receipt.segmentCount == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.rootURL.path))
        let file = fixture.destinationURL.appendingPathComponent("resources/sequence-1.ts")
        #expect(try Data(contentsOf: file) == fixture.media(1))
        #expect(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.destinationURL.appendingPathComponent("resources").path)
                == ["sequence-1.ts"])
    }
}

// A post-replacement synchronization failure has a complete new checkpoint
// visible to this process, but does not establish power-loss durability.
enum DVRRecorderPersistenceBoundary: CaseIterable, Equatable, Sendable {
    case beforeReplacement
    case afterReplacementSync
}

private final class DVRRecorderPersistenceProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var failureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func recordFailure() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private struct DVRPersistenceRecorderFixture: Sendable {
    let rootURL: URL
    let destinationURL: URL
    let sourceURL: URL
    let session: URLSession

    var store: HLSLiveDVRCheckpointStore {
        HLSLiveDVRCheckpointStore(destinationURL: destinationURL)
    }

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DVRRecorderPersistenceFailure-\(UUID().uuidString)", isDirectory: true)
        destinationURL = rootURL.appendingPathComponent("recording", isDirectory: true)
        sourceURL = try #require(URL(string: "https://media.example/recorder-persistence.m3u8"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HLSLiveURLProtocol.self]
        session = URLSession(configuration: configuration)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        session.invalidateAndCancel()
        HLSLiveURLProtocol.reset()
        try? FileManager.default.removeItem(at: rootURL)
    }

    func media(_ sequence: Int) -> Data {
        Data("media-\(sequence)".utf8)
    }

    func registerPlaylist(through last: Int, at source: URL) {
        let segments = (1...last).map { "#EXTINF:4,\nsegment-\($0).ts" }.joined(separator: "\n")
        let text = """
            #EXTM3U
            #EXT-X-TARGETDURATION:4
            #EXT-X-MEDIA-SEQUENCE:1
            \(segments)
            #EXT-X-ENDLIST
            """
        HLSLiveURLProtocol.register(
            HLSLiveURLProtocol.Response(
                statusCode: 200, data: Data(text.utf8),
                headers: ["Content-Type": "application/vnd.apple.mpegurl"]),
            for: source)
    }

    func registerMedia(_ sequence: Int) {
        let url = sourceURL.deletingLastPathComponent().appendingPathComponent("segment-\(sequence).ts")
        HLSLiveURLProtocol.register(
            HLSLiveURLProtocol.Response(
                statusCode: 200, data: media(sequence),
                headers: ["Content-Type": "video/mp2t", "Content-Length": "\(media(sequence).count)"]),
            for: url)
    }

    func resourceURL(_ sequence: Int) -> URL {
        store.workspace.directoryURL.appendingPathComponent("resources/sequence-\(sequence).ts")
    }

    func readCheckpoint() throws -> HLSLiveDVRCheckpoint {
        try JSONDecoder().decode(
            HLSLiveDVRCheckpoint.self,
            from: Data(contentsOf: store.rootURL.appendingPathComponent("checkpoint.json")))
    }

    func validateFiles(_ checkpoint: HLSLiveDVRCheckpoint) throws {
        for file in checkpoint.files {
            let url = store.workspace.directoryURL.appendingPathComponent(file.relativePath)
            #expect(try Data(contentsOf: url).count == Int(file.byteCount))
            #expect(try HLSContentFingerprint.sha256(contentsOf: url) == file.contentSHA256)
        }
    }

    func recorder(
        persistence: HLSLiveDVRCheckpointStore.Persistence = .init(),
        requestPolicy: HLSRequestPolicy = HLSRequestPolicy()
    ) -> HLSLiveDVRRecorder {
        HLSLiveDVRRecorder(
            client: HLSLivePlaylistClient(session: session, requestPolicy: requestPolicy),
            configuration: .advanced(
                limits: HLSLiveDVRLimitPack(
                    maximumDuration: 60, maximumSegmentCount: 2,
                    maximumMediaResourceBytes: 1_024, maximumTotalMediaBytes: 4_096,
                    retentionPolicy: .rollingWindow),
                startPosition: .currentWindow,
                recovery: HLSLiveDVRRecoveryPack(policy: .resumable)),
            checkpointPersistence: persistence)
    }

    func failingPersistence(
        at boundary: DVRRecorderPersistenceBoundary,
        sequence: Int,
        probe: DVRRecorderPersistenceProbe
    ) -> HLSLiveDVRCheckpointStore.Persistence {
        var persistence = HLSLiveDVRCheckpointStore.Persistence()
        let write = persistence.writeCheckpoint
        persistence.writeCheckpoint = { data, url in
            let next = try JSONDecoder().decode(HLSLiveDVRCheckpoint.self, from: data)
            if next.primary.segments.last?.sequenceNumber == Int64(sequence) {
                if sequence == 3 {
                    let previous = try readCheckpoint()
                    #expect(previous.primary.segments.map(\.sequenceNumber) == [1, 2])
                    try validateFiles(previous)
                } else {
                    #expect(!FileManager.default.fileExists(atPath: url.path))
                }
                if boundary == .beforeReplacement {
                    probe.recordFailure()
                    throw POSIXError(.ENOSPC)
                }
            }
            try write(data, url)
        }
        let synchronize = persistence.synchronizeFile
        let checkpointURL = store.rootURL.appendingPathComponent("checkpoint.json")
        persistence.synchronizeFile = { url in
            if boundary == .afterReplacementSync, url == checkpointURL,
                try readCheckpoint().primary.segments.last?.sequenceNumber == Int64(sequence)
            {
                // Every old referenced resource is still present at the
                // post-replacement error boundary; eviction has not run.
                for retained in 1...sequence {
                    #expect(try Data(contentsOf: resourceURL(retained)) == media(retained))
                }
                probe.recordFailure()
                throw POSIXError(.EIO)
            }
            try synchronize(url)
        }
        return persistence
    }
}
