import Foundation
import InnoNetwork
import Testing
import os

@testable import InnoNetworkHLS

extension HLSDownloaderTests {
    @Test("last steering waiter cancellation stops an active Core transfer")
    func steeringLastWaiterStopsTransfer() async throws {
        let url = URL(string: "https://steering.example/unfinished.json")!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HLSURLProtocol.self]
        let session = URLSession(configuration: config)
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
        }
        let stopped = OSAllocatedUnfairLock(initialState: false)
        HLSURLProtocol.setStopLoadingHandler { if $0 == url { stopped.withLock { $0 = true } } }
        HLSURLProtocol.register(.unfinished(statusCode: 200, data: Data("{".utf8), headers: [:]), for: url)
        let resolver = HLSContentSteeringResolver(
            client: HLSHTTPClient(
                session: session,
                requestContext: NetworkRequestContext(), requestAdapter: { $0 }),
            settings: HLSContentSteeringPack().resolvedSettings)
        let playlist = try steeringLifecyclePlaylist(serverURL: url)
        let first = Task { try await resolver.catalog(for: playlist) }
        let second = Task { try await resolver.catalog(for: playlist) }
        do {
            try await steeringEventually {
                await resolver.pendingManifestWaiterCount == 2 && !HLSURLProtocol.capturedRequests().isEmpty
            }
            first.cancel()
            await #expect(throws: CancellationError.self) { try await first.value }
            #expect(!stopped.withLock { $0 })
            second.cancel()
            await #expect(throws: CancellationError.self) { try await second.value }
            try await steeringEventually { stopped.withLock { $0 } }
            try await steeringEventually { await resolver.activeManifestLoadCount == 0 }
            #expect(HLSURLProtocol.capturedRequests().count == 1)
        } catch {
            first.cancel()
            second.cancel()
            _ = await first.result
            _ = await second.result
            throw error
        }
    }

    @Test(
        "steering Retry-After accepts HTTP wait syntax",
        arguments: [
            "0", "60", " 60 ", "Thu, 01 Jan 1970 00:00:10 GMT", "Wed, 31 Dec 1969 23:59:59 GMT",
            "+1", "-1", "1.5", "bogus", "999999999999999999999999999999999999",
        ])
    func steeringRetryAfterSyntax(header: String) throws {
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://steering.example/retry")!,
                statusCode: 429, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": header]))
        let expected: Duration?
        switch header {
        case "0", "Wed, 31 Dec 1969 23:59:59 GMT": expected = .zero
        case "60", " 60 ": expected = .seconds(60)
        case "Thu, 01 Jan 1970 00:00:10 GMT": expected = .seconds(10)
        default: expected = nil
        }
        #expect(HLSContentSteeringResolver.retryDelay(from: response, now: Date(timeIntervalSince1970: 0)) == expected)
    }

    @Test("shared steering waiters cancel independently", arguments: [200, 429, 410, 503])
    func steeringSharedWaiters(status: Int) async throws {
        let fixture = try SteeringFlightFixture(status: status)
        defer { fixture.close() }
        let first = Task { try await fixture.resolver.catalog(for: fixture.playlist) }
        let second = Task { try await fixture.resolver.catalog(for: fixture.playlist) }
        defer {
            first.cancel()
            second.cancel()
            fixture.gate.finish(.success(()))
        }
        try await steeringEventually { await fixture.resolver.pendingManifestWaiterCount == 2 }
        #expect(await fixture.resolver.activeManifestLoadCount == 1)
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await fixture.resolver.pendingManifestWaiterCount == 1)
        fixture.gate.finish(.success(()))
        #expect(try await second.value.pathways.count == 1)
        _ = try await fixture.resolver.catalog(for: fixture.playlist)
        #expect(HLSURLProtocol.capturedRequests().count == 1)
        #expect(await fixture.resolver.activeManifestLoadCount == 0)
    }

    @Test("steering bounds waiters and producers", arguments: [false, true])
    func steeringFlightCapacity(distinctURLs: Bool) async throws {
        let fixture = try SteeringFlightFixture()
        defer { fixture.close() }
        var tasks: [Task<HLSPathwayCatalog, Error>] = []
        defer {
            for task in tasks { task.cancel() }
            fixture.gate.finish(.success(()))
        }
        for index in 0..<64 {
            let playlist =
                try distinctURLs
                ? steeringLifecyclePlaylist(serverURL: URL(string: "https://steering.example/\(index).json")!)
                : fixture.playlist
            tasks.append(Task { try await fixture.resolver.catalog(for: playlist) })
        }
        do {
            try await steeringEventually { await fixture.resolver.pendingManifestWaiterCount == 64 }
            #expect(await fixture.resolver.activeManifestLoadCount == (distinctURLs ? 64 : 1))
            let fallback = try await fixture.resolver.catalog(for: fixture.playlist)
            #expect(fallback.pathways.count == 1)
            #expect(HLSURLProtocol.capturedRequests().isEmpty)
            for task in tasks { task.cancel() }
            for task in tasks { await #expect(throws: CancellationError.self) { try await task.value } }
            try await steeringEventually { await fixture.resolver.activeManifestLoadCount == 0 }
            #expect(await fixture.resolver.pendingManifestWaiterCount == 0)
            fixture.gate.finish(.success(()))
            _ = try await fixture.resolver.catalog(for: fixture.playlist)
            #expect(HLSURLProtocol.capturedRequests().count == 1)
        } catch {
            for task in tasks { task.cancel() }
            fixture.gate.finish(.success(()))
            for task in tasks { _ = await task.result }
            throw error
        }
    }

    @Test("cancelled steering producer cannot finish its replacement")
    func steeringCancelledGeneration() async throws {
        let oldGate = SteeringUncooperativeGate()
        let entered = OSAllocatedUnfairLock(initialState: 0)
        let fixture = try SteeringFlightFixture(adapter: { request in
            let ordinal = entered.withLock {
                $0 += 1
                return $0
            }
            if ordinal == 1 { await oldGate.wait() }
            return request
        })
        defer { fixture.close() }
        let old = Task { try await fixture.resolver.catalog(for: fixture.playlist) }
        do {
            try await steeringEventually { entered.withLock { $0 } == 1 }
            old.cancel()
            await #expect(throws: CancellationError.self) { try await old.value }
            #expect(await fixture.resolver.activeManifestLoadCount == 1)
            _ = try await fixture.resolver.catalog(for: fixture.playlist)
            await oldGate.release()
            try await steeringEventually { await fixture.resolver.activeManifestLoadCount == 0 }
            _ = try await fixture.resolver.catalog(for: fixture.playlist)
            #expect(HLSURLProtocol.capturedRequests().count == 1)
            #expect(await fixture.resolver.pendingManifestWaiterCount == 0)
        } catch {
            old.cancel()
            await oldGate.release()
            _ = await old.result
            throw error
        }
    }

    @Test("steering wait periods start after receipt", arguments: [200, 429], [0, 2])
    func steeringReceiptTime(status: Int, elapsed: Int) async throws {
        let instant = OSAllocatedUnfairLock(initialState: ContinuousClock.now)
        let url = try #require(URL(string: "https://steering.example/receipt.json"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HLSURLProtocol.self]
        let session = URLSession(configuration: config)
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
        }
        HLSURLProtocol.register(
            .success(
                statusCode: status,
                data: Data("{\"VERSION\":1,\"TTL\":1,\"PATHWAY-PRIORITY\":[\"A\"]}".utf8),
                headers: ["Retry-After": "1"]), for: url)
        let resolver = HLSContentSteeringResolver(
            client: HLSHTTPClient(
                session: session, requestContext: NetworkRequestContext(),
                requestAdapter: { request in
                    instant.withLock { $0 = $0.advanced(by: .seconds(elapsed)) }
                    return request
                }), settings: HLSContentSteeringPack().resolvedSettings, now: { instant.withLock { $0 } })
        let playlist = try steeringLifecyclePlaylist(serverURL: url)
        _ = try await resolver.catalog(for: playlist)
        _ = try await resolver.catalog(for: playlist)
        #expect(HLSURLProtocol.capturedRequests().count == 1)
        instant.withLock { $0 = $0.advanced(by: .seconds(1)) }
        _ = try await resolver.catalog(for: playlist)
        #expect(HLSURLProtocol.capturedRequests().count == 2)
    }
}

