import Foundation
import InnoNetwork
import Testing

@testable import InnoNetworkHLS
@testable import InnoNetworkHLSLive

extension HLSLivePlaylistClientTests {
    @Test(
        "DVR ranges require a complete valid Content-Range",
        arguments: [
            "bytes 0-3/4", "bytes 0-3/*", "bytes 0-3/0", "bytes 0-3", "bytes 0-3/garbage", "bytes +0-3/4",
        ])
    func productionRangeSyntax(header: String) throws {
        let range = try #require(HLSByteRange(offset: 0, length: 4))
        let valid = ["bytes 0-3/4", "bytes 0-3/*"].contains(header)
        #expect(HLSLiveDVRResourceLoader.matches(contentRange: header, byteRange: range) == valid)
        #expect(
            HLSLiveDVRResourceLoader.matches(
                contentRange: header, openEndedByteRangeStart: 0, expectedContentLength: -1) == valid)
    }

    @Test("DVR open ranges verify actual bytes without Content-Length", arguments: [2, 4, 5])
    func productionOpenRangeLength(count: Int) async throws {
        let url = try #require(URL(string: "https://media.example/open-range.mp4"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HLSLiveURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("part.mp4")
        defer {
            session.invalidateAndCancel()
            HLSLiveURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        HLSLiveURLProtocol.register(
            .init(
                statusCode: 206, data: Data(repeating: 1, count: count), headers: ["Content-Range": "bytes 0-3/4"]),
            for: url)
        let client = HLSHTTPClient(
            session: session, requestContext: NetworkRequestContext(), requestPolicy: HLSRequestPolicy())
        var rejected = false
        do {
            let bytes = try await HLSLiveDVRResourceLoader(client: client, requestTimeout: 10).load(
                from: url, byteRange: nil, openEndedByteRangeStart: 0, encryption: nil, resourceIndex: 0,
                maximumBytes: 64, maximumRetainedBytes: 64, keyCache: HLSAES128KeyCache(client: client),
                diskCapacityGuard: HLSDiskCapacityGuard(directoryURL: directory, policy: .disabled),
                destinationURL: destination)
            #expect(bytes == 4)
        } catch HLSLiveDVRResourceLoadError.invalidByteRangeResponse {
            rejected = true
        }
        #expect(rejected == (count != 4))
        #expect(FileManager.default.fileExists(atPath: destination.path) == (count == 4))
    }
}
