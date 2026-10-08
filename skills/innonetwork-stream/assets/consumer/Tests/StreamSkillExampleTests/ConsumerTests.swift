import Foundation
import Testing
import InnoNetworkHLS
import InnoNetworkHLSLive
import InnoNetworkHLSAVFoundation
import InnoNetworkHLSAudio
@testable import StreamSkillExample

private let playlist = "#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nsegment.ts\n#EXT-X-ENDLIST\n"
private let source = URL(string: "https://media.example/movie.m3u8")!
// Session-local, stateless deterministic transport; no external media service.
private final class MediaProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let bytes = Data((request.url!.path.hasSuffix("m3u8") ? playlist : "MEDIA").utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MediaProtocol.self]
    return URLSession(configuration: config)
}
private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private actor Latch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

@Suite(.timeLimit(.minutes(1))) struct ConsumerTests {
    @Test func parsesTypedMediaAndMaster() throws {
        let parser = try HLSPlaylistParser()
        let document = try parser.parse(playlist, relativeTo: source)
        guard case .media(let media) = document else { Issue.record("Expected media"); return }
        #expect(media.segmentCount == 1 && media.hasEndList)
        try media.validateSingleFileDownload()
        let master = try parser.parse("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nmovie.m3u8\n", relativeTo: source)
        guard case .multivariant(let variants) = master else { Issue.record("Expected master"); return }
        #expect(variants.variants.count == 1)
    }
    @Test func rejectsMalformedAndOversizedInput() throws {
        let parser = try HLSPlaylistParser(maximumPlaylistBytes: 100)
        #expect(throws: (any Error).self) { try parser.parse("invalid", relativeTo: source) }
        #expect(throws: (any Error).self) { try parser.parse(String(repeating: "x", count: 101), relativeTo: source) }
        if case .failure(let report) = parser.inspect("invalid", relativeTo: source) {
            #expect(report.category == .invalidInput && report.backend == .playlistInspection)
        } else { Issue.record("Expected structured failure") }
    }
    @Test func allMacrosAndManualEquivalents() throws {
        #expect(try MovieDownload.configuration().maximumMediaResourceBytes == ManualDownload.configuration().maximumMediaResourceBytes)
        #expect(try OfflineMovie.configuration().maximumConcurrentResourceTransfers == ManualOffline.configuration().maximumConcurrentResourceTransfers)
        #expect(try ChannelWatch.configuration().minimumPollingInterval == ManualLive.configuration().minimumPollingInterval)
        #expect(try ChannelArchive.configuration().effectiveLimits.maximumSegmentCount == ManualDVR.configuration().effectiveLimits.maximumSegmentCount)
        #expect(try PlaybackProfile.configuration().variant.maximumWidth == ManualPlayback.configuration().variant.maximumWidth)
        #expect(try MediaLibrary.configuration().maximumEntries == ManualCatalog.configuration().maximumEntries)
    }
    @Test func dynamicLimitsRejectInvalidValues() {
        #expect(throws: (any Error).self) { try HLSDownloadConfiguration.validated(maximumConcurrentResourceTransfers: 9) }
        #expect(throws: (any Error).self) { try HLSOfflinePackageConfiguration.validated(maximumMediaResourceBytes: 100, maximumTotalDownloadBytes: 1) }
        #expect(throws: (any Error).self) { try HLSLiveConfiguration.validated(minimumPollingMilliseconds: 100, maximumPollingMilliseconds: 50) }
        #expect(throws: (any Error).self) { try HLSLiveDVRConfiguration.validated(maximumSegmentCount: 0) }
        #expect(throws: (any Error).self) { try HLSPlaybackConfiguration.validated(maximumWidth: 0) }
        #expect(throws: (any Error).self) { try HLSMediaCatalogConfiguration.validated(maximumEntries: 0) }
    }
    @Test func pureFactoryIsNonisolated() async throws {
        _ = try await Task.detached { try ActorDownload.makeDownloader() }.value
    }
    @Test func singleFileTransferAndLateCancellation() async throws {
        let session = makeSession(); defer { session.invalidateAndCancel() }
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("movie.ts")
        let operation = try MovieDownload.start(sourceURL: source, destinationURL: target, session: session)
        let receipt = try await operation.receipt()
        #expect(receipt.destinationURL == target)
        #expect(try Data(contentsOf: target) == Data("MEDIA".utf8))
        operation.cancel()
        #expect(try await operation.receipt().destinationURL == target)
        #expect(operation.state == .completed)
    }
    @Test func offlinePreviewAtomicCommitAndNoOverwrite() async throws {
        let session = makeSession(); defer { session.invalidateAndCancel() }
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("movie.hlspkg")
        let preview = try await OfflineMovie.prepare(sourceURL: source, session: session)
        #expect(preview.resourceTransferCount == 1 && !FileManager.default.fileExists(atPath: target.path))
        let receipt = try await OfflineMovie.downloadPackage(sourceURL: source, destinationDirectoryURL: target, session: session)
        let reopened = try HLSOfflinePackageStore().open(at: target)
        #expect(receipt.byteCount == reopened.byteCount && receipt.byteCount > 5)
        #expect(FileManager.default.fileExists(atPath: receipt.entryPlaylistURL.path))
        await #expect(throws: (any Error).self) {
            try await OfflineMovie.downloadPackage(sourceURL: source, destinationDirectoryURL: target, session: session)
        }
        #expect(try HLSOfflinePackageStore().open(at: target).byteCount == receipt.byteCount)
    }
    @Test func cancelledObserverDoesNotCancelOfflineOwner() async throws {
        let session = makeSession(); defer { session.invalidateAndCancel() }
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let entered = Latch(), permitted = Latch()
        defer { Task { await permitted.release() } }
        let policy = HLSRequestPolicy { request, _ in
            await entered.release()
            await permitted.wait()
            return request
        }
        let owner = try OfflineMovie.start(sourceURL: source, destinationDirectoryURL: directory.appendingPathComponent("owned.hlspkg"), session: session, requestPolicy: policy)
        await entered.wait()
        let observations = try owner.events()
        let observer = Task { for try await _ in observations {} }
        observer.cancel()
        _ = await observer.result
        #expect(owner.state == .running)
        await permitted.release()
        let receipt = try await owner.receipt()
        owner.cancel()
        #expect(try await owner.receipt().directoryURL == receipt.directoryURL)
        #expect(try HLSOfflinePackageStore().open(at: receipt.directoryURL).byteCount == receipt.byteCount)
    }
    @Test func cancellationBeforeTransportPublishesNothing() async throws {
        let session = makeSession(); defer { session.invalidateAndCancel() }
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("cancelled.hlspkg")
        let policy = HLSRequestPolicy { _, _ in throw CancellationError() }
        await #expect(throws: CancellationError.self) {
            try await OfflineMovie.downloadPackage(sourceURL: source, destinationDirectoryURL: target, session: session, requestPolicy: policy)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }
    @Test func liveEndListIsAwaitableWithoutObserver() async throws {
        let session = makeSession(); defer { session.invalidateAndCancel() }
        let watch = try ChannelWatch.watch(from: source, session: session)
        _ = try await watch.finalSnapshot()
        #expect(watch.state == .completed)
        watch.cancel()
        _ = try await watch.finalSnapshot()
    }
    @Test func catalogCapacityAndReconciliation() async throws {
        let catalog = try MediaLibrary.makeCatalog()
        let first = try HLSMediaRecord(id: HLSMediaID(), ownership: .offlinePackage, reference: "movie-1")
        try await catalog.upsert(first)
        try await catalog.upsert(HLSMediaRecord(id: HLSMediaID(), ownership: .applicationFile, reference: "movie-2"))
        await #expect(throws: HLSMediaCatalogError.capacityExceeded) {
            try await catalog.upsert(HLSMediaRecord(id: HLSMediaID(), ownership: .applicationFile, reference: "movie-3"))
        }
        try await catalog.reconcile { _ in .missing }
        let snapshot = await catalog.snapshot()
        #expect(snapshot.count == 2 && snapshot.allSatisfy { $0.availability == .missing })
        #expect(throws: HLSMediaCatalogError.invalidReference) {
            try HLSMediaRecord(id: HLSMediaID(), ownership: .applicationFile, reference: "https://media.example/file")
        }
    }
    @Test func failureAndCapabilitiesDoNotAuthorizeRecovery() {
        let cancelled = HLSFailureReport.classify(CancellationError(), backend: .offlinePackage)
        #expect(cancelled.category == .cancelled && cancelled.recovery == .none)
        let auth = HLSFailureReport.classify(HLSDownloadError.invalidResponseStatus(401), backend: .singleFileDownload)
        #expect(auth.category == .authorization && auth.recovery == .provideFreshAuthorization)
        #expect(HLSBackendCapabilities.forBackend(.nativeBackgroundDownload).supportsSystemRestoration)
        #expect(!HLSBackendCapabilities.forBackend(.liveWatch).supportsCheckpointRecovery)
    }
    #if compiler(>=6.4)
    @Test func guardedAudioConfiguration() throws {
        if #available(macOS 27, *) { _ = try HLSDecodedAudioConfiguration.float32(sampleRate: 48_000, channelCount: 2) }
    }
    #endif
}
