import Foundation
import Testing

@testable import InnoNetworkHLS

@HLSOfflinePackageDefinition(
    maximumMediaResourceBytes: 4096, maximumTotalDownloadBytes: 8192, maximumConcurrentResourceTransfers: 2)
private enum FixtureOfflinePackage {}

private enum ManualOfflinePackage: HLSOfflinePackageDefining {
    static func configuration() throws -> HLSOfflinePackageConfiguration {
        try .validated(
            maximumMediaResourceBytes: 4096, maximumTotalDownloadBytes: 8192, maximumConcurrentResourceTransfers: 2)
    }
}

@Suite("Macro-first offline package")
struct HLSOfflinePackageDefinitionTests {
    @Test("macro and dynamic settings share validated effective limits")
    func settingsParity() throws {
        let macro = try FixtureOfflinePackage.configuration()
        let manual = try ManualOfflinePackage.configuration()
        #expect(macro.maximumMediaResourceBytes == manual.maximumMediaResourceBytes)
        #expect(macro.maximumTotalDownloadBytes == manual.maximumTotalDownloadBytes)
        #expect(macro.maximumConcurrentResourceTransfers == manual.maximumConcurrentResourceTransfers)
        #expect(macro.resumePolicy == .automatic)
        #expect(macro.diskCapacityPolicy == manual.diskCapacityPolicy)
        _ = try FixtureOfflinePackage.makeDownloader()
        _ = try ManualOfflinePackage.makeDownloader()
    }

    @Test("offline dynamic limits reject invalid values rather than clamp")
    func invalidSettings() throws {
        #expect(throws: HLSConfigurationError.invalidResourceByteLimit) {
            try HLSOfflinePackageConfiguration.validated(maximumMediaResourceBytes: 0)
        }
        #expect(throws: HLSConfigurationError.invalidOutputByteLimit) {
            try HLSOfflinePackageConfiguration.validated(maximumTotalDownloadBytes: 0)
        }
        #expect(throws: HLSConfigurationError.invalidResourceByteLimit) {
            try HLSOfflinePackageConfiguration.validated(maximumMediaResourceBytes: 2, maximumTotalDownloadBytes: 1)
        }
        #expect(throws: HLSConfigurationError.invalidTransferConcurrency) {
            try HLSOfflinePackageConfiguration.validated(maximumConcurrentResourceTransfers: 9)
        }
        #expect(throws: HLSConfigurationError.invalidDiskCapacity) {
            try HLSOfflinePackageConfiguration.validated(diskCapacityPolicy: .required(minimumAvailableCapacity: -1))
        }
        let settings = try HLSOfflinePackageConfiguration.validated(
            maximumMediaResourceBytes: 1, maximumTotalDownloadBytes: 1,
            maximumConcurrentResourceTransfers: 8, diskCapacityPolicy: .disabled)
        #expect(settings.maximumConcurrentResourceTransfers == 8)
    }

    @Test("macro offline cancellation belongs to the calling task")
    func callerCancellation() async throws {
        let source = try #require(URL(string: "https://media.example/cancel-offline.m3u8"))
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let (entries, entry) = AsyncStream<Void>.makeStream()
        defer { entry.finish() }
        let worker = Task {
            try await FixtureOfflinePackage.downloadPackage(
                sourceURL: source, destinationDirectoryURL: parent.appendingPathComponent("media.hlspkg"),
                requestPolicy: HLSRequestPolicy { request, _ in
                    entry.yield(())
                    try await Task.sleep(for: .seconds(60))
                    return request
                })
        }
        defer { worker.cancel() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in entries { return } }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw CancellationError()
            }
            defer { group.cancelAll() }
            try await group.next()
        }
        worker.cancel()
        await #expect(throws: CancellationError.self) { try await worker.value }
        #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("media.hlspkg").path))
    }
}
