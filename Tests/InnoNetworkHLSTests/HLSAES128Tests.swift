import CommonCrypto
import Foundation
import InnoNetwork
import Testing

@testable import InnoNetworkHLS

extension HLSDownloaderTests {
    @Test("Recording key caches evict old URLs and safely refetch them")
    func recordingKeyCacheIsBounded() async throws {
        let session = makeAES128Session()
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
        }
        let cache = HLSAES128KeyCache(
            client: HLSHTTPClient(
                session: session,
                requestContext: NetworkRequestContext(),
                requestAdapter: { $0 }
            ),
            maximumKeyCount: 4
        )
        let keyURLs = try (0..<64).map {
            try #require(URL(string: "https://media.example/rotation-\($0).key"))
        }
        for (index, url) in keyURLs.enumerated() {
            let key = Data(repeating: UInt8(index), count: 16)
            HLSURLProtocol.register(
                .success(statusCode: 200, data: key, headers: [:]), for: url
            )
            #expect(try await cache.key(for: url) == key)
        }
        let newest = try #require(keyURLs.last)
        #expect(try await cache.key(for: newest) == Data(repeating: 63, count: 16))
        let first = try #require(keyURLs.first)
        #expect(try await cache.key(for: first) == Data(repeating: 0, count: 16))
        #expect(try await cache.key(for: newest) == Data(repeating: 63, count: 16))
        let requests = HLSURLProtocol.capturedRequests().compactMap(\.url)
        #expect(requests.count == 65)
        #expect(requests.count { $0 == first } == 2)
        #expect(requests.count { $0 == newest } == 1)
    }

    @Test("Recording key caches bound aggregate signed URL bytes independently of entry count")
    func recordingKeyCacheBoundsURLBytes() async throws {
        let session = makeAES128Session()
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
        }
        let urls = try (0..<3).map {
            try #require(
                URL(
                    string:
                        "https://media.example/key-\($0).bin?signature=" + String(repeating: "a", count: 128)))
        }
        let first = urls[0]
        let second = urls[1]
        let third = urls[2]
        let key = Data(repeating: 0x31, count: 16)
        let entryBytes = first.absoluteString.utf8.count + key.count
        let cache = HLSAES128KeyCache(
            client: HLSHTTPClient(
                session: session,
                requestContext: NetworkRequestContext(),
                requestAdapter: { $0 }
            ),
            maximumKeyCount: 128,
            maximumRetainedBytes: entryBytes * 2
        )
        for url in urls {
            HLSURLProtocol.register(
                .success(statusCode: 200, data: key, headers: [:]), for: url
            )
        }
        #expect(try await cache.key(for: first) == key)
        #expect(try await cache.key(for: second) == key)
        // A hit changes recency without charging URL bytes again.
        #expect(try await cache.key(for: first) == key)
        #expect(try await cache.key(for: third) == key)
        #expect(try await cache.key(for: first) == key)
        // The byte limit evicted the second URL even though only three of
        // 128 possible entries were seen. Refilling must reclaim its old cost.
        #expect(try await cache.key(for: second) == key)
        #expect(try await cache.key(for: first) == key)
        let requests = HLSURLProtocol.capturedRequests().compactMap(\.url)
        #expect(requests.count == 4)
        #expect(requests.count { $0 == first } == 1)
        #expect(requests.count { $0 == second } == 2)
        #expect(requests.count { $0 == third } == 1)
    }

    @Test("Concurrent key fills replace one byte-budget charge")
    func recordingKeyCacheChargesConcurrentReplacementOnce() async throws {
        let session = makeAES128Session()
        let gate = AES128ConcurrentFillGate()
        defer {
            Task { await gate.releaseFirst() }
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
        }
        let firstURL = try #require(URL(string: "https://media.example/key-1.bin"))
        let secondURL = try #require(URL(string: "https://media.example/key-2.bin"))
        let key = Data(repeating: 0x51, count: 16)
        let cache = HLSAES128KeyCache(
            client: HLSHTTPClient(
                session: session,
                requestContext: NetworkRequestContext(),
                requestAdapter: { request in
                    if request.url == firstURL {
                        await gate.delayFirstRequest()
                    }
                    return request
                }
            ),
            maximumRetainedBytes: (firstURL.absoluteString.utf8.count + key.count) * 2
        )
        for url in [firstURL, secondURL] {
            HLSURLProtocol.register(
                .success(statusCode: 200, data: key, headers: [:]), for: url
            )
        }
        let firstFill = Task { try await cache.key(for: firstURL) }
        await gate.waitForFirstRequest()
        // The second request fills the cache while the first is suspended.
        #expect(try await cache.key(for: firstURL) == key)
        await gate.releaseFirst()
        #expect(try await firstFill.value == key)
        #expect(try await cache.key(for: secondURL) == key)
        #expect(try await cache.key(for: firstURL) == key)
        #expect(try await cache.key(for: secondURL) == key)
        let requests = HLSURLProtocol.capturedRequests().compactMap(\.url)
        #expect(requests.count { $0 == firstURL } == 2)
        #expect(requests.count { $0 == secondURL } == 1)
    }

    @Test("Oversized signed key URLs bypass caching without evicting useful keys")
    func recordingKeyCacheBypassesOversizedURL() async throws {
        let session = makeAES128Session()
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
        }
        let shortURL = try #require(URL(string: "https://media.example/key.bin"))
        let longURL = try #require(
            URL(
                string:
                    "https://media.example/key.bin?signature=" + String(repeating: "b", count: 256)))
        let key = Data(repeating: 0x41, count: 16)
        let cache = HLSAES128KeyCache(
            client: HLSHTTPClient(
                session: session,
                requestContext: NetworkRequestContext(),
                requestAdapter: { $0 }
            ),
            maximumRetainedBytes: shortURL.absoluteString.utf8.count + key.count
        )
        for url in [shortURL, longURL] {
            HLSURLProtocol.register(
                .success(statusCode: 200, data: key, headers: [:]), for: url
            )
        }
        #expect(try await cache.key(for: shortURL) == key)
        #expect(try await cache.key(for: longURL) == key)
        #expect(try await cache.key(for: longURL) == key)
        #expect(try await cache.key(for: shortURL) == key)
        let requests = HLSURLProtocol.capturedRequests().compactMap(\.url)
        #expect(requests.count { $0 == shortURL } == 1)
        #expect(requests.count { $0 == longURL } == 2)
    }

    @Test("Empty decrypted media cannot publish an offline package", arguments: [false, true])
    func productionEmptyPlaintext(empty: Bool) async throws {
        let url = try #require(URL(string: "https://media.example/empty-plaintext.m3u8"))
        let keyURL = try #require(URL(string: "https://media.example/key.bin"))
        let mediaURL = try #require(URL(string: "https://media.example/segment.ts"))
        let key = Data(repeating: 0, count: 16)
        let iv = Data(repeating: 0, count: 16)
        let ciphertext = try aes128Encrypt(empty ? Data() : Data("MEDIA".utf8), key: key, initializationVector: iv)
        let session = makeAES128Session()
        let directory = try makeAES128TemporaryDirectory()
        let destination = directory.appendingPathComponent("media.hlspkg")
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        let playlist =
            "#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"\n#EXTINF:1,\nsegment.ts\n#EXT-X-ENDLIST\n"
        HLSURLProtocol.register(.success(statusCode: 200, data: Data(playlist.utf8), headers: [:]), for: url)
        HLSURLProtocol.register(.success(statusCode: 200, data: key, headers: [:]), for: keyURL)
        HLSURLProtocol.register(.success(statusCode: 200, data: ciphertext, headers: [:]), for: mediaURL)
        var rejected = false
        do {
            _ = try await HLSOfflinePackageDownloader(session: session).downloadPackage(
                sourceURL: url, destinationDirectoryURL: destination)
        } catch HLSDownloadError.aes128DecryptionFailed { rejected = true }
        #expect(rejected == empty)
        #expect(FileManager.default.fileExists(atPath: destination.path) == !empty)
    }

    @Test("AES-128 media is decrypted with an explicit IV")
    func downloadsAES128Media() async throws {
        let playlistURL = try #require(
            URL(string: "https://media.example/encrypted.m3u8")
        )
        let keyURL = try #require(
            URL(string: "https://media.example/key.bin?token=secret")
        )
        let segmentURL = try #require(
            URL(string: "https://media.example/segment.ts")
        )
        let key = Data(0..<16)
        let initializationVector = Data(16..<32)
        let plaintext = Data("decrypted media payload".utf8)
        let ciphertext = try aes128Encrypt(
            plaintext,
            key: key,
            initializationVector: initializationVector
        )
        let session = makeAES128Session()
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
                    #EXT-X-KEY:METHOD=AES-128,URI="key.bin?token=secret",IV=0x101112131415161718191a1b1c1d1e1f
                    #EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://asset",KEYFORMAT="com.apple.streamingkeydelivery"
                    #EXTINF:1,
                    segment.ts
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
                data: key,
                headers: ["Content-Length": "\(key.count)"]
            ),
            for: keyURL
        )
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: ciphertext,
                headers: [
                    "Content-Length": "\(ciphertext.count)"
                ]
            ),
            for: segmentURL
        )
        let directoryURL = try makeAES128TemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let destinationURL = directoryURL.appendingPathComponent(
            "decrypted.ts"
        )
        let requestRecorder = HLSRequestEventRecorder()

        var progressEvents: [HLSDownloadProgress] = []
        var didComplete = false
        for await event in HLSDownloader(
            session: session,
            configuration: .advanced(
                storage: HLSStoragePack(
                    diskCapacityPolicy: .disabled
                ),
                transfer: HLSTransferPack(retryPolicy: nil)
            ),
            requestPolicy: HLSRequestPolicy(
                eventObservers: [requestRecorder]
            )
        ).download(
            sourceURL: playlistURL,
            destinationURL: destinationURL
        ) {
            switch event {
            case .progress(let progress):
                progressEvents.append(progress)
            case .completed:
                didComplete = true
            case .failed(let error):
                Issue.record("Unexpected AES-128 failure: \(error)")
            case .cancelled:
                Issue.record("Unexpected AES-128 cancellation.")
            }
        }

        #expect(didComplete)
        #expect(try Data(contentsOf: destinationURL) == plaintext)
        let finalProgress = try #require(progressEvents.last)
        #expect(
            finalProgress.totalBytesWritten
                == Int64(plaintext.count)
        )
        #expect(
            finalProgress.totalBytesExpectedToWrite
                == Int64(plaintext.count)
        )
        let requestContexts = await requestRecorder.startedContexts()
        #expect(
            requestContexts.map(\.purpose)
                == [
                    .entryPlaylist,
                    .encryptionKey,
                    .mediaResource,
                ]
        )
        #expect(
            requestContexts.last?.resourceIndex == 0
        )
        #expect(
            HLSURLProtocol.capturedRequests().compactMap(\.url)
                == [playlistURL, keyURL, segmentURL]
        )
        let keyRequest = try #require(
            HLSURLProtocol.capturedRequests().first {
                $0.url == keyURL
            }
        )
        #expect(
            keyRequest.value(forHTTPHeaderField: "Cache-Control")
                == "no-store"
        )
        #expect(
            keyRequest.cachePolicy
                == .reloadIgnoringLocalCacheData
        )
        let persistedText = try directoryTextContents(directoryURL)
        #expect(!persistedText.contains("token=secret"))
        #expect(!persistedText.contains(key.base64EncodedString()))
    }

    @Test("prepare does not fetch AES-128 keys or media")
    func preparesAES128MetadataWithoutFetchingSecrets() async throws {
        let playlistURL = try #require(
            URL(string: "https://media.example/encrypted.m3u8")
        )
        let keyURL = try #require(
            URL(string: "https://media.example/key.bin")
        )
        let segmentURL = try #require(
            URL(string: "https://media.example/segment.ts")
        )
        let session = makeAES128Session()
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
                    #EXT-X-KEY:METHOD=AES-128,URI="key.bin"
                    #EXTINF:1,
                    segment.ts
                    #EXT-X-ENDLIST

                    """.utf8
                ),
                headers: [:]
            ),
            for: playlistURL
        )

        let preparation = try await HLSDownloader(
            session: session,
            configuration: .advanced(
                storage: HLSStoragePack(
                    diskCapacityPolicy: .disabled
                )
            )
        ).prepare(sourceURL: playlistURL)

        #expect(preparation.segmentCount == 1)
        #expect(preparation.resourceTransferCount == 1)
        #expect(
            HLSURLProtocol.capturedRequests().compactMap(\.url)
                == [playlistURL]
        )
        #expect(
            !HLSURLProtocol.capturedRequests().contains {
                $0.url == keyURL || $0.url == segmentURL
            }
        )
    }

    @Test("AES-128 key HTTP status fails before media transfer")
    func rejectsAES128KeyHTTPStatus() async throws {
        let playlistURL = try #require(
            URL(string: "https://media.example/encrypted.m3u8")
        )
        let keyURL = try #require(
            URL(string: "https://media.example/key.bin")
        )
        let segmentURL = try #require(
            URL(string: "https://media.example/segment.ts")
        )
        let session = makeAES128Session()
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
                    #EXT-X-KEY:METHOD=AES-128,URI="key.bin"
                    #EXTINF:1,
                    segment.ts
                    #EXT-X-ENDLIST

                    """.utf8
                ),
                headers: [:]
            ),
            for: playlistURL
        )
        HLSURLProtocol.register(
            .success(
                statusCode: 403,
                data: Data(),
                headers: [:]
            ),
            for: keyURL
        )
        let directoryURL = try makeAES128TemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let event = await aes128TerminalEvent(
            from: HLSDownloader(
                session: session,
                configuration: .advanced(
                    storage: HLSStoragePack(
                        diskCapacityPolicy: .disabled
                    ),
                    transfer: HLSTransferPack(retryPolicy: nil)
                )
            ).download(
                sourceURL: playlistURL,
                destinationURL:
                    directoryURL.appendingPathComponent(
                        "rejected.ts"
                    )
            )
        )

        #expect(
            {
                if case .failed(
                    .invalidAES128KeyResponseStatus(403)
                ) = event {
                    return true
                }
                return false
            }()
        )
        #expect(
            !HLSURLProtocol.capturedRequests().contains {
                $0.url == segmentURL
            }
        )
    }

    @Test("invalid AES-128 key length fails before media transfer")
    func rejectsInvalidAES128KeyLength() async throws {
        let playlistURL = try #require(
            URL(string: "https://media.example/encrypted.m3u8")
        )
        let keyURL = try #require(
            URL(string: "https://media.example/key.bin")
        )
        let segmentURL = try #require(
            URL(string: "https://media.example/segment.ts")
        )
        let session = makeAES128Session()
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
                    #EXT-X-KEY:METHOD=AES-128,URI="key.bin"
                    #EXTINF:1,
                    segment.ts
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
                data: Data(repeating: 0, count: 15),
                headers: ["Content-Length": "15"]
            ),
            for: keyURL
        )
        let directoryURL = try makeAES128TemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let destinationURL = directoryURL.appendingPathComponent(
            "rejected.ts"
        )

        let event = await aes128TerminalEvent(
            from: HLSDownloader(
                session: session,
                configuration: .advanced(
                    storage: HLSStoragePack(
                        diskCapacityPolicy: .disabled
                    ),
                    transfer: HLSTransferPack(retryPolicy: nil)
                )
            ).download(
                sourceURL: playlistURL,
                destinationURL: destinationURL
            )
        )

        #expect(
            {
                if case .failed(.invalidAES128Key) = event {
                    return true
                }
                return false
            }()
        )
        #expect(
            !HLSURLProtocol.capturedRequests().contains {
                $0.url == segmentURL
            }
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: destinationURL.path
            )
        )
    }

    @Test("invalid AES-128 ciphertext fails without committing output")
    func rejectsInvalidAES128Ciphertext() async throws {
        let playlistURL = try #require(
            URL(string: "https://media.example/encrypted.m3u8")
        )
        let keyURL = try #require(
            URL(string: "https://media.example/key.bin")
        )
        let segmentURL = try #require(
            URL(string: "https://media.example/segment.ts")
        )
        let session = makeAES128Session()
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
                    #EXT-X-KEY:METHOD=AES-128,URI="key.bin"
                    #EXTINF:1,
                    segment.ts
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
                data: Data(repeating: 0, count: 16),
                headers: ["Content-Length": "16"]
            ),
            for: keyURL
        )
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: Data(repeating: 0, count: 15),
                headers: ["Content-Length": "15"]
            ),
            for: segmentURL
        )
        let directoryURL = try makeAES128TemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let destinationURL = directoryURL.appendingPathComponent(
            "rejected.ts"
        )

        let event = await aes128TerminalEvent(
            from: HLSDownloader(
                session: session,
                configuration: .advanced(
                    storage: HLSStoragePack(
                        diskCapacityPolicy: .disabled
                    ),
                    transfer: HLSTransferPack(retryPolicy: nil)
                )
            ).download(
                sourceURL: playlistURL,
                destinationURL: destinationURL
            )
        )

        guard case .failed(.aes128DecryptionFailed) = event else {
            Issue.record(
                "Expected AES-128 decryption failure, got \(String(reflecting: event))."
            )
            return
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: destinationURL.path
            )
        )
    }

    @Test("offline packages preload, decrypt, and remove key declarations")
    func localizesDecryptedAES128Package() async throws {
        let playlistURL = try #require(
            URL(string: "https://media.example/offline-master.m3u8")
        )
        let mediaURL = try #require(
            URL(string: "https://media.example/encrypted.m3u8")
        )
        let keyURL = try #require(
            URL(string: "https://media.example/key.bin")
        )
        let segmentURL = try #require(
            URL(string: "https://media.example/segment.ts")
        )
        let key = Data(0..<16)
        let initializationVector = Data(16..<32)
        let plaintext = Data("offline plaintext".utf8)
        let ciphertext = try aes128Encrypt(
            plaintext,
            key: key,
            initializationVector: initializationVector
        )
        let session = makeAES128Session()
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
                    #EXT-X-SESSION-KEY:METHOD=AES-128,URI="key.bin"
                    #EXT-X-STREAM-INF:BANDWIDTH=1000
                    encrypted.m3u8

                    """.utf8
                ),
                headers: [:]
            ),
            for: playlistURL
        )
        HLSURLProtocol.register(
            .delayedSuccess(
                statusCode: 200,
                data: Data(
                    """
                    #EXTM3U
                    #EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x101112131415161718191a1b1c1d1e1f
                    #EXTINF:1,
                    segment.ts
                    #EXT-X-ENDLIST

                    """.utf8
                ),
                headers: [:],
                delay: 0.1
            ),
            for: mediaURL
        )
        HLSURLProtocol.register(
            .delayedSuccess(
                statusCode: 200,
                data: key,
                headers: ["Content-Length": "16"],
                delay: 0.1
            ),
            for: keyURL
        )
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: ciphertext,
                headers: [
                    "Content-Length": "\(ciphertext.count)"
                ]
            ),
            for: segmentURL
        )
        let parentURL = try makeAES128TemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: parentURL)
        }
        let packageURL = parentURL.appendingPathComponent(
            "encrypted.hlspkg",
            isDirectory: true
        )

        let receipt = try await HLSOfflinePackageDownloader(
            session: session,
            configuration: .advanced(
                storage: HLSOfflinePackageStoragePack(
                    diskCapacityPolicy: .disabled
                ),
                transfer: HLSTransferPack(
                    retryPolicy: nil,
                    sessionKeyPreloadPolicy: .identityAES128
                )
            )
        ).downloadPackage(
            sourceURL: playlistURL,
            destinationDirectoryURL: packageURL
        )
        let primaryTrack = try #require(receipt.tracks.first)
        let primaryPlaylistURL =
            packageURL.appendingPathComponent(
                primaryTrack.relativePlaylistPath
            )
        let localizedPlaylist = try String(
            contentsOf: primaryPlaylistURL,
            encoding: .utf8
        )
        let localizedResourceURL =
            primaryPlaylistURL.deletingLastPathComponent()
            .appendingPathComponent("resources/00000.ts")

        #expect(!localizedPlaylist.contains("#EXT-X-KEY"))
        #expect(
            try Data(contentsOf: localizedResourceURL)
                == plaintext
        )
        #expect(HLSURLProtocol.maximumActiveRequestCount() >= 2)
        #expect(
            HLSURLProtocol.capturedRequests().count {
                $0.url == keyURL
            } == 1
        )
    }

    @Test("session key preload overlaps media resolution and is reused")
    func preloadsSessionKeyDuringMediaResolution() async throws {
        let masterURL = try #require(
            URL(string: "https://media.example/master.m3u8")
        )
        let mediaURL = try #require(
            URL(string: "https://media.example/media.m3u8")
        )
        let keyURL = try #require(
            URL(string: "https://media.example/key.bin")
        )
        let segmentURL = try #require(
            URL(string: "https://media.example/segment.ts")
        )
        let key = Data(0..<16)
        let initializationVector = Data(16..<32)
        let plaintext = Data("session key preload".utf8)
        let ciphertext = try aes128Encrypt(
            plaintext,
            key: key,
            initializationVector: initializationVector
        )
        let session = makeAES128Session()
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
                    #EXT-X-SESSION-KEY:METHOD=AES-128,URI="key.bin"
                    #EXT-X-STREAM-INF:BANDWIDTH=1000
                    media.m3u8

                    """.utf8
                ),
                headers: [:]
            ),
            for: masterURL
        )
        HLSURLProtocol.register(
            .delayedSuccess(
                statusCode: 200,
                data: Data(
                    """
                    #EXTM3U
                    #EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x101112131415161718191a1b1c1d1e1f
                    #EXTINF:1,
                    segment.ts
                    #EXT-X-ENDLIST

                    """.utf8
                ),
                headers: [:],
                delay: 0.1
            ),
            for: mediaURL
        )
        HLSURLProtocol.register(
            .delayedSuccess(
                statusCode: 200,
                data: key,
                headers: ["Content-Length": "16"],
                delay: 0.1
            ),
            for: keyURL
        )
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: ciphertext,
                headers: ["Content-Length": "\(ciphertext.count)"]
            ),
            for: segmentURL
        )
        let directoryURL = try makeAES128TemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let destinationURL = directoryURL.appendingPathComponent(
            "preloaded.ts"
        )

        let event = await aes128TerminalEvent(
            from: HLSDownloader(
                session: session,
                configuration: .advanced(
                    storage: HLSStoragePack(
                        diskCapacityPolicy: .disabled
                    ),
                    transfer: HLSTransferPack(
                        retryPolicy: nil,
                        sessionKeyPreloadPolicy: .identityAES128
                    )
                )
            ).download(
                sourceURL: masterURL,
                destinationURL: destinationURL
            )
        )

        guard case .completed = event else {
            Issue.record("Expected session-key download to complete.")
            return
        }
        #expect(try Data(contentsOf: destinationURL) == plaintext)
        #expect(HLSURLProtocol.maximumActiveRequestCount() >= 2)
        #expect(
            HLSURLProtocol.capturedRequests().count {
                $0.url == keyURL
            } == 1
        )
    }

    @Test("failed session key preload falls back to demand loading")
    func retriesFailedSessionKeyPreloadOnDemand() async throws {
        let masterURL = try #require(
            URL(string: "https://media.example/fallback-master.m3u8")
        )
        let mediaURL = try #require(
            URL(string: "https://media.example/fallback-media.m3u8")
        )
        let keyURL = try #require(
            URL(string: "https://media.example/fallback.key")
        )
        let segmentURL = try #require(
            URL(string: "https://media.example/fallback.ts")
        )
        let key = Data(0..<16)
        let initializationVector = Data(16..<32)
        let plaintext = Data("fallback key load".utf8)
        let ciphertext = try aes128Encrypt(
            plaintext,
            key: key,
            initializationVector: initializationVector
        )
        let session = makeAES128Session()
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
                    #EXT-X-SESSION-KEY:METHOD=AES-128,URI="fallback.key"
                    #EXT-X-STREAM-INF:BANDWIDTH=1000
                    fallback-media.m3u8

                    """.utf8
                ),
                headers: [:]
            ),
            for: masterURL
        )
        HLSURLProtocol.register(
            .delayedSuccess(
                statusCode: 200,
                data: Data(
                    """
                    #EXTM3U
                    #EXT-X-KEY:METHOD=AES-128,URI="fallback.key",IV=0x101112131415161718191a1b1c1d1e1f
                    #EXTINF:1,
                    fallback.ts
                    #EXT-X-ENDLIST

                    """.utf8
                ),
                headers: [:],
                delay: 0.05
            ),
            for: mediaURL
        )
        HLSURLProtocol.register(
            .success(statusCode: 503, data: Data(), headers: [:]),
            for: keyURL
        )
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: key,
                headers: ["Content-Length": "16"]
            ),
            for: keyURL
        )
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: ciphertext,
                headers: ["Content-Length": "\(ciphertext.count)"]
            ),
            for: segmentURL
        )
        let directoryURL = try makeAES128TemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let destinationURL = directoryURL.appendingPathComponent(
            "fallback.ts"
        )

        let event = await aes128TerminalEvent(
            from: HLSDownloader(
                session: session,
                configuration: .advanced(
                    storage: HLSStoragePack(
                        diskCapacityPolicy: .disabled
                    ),
                    transfer: HLSTransferPack(
                        retryPolicy: nil,
                        sessionKeyPreloadPolicy: .identityAES128
                    )
                )
            ).download(
                sourceURL: masterURL,
                destinationURL: destinationURL
            )
        )

        guard case .completed = event else {
            Issue.record("Expected demand-key fallback to complete.")
            return
        }
        #expect(try Data(contentsOf: destinationURL) == plaintext)
        #expect(
            HLSURLProtocol.capturedRequests().count {
                $0.url == keyURL
            } == 2
        )
    }

    @Test("prepare never executes an enabled session key preload")
    func preparesSessionKeyMetadataWithoutPreloading() async throws {
        let masterURL = try #require(
            URL(string: "https://media.example/prepare-master.m3u8")
        )
        let mediaURL = try #require(
            URL(string: "https://media.example/prepare-media.m3u8")
        )
        let keyURL = try #require(
            URL(string: "https://media.example/prepare.key")
        )
        let session = makeAES128Session()
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
                    #EXT-X-SESSION-KEY:METHOD=AES-128,URI="prepare.key"
                    #EXT-X-STREAM-INF:BANDWIDTH=1000
                    prepare-media.m3u8

                    """.utf8
                ),
                headers: [:]
            ),
            for: masterURL
        )
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: Data(
                    """
                    #EXTM3U
                    #EXT-X-KEY:METHOD=AES-128,URI="prepare.key"
                    #EXTINF:1,
                    segment.ts
                    #EXT-X-ENDLIST

                    """.utf8
                ),
                headers: [:]
            ),
            for: mediaURL
        )

        let preparation = try await HLSDownloader(
            session: session,
            configuration: .advanced(
                storage: HLSStoragePack(
                    diskCapacityPolicy: .disabled
                ),
                transfer: HLSTransferPack(
                    retryPolicy: nil,
                    sessionKeyPreloadPolicy: .identityAES128
                )
            )
        ).prepare(sourceURL: masterURL)

        #expect(preparation.segmentCount == 1)
        #expect(
            HLSURLProtocol.capturedRequests().compactMap(\.url)
                == [masterURL, mediaURL]
        )
        #expect(
            !HLSURLProtocol.capturedRequests().contains {
                $0.url == keyURL
            }
        )
    }

    @Test("unused session key preload never blocks media transfer")
    func cancelsUnusedSessionKeyPreload() async throws {
        let masterURL = try #require(
            URL(string: "https://media.example/unused-master.m3u8")
        )
        let mediaURL = try #require(
            URL(string: "https://media.example/unused-media.m3u8")
        )
        let keyURL = try #require(
            URL(string: "https://media.example/unused.key")
        )
        let segmentURL = try #require(
            URL(string: "https://media.example/clear.ts")
        )
        let session = makeAES128Session()
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
                    #EXT-X-SESSION-KEY:METHOD=AES-128,URI="unused.key"
                    #EXT-X-STREAM-INF:BANDWIDTH=1000
                    unused-media.m3u8

                    """.utf8
                ),
                headers: [:]
            ),
            for: masterURL
        )
        HLSURLProtocol.register(
            .delayedSuccess(
                statusCode: 200,
                data: Data(
                    """
                    #EXTM3U
                    #EXTINF:1,
                    clear.ts
                    #EXT-X-ENDLIST

                    """.utf8
                ),
                headers: [:],
                delay: 0.05
            ),
            for: mediaURL
        )
        HLSURLProtocol.register(
            .unfinished(
                statusCode: 200,
                data: Data(0..<16),
                headers: ["Content-Length": "16"]
            ),
            for: keyURL
        )
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: Data("clear media".utf8),
                headers: [:]
            ),
            for: segmentURL
        )
        let directoryURL = try makeAES128TemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let event = await aes128TerminalEvent(
            from: HLSDownloader(
                session: session,
                configuration: .advanced(
                    storage: HLSStoragePack(
                        diskCapacityPolicy: .disabled
                    ),
                    transfer: HLSTransferPack(
                        retryPolicy: nil,
                        sessionKeyPreloadPolicy: .identityAES128
                    )
                )
            ).download(
                sourceURL: masterURL,
                destinationURL:
                    directoryURL.appendingPathComponent("clear.ts")
            )
        )

        guard case .completed = event else {
            Issue.record("An unused key preload blocked clear media.")
            return
        }
        #expect(
            HLSURLProtocol.capturedRequests().contains {
                $0.url == keyURL
            }
        )
    }

    @Test("session key preload is bounded and ignores nonidentity formats")
    func boundsSessionKeyPreloadCandidates() async throws {
        let masterURL = try #require(
            URL(string: "https://media.example/bounded-master.m3u8")
        )
        let mediaURL = try #require(
            URL(string: "https://media.example/bounded-media.m3u8")
        )
        let segmentURL = try #require(
            URL(string: "https://media.example/bounded.ts")
        )
        let identityKeyURLs = try (0..<5).map { index in
            try #require(
                URL(string: "https://media.example/key-\(index).bin")
            )
        }
        let fairPlayURL = try #require(
            URL(string: "skd://asset")
        )
        let session = makeAES128Session()
        defer {
            session.invalidateAndCancel()
            HLSURLProtocol.reset()
        }
        let keyDeclarations = (0..<5).map {
            "#EXT-X-SESSION-KEY:METHOD=AES-128,URI=\"key-\($0).bin\""
        }.joined(separator: "\n")
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: Data(
                    """
                    #EXTM3U
                    #EXT-X-VERSION:5
                    \(keyDeclarations)
                    #EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI="skd://asset",KEYFORMAT="com.apple.streamingkeydelivery"
                    #EXT-X-STREAM-INF:BANDWIDTH=1000
                    bounded-media.m3u8

                    """.utf8
                ),
                headers: [:]
            ),
            for: masterURL
        )
        HLSURLProtocol.register(
            .delayedSuccess(
                statusCode: 200,
                data: Data(
                    """
                    #EXTM3U
                    #EXTINF:1,
                    bounded.ts
                    #EXT-X-ENDLIST

                    """.utf8
                ),
                headers: [:],
                delay: 0.1
            ),
            for: mediaURL
        )
        for keyURL in identityKeyURLs {
            HLSURLProtocol.register(
                .unfinished(
                    statusCode: 200,
                    data: Data(0..<16),
                    headers: ["Content-Length": "16"]
                ),
                for: keyURL
            )
        }
        HLSURLProtocol.register(
            .success(
                statusCode: 200,
                data: Data("bounded media".utf8),
                headers: [:]
            ),
            for: segmentURL
        )
        let directoryURL = try makeAES128TemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let event = await aes128TerminalEvent(
            from: HLSDownloader(
                session: session,
                configuration: .advanced(
                    storage: HLSStoragePack(
                        diskCapacityPolicy: .disabled
                    ),
                    transfer: HLSTransferPack(
                        retryPolicy: nil,
                        sessionKeyPreloadPolicy: .identityAES128
                    )
                )
            ).download(
                sourceURL: masterURL,
                destinationURL:
                    directoryURL.appendingPathComponent("bounded.ts")
            )
        )

        guard case .completed = event else {
            Issue.record(
                "Expected bounded session-key preload to complete, got \(String(reflecting: event))."
            )
            return
        }
        let requestedURLs = Set(
            HLSURLProtocol.capturedRequests().compactMap(\.url)
        )
        #expect(
            requestedURLs.isSuperset(
                of: Set(identityKeyURLs.prefix(4))
            )
        )
        #expect(!requestedURLs.contains(identityKeyURLs[4]))
        #expect(!requestedURLs.contains(fairPlayURL))
    }

    @Test("session key preload preserves structured cancellation")
    func cancelsRequiredSessionKeyPreload() async throws {
        let keyURL = try #require(
            URL(string: "https://media.example/cancelled.key")
        )
        let keyTask = Task<Data?, Never> {
            try? await ContinuousClock().sleep(
                for: .seconds(3_600)
            )
            return Data(0..<16)
        }
        let preload = HLSAES128SessionKeyPreload(
            tasksByURL: [keyURL: keyTask]
        )
        let resolution = Task {
            try await preload.resolve(requiredKeyURLs: [keyURL])
        }
        await Task.yield()

        resolution.cancel()

        await #expect(throws: CancellationError.self) {
            try await resolution.value
        }
        #expect(keyTask.isCancelled)
    }

    @Test("media sequence numbers derive distinct AES-128 IVs")
    func derivesImplicitAES128InitializationVectors() throws {
        let sourceURL = try #require(
            URL(string: "https://media.example/encrypted.m3u8")
        )
        let playlist = try PlaylistResolver().resolve(
            """
            #EXTM3U
            #EXT-X-MEDIA-SEQUENCE:257
            #EXT-X-KEY:METHOD=AES-128,URI="key.bin"
            #EXTINF:1,
            first.ts
            #EXTINF:1,
            second.ts
            #EXT-X-ENDLIST
            """,
            relativeTo: sourceURL
        )
        let resources = try #require(playlist.media?.resources)

        #expect(
            resources.map(\.encryption?.initializationVector)
                == [
                    Data(
                        [
                            0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 1, 1,
                        ]
                    ),
                    Data(
                        [
                            0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 1, 2,
                        ]
                    ),
                ]
        )
    }

    private func directoryTextContents(
        _ directoryURL: URL
    ) throws -> String {
        let fileManager = FileManager.default
        let enumerator = try #require(
            fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        )
        var contents = ""
        for case let url as URL in enumerator {
            guard
                try url.resourceValues(
                    forKeys: [.isRegularFileKey]
                ).isRegularFile == true,
                let text = String(
                    data: try Data(contentsOf: url),
                    encoding: .utf8
                )
            else {
                continue
            }
            contents += text
        }
        return contents
    }

    private func makeAES128Session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HLSURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeAES128TemporaryDirectory() throws -> URL {
        let directoryURL =
            FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "HLSAES128Tests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }

    private func aes128TerminalEvent(
        from stream: AsyncStream<HLSDownloadEvent>
    ) async -> HLSDownloadEvent? {
        for await event in stream {
            switch event {
            case .completed, .failed, .cancelled:
                return event
            case .progress:
                continue
            }
        }
        return nil
    }
}

private func aes128Encrypt(
    _ plaintext: Data,
    key: Data,
    initializationVector: Data
) throws -> Data {
    var ciphertext = Data(
        count: plaintext.count + kCCBlockSizeAES128
    )
    let outputCapacity = ciphertext.count
    var outputLength = 0
    let status = ciphertext.withUnsafeMutableBytes { outputBytes in
        plaintext.withUnsafeBytes { plaintextBytes in
            key.withUnsafeBytes { keyBytes in
                initializationVector.withUnsafeBytes { ivBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        key.count,
                        ivBytes.baseAddress,
                        plaintextBytes.baseAddress,
                        plaintext.count,
                        outputBytes.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }
    }
    guard status == kCCSuccess else {
        throw HLSDownloadError.aes128DecryptionFailed
    }
    ciphertext.count = outputLength
    return ciphertext
}

private actor AES128ConcurrentFillGate {
    private var firstRequestStarted = false
    private var firstRequestReleased = false
    private var arrivalWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func delayFirstRequest() async {
        guard !firstRequestStarted else { return }
        firstRequestStarted = true
        arrivalWaiter?.resume()
        arrivalWaiter = nil
        if !firstRequestReleased {
            await withCheckedContinuation { releaseWaiter = $0 }
        }
    }

    func waitForFirstRequest() async {
        if !firstRequestStarted {
            await withCheckedContinuation { arrivalWaiter = $0 }
        }
    }

    func releaseFirst() {
        firstRequestReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