private struct SteeringFlightFixture: Sendable {
    let session: URLSession
    let gate = HLSOperationChannel<Void, Void>()
    let resolver: HLSContentSteeringResolver
    let playlist: HLSPlaylist

    init(status: Int = 200, adapter: (@Sendable (URLRequest) async throws -> URLRequest)? = nil) throws {
        let url = URL(string: "https://steering.example/shared.json")!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HLSURLProtocol.self]
        session = URLSession(configuration: config)
        HLSURLProtocol.register(
            .success(
                statusCode: status,
                data: Data("{\"VERSION\":1,\"TTL\":60,\"PATHWAY-PRIORITY\":[\"A\"]}".utf8),
                headers: ["Retry-After": "60"]), for: url)
        let gate = self.gate
        resolver = HLSContentSteeringResolver(
            client: HLSHTTPClient(
                session: session,
                requestContext: NetworkRequestContext(),
                requestAdapter: adapter ?? { request in
                    try await gate.value()
                    return request
                }), settings: HLSContentSteeringPack().resolvedSettings)
        playlist = try steeringLifecyclePlaylist(serverURL: url)
    }

    func close() {
        gate.finish(.success(()))
        session.invalidateAndCancel()
        HLSURLProtocol.reset()
    }
}

private actor SteeringUncooperativeGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private func steeringEventually(_ condition: @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw SteeringTestTimeout() }
        try Task.checkCancellation()
        await Task.yield()
    }
}

private struct SteeringTestTimeout: Error {}

private func steeringLifecyclePlaylist(serverURL: URL) throws -> HLSPlaylist {
    try HLSPlaylistParser().parse(
        """
        #EXTM3U
        #EXT-X-VERSION:12
        #EXT-X-CONTENT-STEERING:SERVER-URI="\(serverURL.absoluteString)",PATHWAY-ID="A"
        #EXT-X-STREAM-INF:BANDWIDTH=1000,PATHWAY-ID="A",STABLE-VARIANT-ID="video"
        a.m3u8
        """, relativeTo: URL(string: "https://media.example/master.m3u8")!
    ).legacyPlaylist
}
