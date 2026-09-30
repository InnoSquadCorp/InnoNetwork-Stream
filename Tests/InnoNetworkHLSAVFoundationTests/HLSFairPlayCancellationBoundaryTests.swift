#if canImport(AVFoundation) && !os(tvOS)
import Foundation
import Testing
import os

@testable import InnoNetworkHLSAVFoundation

private enum PersistentCancellationStage: Sendable, CaseIterable {
    case none, read, spc, license, conversion, commit
}

@Suite("Persistent FairPlay stage cancellation")
struct HLSFairPlayCancellationBoundaryTests {
    @Test(
        "no new effects start after cancellation; successful store is committed",
        arguments: PersistentCancellationStage.allCases)
    private func cancellationBoundary(stage: PersistentCancellationStage) async throws {
        let request = BoundaryRequest(stage: stage)
        let storage = BoundaryStorage(stage: stage)
        let transport = BoundaryTransport(stage: stage)
        let keyID = try HLSFairPlayKeyID("stage-boundary")
        let workflow = HLSFairPlayPersistentKeyWorkflow(transport: transport, storage: storage)
        let result = await Task {
            do {
                _ = try await workflow.fulfill(
                    request, keyID: keyID,
                    acquisition: HLSFairPlayPersistentKeyAcquisition(
                        applicationCertificate: Data([1]), contentIdentifier: Data([2])
                    )
                )
                return true
            } catch is CancellationError {
                return false
            } catch {
                Issue.record("Unexpected workflow classification: \(error)")
                return false
            }
        }.value
        let committed = stage == .none || stage == .commit
        #expect(result == committed)
        #expect(request.outcomes.withLock { $0.successes } == (committed ? 1 : 0))
        #expect(request.outcomes.withLock { $0.failures } == (committed ? 0 : 1))
        #expect(await storage.writes == (committed ? 1 : 0))
        let expectedLicenseCount = stage == .read || stage == .spc ? 0 : 1
        #expect(await transport.requests == expectedLicenseCount)
    }
}

private final class BoundaryRequest: HLSFairPlayPersistableRequestHandling, Sendable {
    let stage: PersistentCancellationStage
    let outcomes = OSAllocatedUnfairLock(initialState: (successes: 0, failures: 0))
    init(stage: PersistentCancellationStage) { self.stage = stage }

    func makeSPC(
        applicationCertificate: Data, contentIdentifier: Data,
        supportedProtocolVersions: [Int], deviceIdentifierPolicy: HLSFairPlayDeviceIdentifierPolicy
    ) async throws -> Data {
        if stage == .spc { withUnsafeCurrentTask { $0?.cancel() } }
        return Data([3])
    }

    func makePersistableKey(from licenseResponse: Data) throws -> Data {
        if stage == .conversion { withUnsafeCurrentTask { $0?.cancel() } }
        return Data([4])
    }

    func processPersistableKey(_ data: Data) { outcomes.withLock { $0.successes += 1 } }
    func processFailure(_ error: NSError) { outcomes.withLock { $0.failures += 1 } }
}

private actor BoundaryStorage: HLSFairPlayPersistentKeyStoring {
    let stage: PersistentCancellationStage
    var writes = 0
    init(stage: PersistentCancellationStage) { self.stage = stage }
    func persistableContentKey(for keyID: HLSFairPlayKeyID) -> Data? {
        if stage == .read { withUnsafeCurrentTask { $0?.cancel() } }
        return nil
    }
    func storePersistableContentKey(_ data: Data, for keyID: HLSFairPlayKeyID) {
        writes += 1
        if stage == .commit { withUnsafeCurrentTask { $0?.cancel() } }
    }
}

private actor BoundaryTransport: HLSFairPlayLicenseTransporting {
    let stage: PersistentCancellationStage
    var requests = 0
    init(stage: PersistentCancellationStage) { self.stage = stage }
    func contentKeyContext(for request: HLSFairPlayLicenseRequest) -> Data {
        requests += 1
        if stage == .license { withUnsafeCurrentTask { $0?.cancel() } }
        return Data([5])
    }
}
#endif
