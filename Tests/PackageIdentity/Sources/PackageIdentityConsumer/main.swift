import AVFoundation
import Foundation
import InnoNetwork
import InnoNetworkHLS
import InnoNetworkHLSAVFoundation
import InnoNetworkHLSAudio
import InnoNetworkHLSLive

@HLSDownloadDefinition(
    maximumMediaResourceBytes: 4_096,
    maximumTotalDownloadBytes: 16_384,
    maximumConcurrentResourceTransfers: 2
)
enum ConsumerDownload {}

@HLSDownloadDefinition
enum ConditionalDownload {
    #if DEBUG
    static let debugLabel = "debug"
    #else
    static let debugLabel = "release"
    #endif
}

@HLSLiveDefinition(minimumPollingMilliseconds: 50, maximumPollingMilliseconds: 100)
enum ConsumerLive {}
@HLSDVRDefinition(maximumDurationSeconds: 60, maximumSegmentCount: 10)
enum ConsumerDVR {}
@HLSPlaybackDefinition(maximumPeakBitRate: 1000, maximumWidth: 320, maximumHeight: 240)
enum ConsumerPlayback {}
@HLSCatalogDefinition(maximumEntries: 3, maximumSnapshotBytes: 2048)
enum ConsumerCatalog {}

// Exact README backend examples: compile effects, invoke settings only below.
@HLSLiveDefinition
enum ChannelWatch {}
@HLSDVRDefinition(maximumDurationSeconds: 1800, maximumSegmentCount: 900)
enum ChannelArchive {}
@HLSPlaybackDefinition(maximumPeakBitRate: 10_000_000, maximumWidth: 1920, maximumHeight: 1080)
enum PlaybackProfile {}
@HLSCatalogDefinition(maximumEntries: 128, maximumSnapshotBytes: 65_536)
enum MediaLibrary {}

func watchChannel(source: URL, session: URLSession) throws -> HLSLiveWatching {
    try ChannelWatch.watch(from: source, session: session)
}
func recordChannel(source: URL, destination: URL, client: HLSLivePlaylistClient) throws -> HLSLiveDVRRecording {
    try ChannelArchive.startRecording(from: source, to: destination, client: client)
}
@MainActor
func configurePlayback(item: AVPlayerItem) async throws -> HLSPlaybackConfigurationResult {
    try await PlaybackProfile.apply(to: item)
}
func makeMediaLibrary(store: any HLSMediaCatalogPersisting) throws -> HLSMediaCatalog {
    try MediaLibrary.makeCatalog(persistence: store)
}
@InnoNetworkHLSLive.HLSLiveDefinition
enum QualifiedLive {}

// Compile-time isolation control: configuration generation is pure.
@MainActor
@HLSDownloadDefinition
enum IsolatedDownload {}
@MainActor
@HLSLiveDefinition
enum IsolatedLive {}
@MainActor
@HLSDVRDefinition
enum IsolatedDVR {}
@MainActor
@HLSPlaybackDefinition
enum IsolatedPlayback {}
@MainActor
@HLSCatalogDefinition
enum IsolatedCatalog {}

struct ManualLive: HLSLiveDefining { static func configuration() throws -> HLSLiveConfiguration { try .validated() } }
struct ManualDVR: HLSDVRDefining { static func configuration() throws -> HLSLiveDVRConfiguration { try .validated() } }
struct ManualPlayback: HLSPlaybackDefining {
    static func configuration() throws -> HLSPlaybackConfiguration { try .validated() }
}
struct ManualCatalog: HLSCatalogDefining {
    static func configuration() throws -> HLSMediaCatalogConfiguration { try .validated() }
}

// Compile backend-specific entry points without initiating external effects.
func observeLive(source: URL, session: URLSession) throws -> HLSLiveWatching {
    try ConsumerLive.watch(from: source, session: session)
}
func recordLive(source: URL, destination: URL, client: HLSLivePlaylistClient) throws -> HLSLiveDVRRecording {
    try ConsumerDVR.startRecording(from: source, to: destination, client: client)
}

