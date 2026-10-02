import Foundation
import InnoNetwork
import Testing

@testable import InnoNetworkHLS

@HLSDownloadDefinition(maximumMediaResourceBytes: 4096, maximumTotalDownloadBytes: 8192)
private enum ProductionBoundaryDownload {}

extension HLSDownloaderTests {
    @Test("request policy preserves bodyless GET semantics", arguments: ["headers", "method", "body", "stream"])
    func productionRequestSemantics(mutation: String) async throws {
        let url = try #require(URL(string: "https://media.example/production.m3u8"))
        let session = productionBoundarySession()
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
        }
        HLSURLProtocol.register(.success(statusCode: 200, data: productionBoundaryPlaylist, headers: [:]), for: url)
        let policy = HLSRequestPolicy { request, _ in
            var request = request
            switch mutation {
            case "method": request.httpMethod = "POST"
            case "body": request.httpBody = Data("payload".utf8)
            case "stream": request.httpBodyStream = InputStream(data: Data("payload".utf8))
            default: request.setValue("valid", forHTTPHeaderField: "X-Test")
            }
            return request
        }
        if mutation == "headers" {
            _ = try await ProductionBoundaryDownload.prepare(sourceURL: url, session: session, requestPolicy: policy)
            #expect(HLSURLProtocol.capturedRequests().first?.value(forHTTPHeaderField: "X-Test") == "valid")
        } else {
            await #expect(throws: NetworkError.self) {
                _ = try await ProductionBoundaryDownload.prepare(
                    sourceURL: url, session: session, requestPolicy: policy)
            }
            #expect(HLSURLProtocol.capturedRequests().isEmpty)
        }
    }

    @Test("cancellation is checked on both sides of request adaptation", arguments: [false, true])
    func productionPreCancelledAdapter(beforeAdapter: Bool) async throws {
        let url = try #require(URL(string: "https://media.example/cancelled.m3u8"))
        let session = productionBoundarySession()
        let counter = ProductionBoundaryCounter()
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
        }
        let worker = Task {
            if beforeAdapter { withUnsafeCurrentTask { $0?.cancel() } }
            do {
                _ = try await ProductionBoundaryDownload.prepare(
                    sourceURL: url, session: session,
                    requestPolicy: HLSRequestPolicy { request, _ in
                        await counter.increment()
                        withUnsafeCurrentTask { $0?.cancel() }
                        return request
                    })
                return false
            } catch { return error is CancellationError }
        }
        #expect(await worker.value)
        #expect(await counter.value == (beforeAdapter ? 0 : 1))
        #expect(HLSURLProtocol.capturedRequests().isEmpty)
    }

    @Test("empty resources cannot commit a partial presentation", arguments: [false, true], [false, true])
    func productionEmptyResource(offline: Bool, empty: Bool) async throws {
        let url = try #require(URL(string: "https://media.example/empty-resource.m3u8"))
        let first = try #require(URL(string: "https://media.example/first.ts"))
        let second = try #require(URL(string: "https://media.example/second.ts"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(offline ? "test.hlspkg" : "test.ts")
        let session = productionBoundarySession()
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        HLSURLProtocol.register(.success(statusCode: 200, data: productionBoundaryPlaylist, headers: [:]), for: url)
        HLSURLProtocol.register(
            .success(statusCode: 200, data: empty ? Data() : Data("ONE".utf8), headers: [:]), for: first)
        HLSURLProtocol.register(.success(statusCode: 200, data: Data("TWO".utf8), headers: [:]), for: second)
        var failed = false
        do {
            if offline {
                _ = try await HLSOfflinePackageDownloader(session: session).downloadPackage(
                    sourceURL: url, destinationDirectoryURL: destination)
            } else {
                let task = try ProductionBoundaryDownload.start(
                    sourceURL: url, destinationURL: destination, session: session)
                _ = try await task.receipt()
            }
        } catch {
            failed = true
            #expect((error as? HLSDownloadError)?.code == .emptyOutput)
        }
        #expect(failed == empty)
        #expect(FileManager.default.fileExists(atPath: destination.path) == !empty)
    }

    private func productionBoundarySession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HLSURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private var productionBoundaryPlaylist: Data {
        Data("#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nfirst.ts\n#EXTINF:1,\nsecond.ts\n#EXT-X-ENDLIST\n".utf8)
    }
}

private actor ProductionBoundaryCounter {
    var value = 0
    func increment() { value += 1 }
}
