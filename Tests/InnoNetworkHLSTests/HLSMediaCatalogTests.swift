import Foundation
import Testing

@testable import InnoNetworkHLS

@HLSCatalogDefinition(maximumEntries: 3, maximumSnapshotBytes: 2048)
private enum TestCatalog {}

@Suite("Optional media metadata catalog")
struct HLSMediaCatalogTests {
    private let id = HLSMediaID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    private func record(_ ownership: HLSMediaOwnership = .offlinePackage) throws -> HLSMediaRecord {
        try HLSMediaRecord(id: id, ownership: ownership, reference: "app-asset-1")
    }

    @Test(arguments: [HLSMediaOwnership.applicationFile, .offlinePackage, .nativeBackgroundAsset])
    func roundTripAndReconcile(_ ownership: HLSMediaOwnership) async throws {
        let store = CatalogStore()
        let catalog = try TestCatalog.makeCatalog(persistence: store)
        try await catalog.upsert(record(ownership))
        let restored = try TestCatalog.makeCatalog(persistence: store)
        try await restored.restore()
        #expect(await restored.snapshot() == [try record(ownership)])
        try await restored.reconcile { _ in .missing }
        #expect(await restored.snapshot().count == 1)
        #expect(await restored.snapshot().first?.availability == .missing)
        #expect(await restored.snapshot().first?.ownership == ownership)
        try await restored.remove(id)
        #expect(await restored.snapshot().isEmpty)
    }

    @Test("known v0 migrates without automatically rewriting storage")
    func migration() async throws {
        let legacy = Data(
            "{\"version\":0,\"entries\":[{\"id\":{\"rawValue\":\"00000000-0000-0000-0000-000000000001\"},\"ownership\":\"offlinePackage\",\"reference\":\"app-asset-1\"}]}"
                .utf8)
        let store = CatalogStore(data: legacy)
        let catalog = try TestCatalog.makeCatalog(persistence: store)
        try await catalog.restore()
        #expect(await catalog.snapshot().first?.availability == .unknown)
        #expect(await store.data == legacy)
        try await catalog.upsert(record())
        let encoded = try #require(await store.data)
        #expect(String(decoding: encoded, as: UTF8.self).contains("\"version\":1"))
    }

    @Test("corruption, unknown version and oversized snapshots preserve current state")
    func invalidSnapshots() async throws {
        let store = CatalogStore()
        let catalog = try TestCatalog.makeCatalog(persistence: store)
        try await catalog.upsert(record())
        for data in [Data("bad".utf8), Data("{\"version\":99,\"entries\":[]}".utf8), Data(repeating: 65, count: 2049)] {
            await store.replace(data)
            await #expect(throws: (any Error).self) { try await catalog.restore() }
            #expect(await catalog.snapshot().count == 1)
        }
        #expect(throws: HLSMediaCatalogError.invalidReference) {
            try HLSMediaRecord(id: id, ownership: .applicationFile, reference: "https://host/path?token=secret")
        }
        #expect(throws: HLSMediaCatalogError.invalidReference) {
            try HLSMediaRecord(id: id, ownership: .applicationFile, reference: String(repeating: "a", count: 129))
        }
        #expect(throws: HLSMediaCatalogError.invalidLimits) {
            try HLSMediaCatalogConfiguration.validated(maximumEntries: 513)
        }
    }

    @Test("capacity and failed commit never publish partial state")
    func capacityAndFailure() async throws {
        let store = CatalogStore()
        let catalog = HLSMediaCatalog(configuration: try .validated(maximumEntries: 1), persistence: store)
        try await catalog.upsert(record())
        let second = try HLSMediaRecord(id: HLSMediaID(), ownership: .nativeBackgroundAsset, reference: "second")
        await #expect(throws: HLSMediaCatalogError.capacityExceeded) { try await catalog.upsert(second) }
        let before = await store.data
        await store.failNextCommit()
        await #expect(throws: CatalogTestFailure.self) { try await catalog.remove(id) }
        #expect(await catalog.snapshot().count == 1)
        #expect(await store.data == before)
        #expect(await store.discards == 1)
    }

    @Test("cancelled staging discards and reentrant mutation is rejected")
    func cancelledStage() async throws {
        let gate = CatalogGate()
        let store = CatalogStore(stageGate: gate)
        let catalog = try TestCatalog.makeCatalog(persistence: store)
        let record = try record()
        let operation = Task { try await catalog.upsert(record) }
        await gate.entered()
        await #expect(throws: HLSMediaCatalogError.transactionInProgress) { try await catalog.remove(id) }
        #expect(await catalog.snapshot().isEmpty)
        operation.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await catalog.snapshot().isEmpty)
        #expect(await store.data == nil)
        #expect(await store.discards == 1)
    }

    @Test("successful atomic commit wins late cancellation")
    func committedResult() async throws {
        let gate = CatalogGate()
        let store = CatalogStore(commitGate: gate)
        let catalog = try TestCatalog.makeCatalog(persistence: store)
        let record = try record()
        let operation = Task { try await catalog.upsert(record) }
        await gate.entered()
        operation.cancel()
        await gate.release()
        try await operation.value
        #expect(await catalog.snapshot() == [record])
        #expect(await store.data != nil)
        #expect(await store.discards == 0)
    }
}

private struct CatalogTestFailure: Error {}
private actor CatalogStore: HLSMediaCatalogPersisting {
    var data: Data?
    var discards = 0
    private var fails = false
    let stageGate: CatalogGate?
    let commitGate: CatalogGate?
    init(data: Data? = nil, stageGate: CatalogGate? = nil, commitGate: CatalogGate? = nil) {
        self.data = data
        self.stageGate = stageGate
        self.commitGate = commitGate
    }
    func read(maximumBytes: Int) -> Data? { data }
    func stage(_ data: Data) async -> any HLSMediaCatalogCommit {
        if let stageGate { await stageGate.wait() }
        return CatalogCommit(store: self, data: data)
    }
    func install(_ data: Data) async throws {
        if let commitGate { await commitGate.wait() }
        if fails {
            fails = false
            throw CatalogTestFailure()
        }
        self.data = data
    }
    func discarded() { discards += 1 }
    func replace(_ data: Data) { self.data = data }
    func failNextCommit() { fails = true }
}
private struct CatalogCommit: HLSMediaCatalogCommit {
    let store: CatalogStore
    let data: Data
    func commit() async throws { try await store.install(data) }
    func discard() async { await store.discarded() }
}
private actor CatalogGate {
    private var didEnter = false
    private var entry: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?
    func entered() async {
        if didEnter { return }
        await withCheckedContinuation { entry = $0 }
    }
    func wait() async {
        didEnter = true
        entry?.resume()
        entry = nil
        await withCheckedContinuation { blocked = $0 }
    }
    func release() {
        blocked?.resume()
        blocked = nil
    }
}
