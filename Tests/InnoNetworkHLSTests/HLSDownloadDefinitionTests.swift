import Foundation
import Testing

@testable import InnoNetworkHLS

@HLSDownloadDefinition(
    maximumMediaResourceBytes: 4_096,
    maximumTotalDownloadBytes: 16_384,
    maximumConcurrentResourceTransfers: 2
)
private enum FixtureDownload {}

@Suite("Macro-first download configuration")
struct HLSDownloadDefinitionTests {
    @Test("generated workflow delegates to validated immutable settings")
    func generatedConfiguration() throws {
        let settings = try FixtureDownload.configuration()
        #expect(settings.maximumMediaResourceBytes == 4_096)
        #expect(settings.maximumTotalDownloadBytes == 16_384)
        #expect(settings.maximumConcurrentResourceTransfers == 2)
        #expect(settings.resumePolicy == .automatic)
        _ = try FixtureDownload.makeDownloader()
    }

    @Test("dynamic settings fail rather than normalize")
    func rejectsInvalidSettings() throws {
        #expect(throws: HLSConfigurationError.invalidResourceByteLimit) {
            try HLSDownloadConfiguration.validated(maximumMediaResourceBytes: 0)
        }
        #expect(throws: HLSConfigurationError.invalidOutputByteLimit) {
            try HLSDownloadConfiguration.validated(maximumTotalDownloadBytes: 0)
        }
        #expect(throws: HLSConfigurationError.invalidResourceByteLimit) {
            try HLSDownloadConfiguration.validated(maximumMediaResourceBytes: 2, maximumTotalDownloadBytes: 1)
        }
        #expect(throws: HLSConfigurationError.invalidTransferConcurrency) {
            try HLSDownloadConfiguration.validated(maximumConcurrentResourceTransfers: 9)
        }
        #expect(throws: HLSConfigurationError.invalidDiskCapacity) {
            try HLSDownloadConfiguration.validated(diskCapacityPolicy: .required(minimumAvailableCapacity: -1))
        }
        let configuration = try HLSDownloadConfiguration.validated(
            maximumMediaResourceBytes: 1, maximumTotalDownloadBytes: 1,
            maximumConcurrentResourceTransfers: 8, diskCapacityPolicy: .bestEffort(minimumAvailableCapacity: 0)
        )
        #expect(configuration.maximumMediaResourceBytes == 1)
        #expect(configuration.maximumTotalDownloadBytes == 1)
        #expect(configuration.maximumConcurrentResourceTransfers == 8)
    }
}

extension HLSDownloaderTests {
    @Test("releasing the last handle cancels work even with an event subscription")
    func macroOperationLastOwnerRelease() async throws {
        let source = try #require(URL(string: "https://media.example/released.m3u8"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HLSURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        let gate = HLSAdapterAdmissionGate()
        var operation: HLSDownloadTask? = try FixtureDownload.start(
            sourceURL: source, destinationURL: directory.appendingPathComponent("movie.ts"),
            session: session,
            requestPolicy: HLSRequestPolicy { request, _ in
                try await gate.hold()
                return request
            }
        )
        await gate.waitForEntry()
        weak var owner = operation
        let events = try #require(operation).events()
        operation = nil
        #expect(owner == nil)
        var cancelled = false
        for await observation in events {
            if case .cancelled = observation.event { cancelled = true }
        }
        #expect(cancelled)
        #expect(await gate.wasCancelled)
        #expect(HLSURLProtocol.capturedRequests().isEmpty)
    }

