import Foundation
import Testing

extension HLSDownloaderTests {
    @Test("a late stop from the previous registry cannot reduce current request counts")
    func oldRequestStopDoesNotReduceNewGenerationCount() throws {
        let source = try #require(URL(string: "https://media.example/generation"))
        let response = HLSURLProtocol.ResponseSpec.unfinished(statusCode: 200, data: Data(), headers: [:])
        let client = HLSProtocolEventRecorder()
        let old = HLSURLProtocol(request: URLRequest(url: source), cachedResponse: nil, client: client)
        let first = HLSURLProtocol(request: URLRequest(url: source), cachedResponse: nil, client: client)
        let second = HLSURLProtocol(request: URLRequest(url: source), cachedResponse: nil, client: client)
        defer {
            old.stopLoading()
            first.stopLoading()
            second.stopLoading()
            HLSURLProtocol.reset()
        }
        HLSURLProtocol.register(response, for: source)
        old.startLoading()
        HLSURLProtocol.reset()
        HLSURLProtocol.register(response, for: source)
        first.startLoading()
        old.stopLoading()
        second.startLoading()
        #expect(HLSURLProtocol.maximumActiveRequestCount() == 2)
    }

    @Test("redirect fixtures hand off without a contradictory cancellation")
    func redirectFixtureHandsOffOnce() throws {
        let source = try #require(URL(string: "https://media.example/redirect"))
        let destination = try #require(URL(string: "https://cdn.example/final"))
        defer { HLSURLProtocol.reset() }
        HLSURLProtocol.register(.redirect(statusCode: 302, location: destination), for: source)
        let client = HLSProtocolEventRecorder()
        let fixture = HLSURLProtocol(request: URLRequest(url: source), cachedResponse: nil, client: client)

        fixture.startLoading()

        #expect(client.events == ["redirect"])
        #expect(HLSURLProtocol.capturedRequests().map(\.url) == [source])
    }

    @Test("successful fixtures still deliver a response, bytes, and completion")
    func successfulFixtureCompletes() throws {
        let source = try #require(URL(string: "https://media.example/success"))
        defer { HLSURLProtocol.reset() }
        HLSURLProtocol.register(.success(statusCode: 200, data: Data([1]), headers: [:]), for: source)
        let client = HLSProtocolEventRecorder()
        let fixture = HLSURLProtocol(request: URLRequest(url: source), cachedResponse: nil, client: client)

        fixture.startLoading()

        #expect(client.events == ["response", "data", "finish"])
    }
}

private final class HLSProtocolEventRecorder: NSObject, URLProtocolClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var events: [String] { lock.withLock { recorded } }

    private func record(_ event: String) {
        lock.withLock { recorded.append(event) }
    }

    func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) {
        record("redirect")
    }

    func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) {}

    func urlProtocol(
        _ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy
    ) {
        record("response")
    }

    func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) { record("data") }
    func urlProtocolDidFinishLoading(_ protocol: URLProtocol) { record("finish") }
    func urlProtocol(_ protocol: URLProtocol, didFailWithError error: any Error) { record("failure") }
    func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge) {}
    func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge) {}
}
