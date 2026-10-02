import Foundation
import InnoNetwork
import Testing
import os

@testable import InnoNetworkHLS

extension HLSDownloaderTests {
    @Test("steering wait periods start after receipt", arguments: [200, 429], [0, 2])
    func steeringReceiptTime(status: Int, elapsed: Int) async throws {
        let instant = OSAllocatedUnfairLock(initialState: ContinuousClock.now)
        let url = try #require(URL(string: "https://steering.example/receipt.json"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HLSURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); HLSURLProtocol.reset() }
        HLSURLProtocol.register(
            .success(statusCode: status,
                data: Data("{\"VERSION\":1,\"TTL\":1,\"PATHWAY-PRIORITY\":[\"A\"]}".utf8),
                headers: ["Retry-After": "1"]), for: url)
        let resolver = HLSContentSteeringResolver(
            client: HLSHTTPClient(session: session, requestContext: NetworkRequestContext(), requestAdapter: { request in
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

private func steeringLifecyclePlaylist(serverURL: URL) throws -> HLSPlaylist {
    try HLSPlaylistParser().parse("""
        #EXTM3U
        #EXT-X-VERSION:12
        #EXT-X-CONTENT-STEERING:SERVER-URI="\(serverURL.absoluteString)",PATHWAY-ID="A"
        #EXT-X-STREAM-INF:BANDWIDTH=1000,PATHWAY-ID="A",STABLE-VARIANT-ID="video"
        a.m3u8
        """, relativeTo: URL(string: "https://media.example/master.m3u8")!).legacyPlaylist
}
