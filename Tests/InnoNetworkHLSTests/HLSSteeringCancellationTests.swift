import Foundation
import Testing

@testable import InnoNetworkHLS

extension HLSDownloaderTests {
    @Test("shared activation preserves a survivor and cancels when all waiters leave", arguments: [false, true])
    func sharedSteeringCancellation(cancelAll: Bool) async throws {
        let source = try #require(URL(string: "https://media.example/master.m3u8"))
        let fallback = try #require(URL(string: "https://media.example/b.m3u8"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HLSURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
        }
        let contents = "#EXTM3U\n#EXTINF:1,\nsegment.ts\n#EXT-X-ENDLIST\n"
        HLSURLProtocol.register(.success(statusCode: 200, data: Data(contents.utf8), headers: [:]), for: fallback)
        let resolver = PlaylistResolver()
        let master = try resolver.resolve(
            "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000,STABLE-VARIANT-ID=\"main\",PATHWAY-ID=\"A\"\na.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=1000,STABLE-VARIANT-ID=\"main\",PATHWAY-ID=\"B\"\nb.m3u8\n",
            relativeTo: source
        )
        let primary = try #require(master.variants.first)
        let secondary = try #require(master.variants.last)
        let playlist = try resolver.resolve(contents, relativeTo: primary.url)
        let media = try #require(playlist.media)
        let gate = HLSAdapterAdmissionGate()
        let client = HLSHTTPClient(
            session: session, requestContext: .init(),
            requestAdapter: { request in
                if request.url == fallback { try await gate.hold() }
                return request
            }
        )
        let recovery = HLSContentSteeringRecovery(
            client: client, clock: HLSSystemClock(), retryPolicy: nil,
            maximumTransferBytes: 1_024, primaryVariant: primary,
            primaryContainer: try #require(playlist.mediaContainer),
            primaryTransfers: HLSResourcePlan(resources: media.resources, maximumTransferBytes: 1_024).transfers,
            candidates: [
                HLSMediaPlaylistCandidate(
                    pathwayID: "B", variant: secondary, renditions: [], multivariantVariables: [:]
                )
            ],
            contentSteeringSession: HLSContentSteeringSession(settings: HLSContentSteeringPack().resolvedSettings)
        )
        let failure = HLSPathwayFailure(pathwayID: "A", phase: .mediaResource, errorCode: .transferFailed)
        let first = Task { try await recovery.resource(at: 0, after: failure, excludingPathwayIDs: []) }
        await gate.waitForEntry()
        let second = Task { try await recovery.resource(at: 0, after: failure, excludingPathwayIDs: []) }
        for _ in 0..<10_000 {
            if await recovery.pendingActivationWaiterCount == 2 { break }
            await Task.yield()
        }
        #expect(await recovery.pendingActivationWaiterCount == 2)
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await recovery.pendingActivationWaiterCount == 1)
        if cancelAll {
            second.cancel()
            await #expect(throws: CancellationError.self) { try await second.value }
            for _ in 0..<10_000 {
                if await gate.wasCancelled { break }
                await Task.yield()
            }
            #expect(await gate.wasCancelled)
            #expect(await recovery.pendingActivationWaiterCount == 0)
            #expect(HLSURLProtocol.capturedRequests().isEmpty)
        } else {
            #expect(await !gate.wasCancelled)
            await gate.open()
            #expect(try await second.value?.pathwayID == "B")
            #expect(HLSURLProtocol.capturedRequests().compactMap(\.url) == [fallback])
        }
        await gate.open()
    }
}

actor HLSAdapterAdmissionGate {
    private var held: CheckedContinuation<Void, Error>?
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var entered = false
    private(set) var wasCancelled = false

    func hold() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                held = continuation
                entered = true
                for waiter in entryWaiters { waiter.resume() }
                entryWaiters.removeAll()
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func open() {
        let continuation = held
        held = nil
        continuation?.resume()
    }
    private func cancel() {
        wasCancelled = true
        let continuation = held
        held = nil
        continuation?.resume(throwing: CancellationError())
    }
}
