import Foundation
import Testing

@testable import InnoNetworkHLS

@Suite("Persisted offline wire compatibility")
struct HLSPersistedContractTests {
    @Test(arguments: [1, 3])
    func manifest(_ version: Int) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ContractFixtures/offline-manifest-v\(version).json")
        let data = try Data(contentsOf: url)
        let value = try JSONDecoder().decode(HLSOfflinePackageManifest.self, from: data)
        #expect(value.schemaVersion == version)
        #expect(value.tracks.count == 1)
        #expect(value.resumedResourceTransferCount == 0)
        #expect(value.tracks.first?.characteristics == [])
        if version == 3 {
            let encoded = try JSONEncoder().encode(value)
            #expect(
                try JSONSerialization.jsonObject(with: data) as? NSDictionary == JSONSerialization.jsonObject(
                    with: encoded) as? NSDictionary)
        }
        // Wire DTO decoding is not package integrity/executable validation.
    }
}
