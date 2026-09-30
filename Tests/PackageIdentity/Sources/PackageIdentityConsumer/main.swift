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
precondition(macroConfiguration.maximumMediaResourceBytes == 4_096)
precondition(macroConfiguration.maximumTotalDownloadBytes == 16_384)
precondition(macroConfiguration.maximumConcurrentResourceTransfers == 2)
_ = try ConsumerDownload.makeDownloader()
_ = try ManualDownload.makeDownloader()
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
