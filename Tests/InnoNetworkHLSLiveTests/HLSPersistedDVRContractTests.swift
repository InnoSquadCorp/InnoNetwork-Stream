import Foundation
import Testing

@testable import InnoNetworkHLSLive

@Suite("Persisted DVR wire compatibility")
struct HLSPersistedDVRContractTests {
    @Test
    func checkpoint() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ContractFixtures/dvr-checkpoint-v1.json")
        let data = try Data(contentsOf: url)
        let value = try JSONDecoder().decode(HLSLiveDVRCheckpoint.self, from: data)
        #expect(value.schemaVersion == HLSLiveDVRCheckpoint.schemaVersion)
        #expect(value.primary.mediaContainer == .mpegTransportStream)
        #expect(value.primary.resolvedInitializations.isEmpty)
        let encoded = try JSONEncoder().encode(value)
        #expect(
            try JSONSerialization.jsonObject(with: data) as? NSDictionary == JSONSerialization.jsonObject(with: encoded)
                as? NSDictionary)
        // Empty tracks intentionally test only the wire shape; recording
        // validity/integrity/corruption is covered by actual recorder controls.
    }
}
