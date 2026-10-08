import AVFoundation
import Foundation
import InnoNetwork
import InnoNetworkHLS
import InnoNetworkHLSLive
import InnoNetworkHLSAVFoundation
import InnoNetworkHLSAudio

@HLSDownloadDefinition(maximumMediaResourceBytes: 4096, maximumTotalDownloadBytes: 16384, maximumConcurrentResourceTransfers: 2)
enum MovieDownload {}
@HLSOfflinePackageDefinition(maximumMediaResourceBytes: 4096, maximumTotalDownloadBytes: 16384, maximumConcurrentResourceTransfers: 2)
enum OfflineMovie {}
@HLSLiveDefinition(minimumPollingMilliseconds: 50, maximumPollingMilliseconds: 100)
enum ChannelWatch {}
@HLSDVRDefinition(maximumDurationSeconds: 60, maximumSegmentCount: 10)
enum ChannelArchive {}
@HLSPlaybackDefinition(maximumPeakBitRate: 1000, maximumWidth: 320, maximumHeight: 240)
enum PlaybackProfile {}
@HLSCatalogDefinition(maximumEntries: 2, maximumSnapshotBytes: 2048)
enum MediaLibrary {}

struct ManualDownload: HLSDownloadDefining {
    static func configuration() throws -> HLSDownloadConfiguration { try .validated(maximumMediaResourceBytes: 4096, maximumTotalDownloadBytes: 16384, maximumConcurrentResourceTransfers: 2) }
}
struct ManualOffline: HLSOfflinePackageDefining {
    static func configuration() throws -> HLSOfflinePackageConfiguration { try .validated(maximumMediaResourceBytes: 4096, maximumTotalDownloadBytes: 16384, maximumConcurrentResourceTransfers: 2) }
}
struct ManualLive: HLSLiveDefining {
    static func configuration() throws -> HLSLiveConfiguration { try .validated(minimumPollingMilliseconds: 50, maximumPollingMilliseconds: 100) }
}
struct ManualDVR: HLSDVRDefining {
    static func configuration() throws -> HLSLiveDVRConfiguration { try .validated(maximumDurationSeconds: 60, maximumSegmentCount: 10) }
}
struct ManualPlayback: HLSPlaybackDefining {
    static func configuration() throws -> HLSPlaybackConfiguration { try .validated(maximumPeakBitRate: 1000, maximumWidth: 320, maximumHeight: 240) }
}
struct ManualCatalog: HLSCatalogDefining {
    static func configuration() throws -> HLSMediaCatalogConfiguration { try .validated(maximumEntries: 2, maximumSnapshotBytes: 2048) }
}

@MainActor
@HLSDownloadDefinition
enum ActorDownload {}

func saveMovie(source: URL, destination: URL, session: URLSession) async throws -> HLSDownloadReceipt {
    let operation = try MovieDownload.start(sourceURL: source, destinationURL: destination, session: session)
    return try await withTaskCancellationHandler {
        try await operation.receipt()
    } onCancel: {
        operation.cancel()
    }
}
func recordChannel(source: URL, destination: URL, client: HLSLivePlaylistClient) throws -> HLSLiveDVRRecording {
    try ChannelArchive.startRecording(from: source, to: destination, client: client)
}
@MainActor
func configurePlayback(item: AVPlayerItem) async throws -> HLSPlaybackConfigurationResult {
    try await PlaybackProfile.apply(to: item)
}
#if compiler(>=6.4)
@available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
@MainActor
func attachAudio(item: AVPlayerItem) throws -> HLSDecodedAudioOutput {
    HLSDecodedAudioOutput(playerItem: item, configuration: try .float32(sampleRate: 48_000, channelCount: 2))
}
#endif
