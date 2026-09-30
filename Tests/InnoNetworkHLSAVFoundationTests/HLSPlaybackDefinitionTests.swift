import AVFoundation
import Testing

@testable import InnoNetworkHLSAVFoundation

@HLSPlaybackDefinition(maximumPeakBitRate: 1000, maximumWidth: 320, maximumHeight: 240)
private enum TestPlayback {}

@Suite("Playback workflow definition")
struct HLSPlaybackDefinitionTests {
    @Test("macro applies to caller-owned native item on MainActor without playback")
    @MainActor
    func playback() async throws {
        let item = AVPlayerItem(asset: AVMutableComposition())
        _ = try await TestPlayback.apply(to: item)
        #expect(item.preferredPeakBitRate == 1000)
        #expect(item.preferredMaximumResolution.width == 320)
        #expect(throws: HLSPlaybackLimitError.invalidLimits) { try HLSPlaybackConfiguration.validated(maximumWidth: 0) }
        #expect(throws: HLSPlaybackLimitError.invalidLimits) {
            try HLSPlaybackConfiguration.validated(maximumHeight: Int.max)
        }
    }
}
