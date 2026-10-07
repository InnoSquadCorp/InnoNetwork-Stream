import Foundation
import InnoNetwork
import Testing

@testable import InnoNetworkHLS

@Suite("Offline package manifest byte limits")
struct HLSOfflineManifestLimitTests {
    @Test("manifest encoding accepts the byte boundary and rejects one byte less")
    func encodedByteBoundary() throws {
        let manifest = HLSOfflinePackageManifest(
            entryPlaylistPath: "index.m3u8",
            tracks: [
                HLSOfflinePackageTrack(
                    kind: .primary,
                    name: "영상 🎬 \"quoted\" \\ name",
                    language: nil,
                    isDefault: false,
                    isAutoselect: false,
                    isForced: false,
                    relativePlaylistPath: "media/primary/index.m3u8"
                )
            ],
            selectedVariant: nil,
            files: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let expected = try encoder.encode(manifest)
        let json = try #require(String(data: expected, encoding: .utf8))
        #expect(expected.count > json.count)
        #expect(HLSOfflinePackageManifest.maximumEncodedBytes == 8 * 1_024 * 1_024)
        #expect(try manifest.encodedData(maximumBytes: expected.count) == expected)
        #expect(try manifest.encodedData() == expected)
        for limit in [-1, 0, expected.count - 1] {
            #expect(throws: HLSDownloadError.invalidOfflinePackage) {
                try manifest.encodedData(maximumBytes: limit)
            }
        }
        let decoded = try JSONDecoder().decode(
            HLSOfflinePackageManifest.self,
            from: manifest.encodedData(maximumBytes: expected.count)
        )
        #expect(decoded.tracks == manifest.tracks)
    }
}

extension HLSDownloaderTests {
    @Test(
        "oversized manifests fail before publication and honor resource recovery",
        arguments: [HLSResumePolicy.automatic, .disabled]
    )
    func oversizedOfflineManifestPreservesRecovery(
        resumePolicy: HLSResumePolicy
    ) async throws {
        let playlistURL = try #require(
            URL(string: "https://media.example/manifest-limit.m3u8")
        )
        let resourceURL = try #require(
            URL(string: "https://media.example/manifest-limit.ts")
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [HLSURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
        }
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: Data(
                    """
                    #EXTM3U
                    #EXT-X-VERSION:3
                    #EXT-X-TARGETDURATION:1
                    #EXTINF:1,
                    manifest-limit.ts
                    #EXT-X-ENDLIST

                    """.utf8
                ),
                headers: [:]
            ),
            for: playlistURL
        )
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: Data("VIDEO".utf8),
                headers: ["Content-Length": "5"]
            ),
            for: resourceURL
        )
        let fileManager = FileManager.default
        let parentURL = fileManager.temporaryDirectory.appendingPathComponent(
            "HLSOfflineManifestLimitTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: parentURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: parentURL) }
        let destinationURL = parentURL.appendingPathComponent(
            "bounded.hlspkg",
            isDirectory: true
        )
        let resumeURL = parentURL.appendingPathComponent(
            ".bounded.hlspkg.hls-package-resume",
            isDirectory: true
        )
        let client = HLSHTTPClient(
            session: session,
            requestContext: NetworkRequestContext(),
            requestAdapter: { $0 }
        )
        let configuration = HLSOfflinePackageConfiguration.advanced(
            storage: HLSOfflinePackageStoragePack(
                diskCapacityPolicy: .disabled,
                resumePolicy: resumePolicy
            ),
            transfer: HLSTransferPack(retryPolicy: nil)
        )
        let rejected = await HLSOfflinePackageOperation(
            client: client,
            configuration: configuration,
            diskCapacityChecker: HLSDiskCapacityChecker(),
            clock: HLSSystemClock(),
            maximumManifestBytes: 1
        ).execute(
            sourceURL: playlistURL,
            destinationDirectoryURL: destinationURL,
            onProgress: { _ in }
        )
        guard case .failed(.invalidOfflinePackage) = rejected else {
            Issue.record("Expected rejection of the oversized manifest.")
            return
        }
        #expect(!fileManager.fileExists(atPath: destinationURL.path))
        #expect(
            HLSURLProtocol.capturedRequests().filter { $0.url == resourceURL }.count == 1
        )
        if resumePolicy == .automatic {
            #expect(fileManager.fileExists(atPath: resumeURL.path))
            let completed = try fileManager.contentsOfDirectory(
                atPath: resumeURL.appendingPathComponent("completed").path
            )
            #expect(completed.count == 1)
            #expect(
                !fileManager.fileExists(
                    atPath: resumeURL.appendingPathComponent("package/manifest.json").path
                )
            )
        } else {
            let siblings = try fileManager.contentsOfDirectory(atPath: parentURL.path)
            #expect(Set(siblings) == [".innonetwork-hls-locks"])
        }

        // Raising the internal test limit to the production default exercises
        // recovery without constructing tens of thousands of resource requests.
        let retried = await HLSOfflinePackageOperation(
            client: client,
            configuration: configuration,
            diskCapacityChecker: HLSDiskCapacityChecker(),
            clock: HLSSystemClock()
        ).execute(
            sourceURL: playlistURL,
            destinationDirectoryURL: destinationURL,
            onProgress: { _ in }
        )
        guard case .completed(let receipt) = retried else {
            Issue.record("Expected a reopenable package after retry.")
            return
        }
        let expectedRetainedCount = resumePolicy == .automatic ? 1 : 0
        #expect(receipt.resumedResourceTransferCount == expectedRetainedCount)
        #expect(
            HLSURLProtocol.capturedRequests().filter { $0.url == resourceURL }.count
                == (resumePolicy == .automatic ? 1 : 2)
        )
        #expect(!fileManager.fileExists(atPath: resumeURL.path))
        #expect(
            try HLSOfflinePackageStore().open(at: destinationURL)
                .resumedResourceTransferCount == expectedRetainedCount
        )
        let manifestBytes = try Data(
            contentsOf: destinationURL.appendingPathComponent("manifest.json")
        ).count
        #expect(
            try HLSOfflinePackageValidator.open(
                at: destinationURL,
                maximumManifestBytes: manifestBytes
            ).byteCount == receipt.byteCount
        )
        #expect(throws: HLSDownloadError.invalidOfflinePackage) {
            try HLSOfflinePackageValidator.open(
                at: destinationURL,
                maximumManifestBytes: manifestBytes - 1
            )
        }
    }
}