    @Test("cancelled observers do not own the macro-started operation")
    func macroOperationObserverCancellation() async throws {
        let source = try #require(URL(string: "https://media.example/observed.m3u8"))
        let resource = try #require(URL(string: "https://media.example/segment.ts"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HLSURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: Data("#EXTM3U\n#EXTINF:1,\nsegment.ts\n#EXT-X-ENDLIST\n".utf8), headers: [:]
            ), for: source)
        HLSURLProtocol.register(.success(statusCode: 200, data: Data("media".utf8), headers: [:]), for: resource)
        let gate = HLSAdapterAdmissionGate()
        let operation = try FixtureDownload.start(
            sourceURL: source, destinationURL: directory.appendingPathComponent("movie.ts"),
            session: session,
            requestPolicy: HLSRequestPolicy { request, _ in
                if request.url == source { try await gate.hold() }
                return request
            }
        )
        await gate.waitForEntry()
        let events = try operation.events()
        let observer = Task { for await _ in events {} }
        observer.cancel()
        await observer.value
        let waiter = Task { try await operation.receipt() }
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(operation.state == .running)
        #expect(await !gate.wasCancelled)
        await gate.open()
        _ = try await operation.receipt()
        #expect(operation.state == .completed)
        #expect(HLSURLProtocol.capturedRequests().compactMap(\.url) == [source, resource])
    }

    @Test("subscriptions stay bounded and explicit operation cancellation stops transport")
    func macroOperationObserverCapacity() async throws {
        let source = try #require(URL(string: "https://media.example/bounded.m3u8"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HLSURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        let gate = HLSAdapterAdmissionGate()
        let operation = try FixtureDownload.start(
            sourceURL: source, destinationURL: directory.appendingPathComponent("movie.ts"),
            session: session,
            requestPolicy: HLSRequestPolicy { request, _ in
                try await gate.hold()
                return request
            }
        )
        await gate.waitForEntry()
        var subscribers: [AsyncStream<HLSDownloadObservation>] = []
        for _ in 0..<64 { subscribers.append(try operation.events()) }
        #expect(throws: HLSOperationObservationError.capacityExceeded) { try operation.events() }
        #expect(subscribers.count == 64)
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.receipt() }
        #expect(operation.state == .cancelled)
        #expect(await gate.wasCancelled)
        #expect(HLSURLProtocol.capturedRequests().isEmpty)
    }

    @Test("multiple slow subscribers receive bounded ordered terminal delivery")
    func macroOperationSlowObservers() async throws {
        let source = try #require(URL(string: "https://media.example/progress.m3u8"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HLSURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        let lines = (0..<40).map { "#EXTINF:1,\nsegment-\($0).ts" }.joined(separator: "\n")
        HLSURLProtocol.register(
            .success(statusCode: 200, data: Data("#EXTM3U\n\(lines)\n#EXT-X-ENDLIST\n".utf8), headers: [:]), for: source
        )
        for index in 0..<40 {
            let resource = try #require(URL(string: "https://media.example/segment-\(index).ts"))
            HLSURLProtocol.register(.success(statusCode: 200, data: Data("media".utf8), headers: [:]), for: resource)
        }
        let gate = HLSAdapterAdmissionGate()
        let operation = try FixtureDownload.start(
            sourceURL: source, destinationURL: directory.appendingPathComponent("movie.ts"), session: session,
            requestPolicy: HLSRequestPolicy { request, _ in
                if request.url == source { try await gate.hold() }
                return request
            }
        )
        await gate.waitForEntry()
        let streams = [try operation.events(), try operation.events()]
        await gate.open()
        _ = try await operation.receipt()
        for stream in streams {
            var observed: [HLSDownloadObservation] = []
            for await event in stream { observed.append(event) }
            #expect(observed.count <= 16)
            #expect(observed.count > 1)
            #expect(observed.allSatisfy { $0.operationID == operation.id })
            #expect(zip(observed, observed.dropFirst()).allSatisfy { $0.sequence < $1.sequence })
            #expect((observed.last?.droppedEventCount ?? 0) > 0)
            if case .completed = observed.last?.event {} else { Issue.record("Missing bounded terminal delivery") }
        }
    }

    @Test("macro-owned operation succeeds with no event subscribers and replays its terminal event")
    func macroOperationWithoutSubscribers() async throws {
        let source = try #require(URL(string: "https://media.example/macro.m3u8"))
        let resource = try #require(URL(string: "https://media.example/segment.ts"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HLSURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: Data("#EXTM3U\n#EXTINF:1,\nsegment.ts\n#EXT-X-ENDLIST\n".utf8), headers: [:]
            ), for: source)
        HLSURLProtocol.register(.success(statusCode: 200, data: Data("media".utf8), headers: [:]), for: resource)
        let destination = directory.appendingPathComponent("movie.ts")
        let operation = try FixtureDownload.start(
            sourceURL: source, destinationURL: destination, session: session
        )
        let receipt = try await operation.receipt()
        #expect(receipt.destinationURL == destination)
        #expect(operation.state == .completed)
        #expect(try Data(contentsOf: destination) == Data("media".utf8))
        operation.cancel()
        #expect(try await operation.receipt().destinationURL == destination)
        var events: [HLSDownloadObservation] = []
        for await event in try operation.events() { events.append(event) }
        #expect(events.count == 1)
        #expect(events.first?.operationID == operation.id)
        if case .completed(let url) = events.first?.event {
            #expect(url == destination)
        } else {
            Issue.record("Terminal subscription must replay completed output")
        }
    }
}
