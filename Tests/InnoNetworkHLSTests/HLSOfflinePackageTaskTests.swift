import Foundation
import Testing
import os

@testable import InnoNetworkHLS

@HLSOfflinePackageDefinition(maximumMediaResourceBytes: 4096, maximumTotalDownloadBytes: 8192)
private enum OwnedOfflineFixture {}

extension HLSDownloaderTests {
    @Test("offline owner outlives cancelled observers and receipt waiters")
    func offlineOwnedObservation() async throws {
        let fixture = OfflineOwnerFixture()
        defer { fixture.close() }
        let gate = HLSOperationChannel<Void, Void>()
        let operation = try OwnedOfflineFixture.start(
            sourceURL: fixture.source,
            destinationDirectoryURL: fixture.destination, session: fixture.session,
            requestPolicy: HLSRequestPolicy { request, _ in
                try await gate.value()
                return request
            })
        defer {
            operation.cancel()
            gate.finish(.success(()))
        }
        let observations = try operation.events()
        let cancelledStream = try operation.events()
        let observer = Task { for try await _ in cancelledStream {} }
        observer.cancel()
        _ = await observer.result
        let waiter = Task { try await operation.receipt() }
        do {
            try await offlineEventually { operation.pendingReceiptCount == 1 }
            waiter.cancel()
            await #expect(throws: CancellationError.self) { try await waiter.value }
            #expect(operation.state == .running)
            gate.finish(.success(()))
            let receipt = try await operation.receipt()
            let events = try await observations.reduce(into: []) { $0.append($1) }
            #expect(events.contains { if case .progress = $0.event { true } else { false } })
            #expect(events.allSatisfy { $0.operationID == operation.id })
            #expect(events.map(\.sequence) == events.map(\.sequence).sorted())
            #expect(events.filter { if case .completed = $0.event { true } else { false } }.count == 1)
            #expect(operation.state == .completed)
            #expect(operation.failureReport == nil)
            operation.cancel()
            #expect(try await operation.receipt().directoryURL == receipt.directoryURL)
            #expect(try HLSOfflinePackageStore().open(at: receipt.directoryURL).byteCount == receipt.byteCount)
            let replay = try await operation.events().reduce(into: []) { $0.append($1) }
            #expect(replay.count == 1)
        } catch {
            waiter.cancel()
            operation.cancel()
            gate.finish(.success(()))
            _ = await waiter.result
            throw error
        }
    }

    @Test("offline explicit cancellation and owner release settle after cleanup", arguments: [false, true])
    func offlineOwnedCancellation(releaseOwner: Bool) async throws {
        let fixture = OfflineOwnerFixture()
        defer { fixture.close() }
        let entered = OSAllocatedUnfairLock(initialState: false)
        let gate = HLSOperationChannel<Void, Void>()
        var operation: HLSOfflinePackageTask? = try OwnedOfflineFixture.start(
            sourceURL: fixture.source,
            destinationDirectoryURL: fixture.destination, session: fixture.session,
            requestPolicy: HLSRequestPolicy { request, _ in
                entered.withLock { $0 = true }
                try await gate.value()
                return request
            })
        defer {
            operation?.cancel()
            gate.finish(.success(()))
        }
        weak let weakOwner = operation
        let stream = try #require(operation).events()
        try await offlineEventually { entered.withLock { $0 } }
        if releaseOwner { operation = nil } else { operation?.cancel() }
        var cancelledEvents = 0
        do {
            for try await item in stream { if case .cancelled = item.event { cancelledEvents += 1 } }
            Issue.record("Cancelled operation must terminate by throwing")
        } catch { #expect(error is CancellationError) }
        #expect(cancelledEvents == 1)
        if releaseOwner { #expect(weakOwner == nil) } else { #expect(operation?.state == .cancelled) }
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        // The first result must not precede destination-lease release.
        let replacement = try OwnedOfflineFixture.start(
            sourceURL: fixture.source,
            destinationDirectoryURL: fixture.destination, session: fixture.session)
        _ = try await replacement.receipt()
        #expect(replacement.state == .completed)
    }

    @Test("offline owned failures retain their typed terminal report")
    func offlineOwnedFailure() async throws {
        let fixture = OfflineOwnerFixture()
        defer { fixture.close() }
        let operation = try OwnedOfflineFixture.start(
            sourceURL: fixture.source,
            destinationDirectoryURL: fixture.source, session: fixture.session)
        await #expect(throws: HLSDownloadError.invalidDestination) { try await operation.receipt() }
        #expect(operation.state == .failed)
        #expect(operation.failureReport?.backend == .offlinePackage)
        #expect(operation.failureReport?.operationID == operation.id)
        var failures = 0
        do {
            for try await item in try operation.events() {
                if case .failed(.invalidDestination) = item.event { failures += 1 }
            }
        } catch { #expect(error as? HLSDownloadError == .invalidDestination) }
        #expect(failures == 1)
        #expect(HLSURLProtocol.capturedRequests().isEmpty)
    }
}

private struct OfflineOwnerFixture: Sendable {
    let source = URL(string: "https://media.example/owned.m3u8")!
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let session: URLSession
    var destination: URL { parent.appendingPathComponent("movie.hlspkg") }
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HLSURLProtocol.self]
        session = URLSession(configuration: config)
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: Data(
                    """
                    #EXTM3U
                    #EXT-X-TARGETDURATION:1
                    #EXTINF:1,
                    segment.ts
                    #EXT-X-ENDLIST
                    """.utf8), headers: [:]), for: source)
        HLSURLProtocol.register(
            .success(statusCode: 200, data: Data("MEDIA".utf8), headers: [:]),
            for: URL(string: "https://media.example/segment.ts")!)
    }
    func close() {
        session.invalidateAndCancel()
        HLSURLProtocol.reset()
        try? FileManager.default.removeItem(at: parent)
    }
}

private func offlineEventually(_ condition: @Sendable () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw OfflineTestTimeout() }
        try Task.checkCancellation()
        await Task.yield()
    }
}
private struct OfflineTestTimeout: Error {}
