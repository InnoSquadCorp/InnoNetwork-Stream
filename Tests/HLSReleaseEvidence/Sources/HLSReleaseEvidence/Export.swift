import Foundation
import InnoNetworkHLS
import InnoNetworkHLSLive

// The public SDK does the actual writing. This exporter never renders its own
// output playlists and has no network fallback for missing fixture resources.
private final class EvidenceFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let root = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["HLS_EVIDENCE_INPUT_ROOT"] ?? "")

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let url = request.url, url.host == "media.example",
                !url.pathComponents.contains("..")
            else { throw URLError(.badURL) }
            let file = Self.root.appendingPathComponent(String(url.path.dropFirst()))
            let data = try Data(contentsOf: file)
            guard
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Length": String(data.count)]
                )
            else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@main
private struct Export {
    static func main() async throws {
        guard CommandLine.arguments.count == 2,
            ProcessInfo.processInfo.environment["HLS_EVIDENCE_INPUT_ROOT"] != nil
        else { throw URLError(.badURL) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EvidenceFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var playlists: [String: String] = [:]
        for fixture in ["transport-stream", "fragmented-mp4", "audio-fmp4"] {
            guard let source = URL(string: "https://media.example/\(fixture)/index.m3u8") else {
                throw URLError(.badURL)
            }
            let offlineID = "offline-\(fixture)"
            let offline = try await HLSOfflinePackageDownloader(
                session: session,
                configuration: .advanced(storage: HLSOfflinePackageStoragePack(diskCapacityPolicy: .disabled))
            ).downloadPackage(
                sourceURL: source, destinationDirectoryURL: output.appendingPathComponent(offlineID))
            _ = try HLSOfflinePackageStore().open(at: offline.directoryURL)
            playlists[offlineID] = relativePath(offline.entryPlaylistURL, under: output)
            let dvrID = "dvr-\(fixture)"
            let dvr = try await HLSLiveDVRRecorder(
                client: HLSLivePlaylistClient(session: session),
                configuration: .advanced(
                    limits: HLSLiveDVRLimitPack(
                        maximumDuration: 60, maximumSegmentCount: 100,
                        diskCapacityPolicy: .disabled),
                    startPosition: .currentWindow)
            ).record(from: source, to: output.appendingPathComponent(dvrID))
            try reopenLocalPlaylist(dvr.playbackSource)
            playlists[dvrID] = relativePath(dvr.entryPlaylistURL, under: output)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(playlists).write(to: output.appendingPathComponent("playlists.json"), options: .atomic)
    }

    private static func reopenLocalPlaylist(_ source: HLSLocalPlaybackSource) throws {
        // This is a separate consumer package: validate through public APIs.
        let local = try HLSLocalPlaybackSource(
            packageDirectoryURL: source.packageDirectoryURL,
            entryPlaylistURL: source.entryPlaylistURL)
        let handle = try FileHandle(forReadingFrom: local.entryPlaylistURL)
        defer { try? handle.close() }
        let limit = 2 * 1_024 * 1_024
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit, let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        _ = try PlaylistResolver().resolve(text, relativeTo: local.entryPlaylistURL)
    }

    private static func relativePath(_ file: URL, under root: URL) -> String {
        String(file.path.dropFirst(root.path.count + 1))
    }
}