struct ManualDownload: HLSDownloadDefining {
    static func configuration() throws -> HLSDownloadConfiguration {
        try .validated(maximumMediaResourceBytes: 4_096, maximumTotalDownloadBytes: 16_384)
    }
}

@APIDefinition(method: .get, path: "/fixture", auth: .anonymous)
struct ConsumerEndpoint {
    typealias APIResponse = String
}

// Exact README workflow and cancellation convenience, compiled externally.
@HLSDownloadDefinition(
    maximumMediaResourceBytes: 8_388_608,
    maximumTotalDownloadBytes: 268_435_456,
    maximumConcurrentResourceTransfers: 3
)
enum MovieDownload {}

func saveMovie(source: URL, destination: URL) async throws -> HLSDownloadReceipt {
    let operation = try MovieDownload.start(
        sourceURL: source,
        destinationURL: destination
    )
    return try await withTaskCancellationHandler {
        try await operation.receipt()
    } onCancel: {
        operation.cancel()
    }
}

let macroConfiguration = try ConsumerDownload.configuration()
_ = try ConditionalDownload.configuration()
precondition(macroConfiguration.maximumMediaResourceBytes == 4_096)
precondition(macroConfiguration.maximumTotalDownloadBytes == 16_384)
precondition(macroConfiguration.maximumConcurrentResourceTransfers == 2)
_ = try ConsumerDownload.makeDownloader()
_ = try ManualDownload.makeDownloader()
let liveConfiguration = try ConsumerLive.configuration()
let dvrConfiguration = try ConsumerDVR.configuration()
let playbackConfiguration = try ConsumerPlayback.configuration()
precondition(liveConfiguration.minimumPollingInterval == 0.05)
precondition(dvrConfiguration.effectiveLimits.maximumSegmentCount == 10)
precondition(playbackConfiguration.variant.maximumWidth == 320)
let catalog = try ConsumerCatalog.makeCatalog()
let catalogRecord = try HLSMediaRecord(id: HLSMediaID(), ownership: .applicationFile, reference: "consumer-asset")
try await catalog.upsert(catalogRecord)
let catalogSnapshot = await catalog.snapshot()
precondition(catalogSnapshot.count == 1)
_ = try ManualLive.makeClient()
_ = try ManualDVR.configuration()
_ = try ManualPlayback.configuration()
_ = try ManualCatalog.makeCatalog()
_ = try QualifiedLive.configuration()
// All five pure generated configuration factories work across actor boundaries.
_ = try await Task.detached {
    _ = try IsolatedDownload.makeDownloader()
    _ = try IsolatedLive.makeClient()
    _ = try IsolatedDVR.configuration()
    _ = try IsolatedPlayback.configuration()
    _ = try IsolatedCatalog.makeCatalog()
}.value
precondition(ConsumerEndpoint().path == "/fixture")

let parsedDocument = try HLSPlaylistParser().parse(
    "#EXTM3U\n#EXTINF:1,\nsegment.ts\n#EXT-X-ENDLIST\n",
    relativeTo: URL(string: "https://media.example/media.m3u8")!
)
guard case .media(let media) = parsedDocument else { fatalError("incorrect playlist kind") }
precondition(media.segmentCount == 1)
try media.validateSingleFileDownload()

// Compile the macro-first advisory phase as well; never contact the network
// from this package-identity fixture.
func previewMovie(source: URL, session: URLSession) async throws -> HLSDownloadPreparation {
    try await MovieDownload.prepare(sourceURL: source, session: session)
}

_ = HLSDownloadConfiguration.safeDefaults()
_ = HLSLiveConfiguration.safeDefaults()
_ = HLSPlaybackConfiguration.safeDefaults()

#if compiler(>=6.4)
if #available(macOS 27, *) {
    _ = try HLSDecodedAudioConfiguration.float32()
}
#endif

print("package-identity-consumer: OK (four unchanged imports, Stream/Network macros, README example)")
