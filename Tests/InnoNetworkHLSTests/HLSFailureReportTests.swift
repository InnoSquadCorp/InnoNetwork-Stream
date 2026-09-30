import Foundation
import Testing

@testable import InnoNetworkHLS

@Suite("Structured failures and export-safe incidents")
struct HLSFailureReportTests {
    @Test("HTTP recovery remains subject to caller policy and stable error codes")
    func recovery() {
        let unauthorized = HLSDownloadError.invalidResponseStatus(401)
        let report = HLSFailureReport.classify(unauthorized, backend: .singleFileDownload)
        #expect(report.category == .authorization)
        #expect(report.recovery == .provideFreshAuthorization)
        #expect(report.legacyHLSCode == (unauthorized as NSError).code)
        #expect(
            HLSFailureReport.classify(HLSDownloadError.invalidResponseStatus(503), backend: .liveWatch).recovery
                == .retrySubjectToRequestPolicy)
        #expect(
            HLSFailureReport.classify(HLSDownloadError.invalidResponseStatus(404), backend: .liveWatch).recovery
                == .inspectInput)
        #expect(HLSFailureReport.classify(CancellationError(), backend: .liveDVR).recovery == .none)
        #expect(HLSBackendCapabilities.forBackend(.liveDVR).supportsCheckpointRecovery)
        #expect(!HLSBackendCapabilities.forBackend(.singleFileDownload).supportsCheckpointRecovery)
        #expect(HLSBackendCapabilities.forBackend(.nativeBackgroundDownload).ownership == .systemManaged)
        #expect(HLSBackendCapabilities.forBackend(.nativeBackgroundDownload).supportsSystemRestoration)
        #expect(HLSBackendCapabilities.forBackend(.decodedAudio).ownership == .realtime)
        #expect(
            HLSFailureReport.classify(URLError(.timedOut), backend: .nativeBackgroundDownload).recovery
                == .restoreNativeTasks)
        let legacy = HLSDownloadError.byteRangePlaylistUnsupported
        #expect(HLSFailureReport.classify(legacy, backend: .singleFileDownload).legacyHLSCode == legacy.errorCode)
    }

    @Test("typed parse failure does not invent source-position or feature support")
    func parsing() throws {
        let url = try #require(URL(string: "https://user:password@host/secret-path?token=secret#private"))
        let parser = try HLSPlaylistParser()
        guard case .failure(let failure) = parser.inspect("not a playlist", relativeTo: url) else {
            Issue.record("Expected parse failure")
            return
        }
        #expect(failure.category == .invalidInput)
        #expect(failure.backend == .playlistInspection)
        guard case .success = parser.inspect("#EXTM3U\n#EXTINF:1,\nsegment.ts\n#EXT-X-ENDLIST\n", relativeTo: url)
        else {
            Issue.record("Expected control to parse")
            return
        }
    }

    @Test("bounded incident exports contain neither URLs nor arbitrary error text or domains")
    func redaction() async throws {
        let id = UUID()
        let buffer = try HLSIncidentBuffer(operationID: id, maximumRecords: 2)
        let secrets = [
            "secret-domain", "secret-key-bytes", "Bearer secret-token",
            "https://user:password@host/private?token=secret#private", "/private/user/movie.ts",
        ]
        let untrusted = NSError(
            domain: secrets[0], code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: secrets[1], "Authorization": secrets[2],
                NSURLErrorFailingURLStringErrorKey: secrets[3], NSFilePathErrorKey: secrets[4],
            ])
        let report = HLSFailureReport.classify(untrusted, backend: .nativeBackgroundDownload, operationID: id)
        #expect(report.category == .unknown)
        #expect(report.legacyHLSCode == nil)
        try await buffer.record(.starting)
        try await buffer.record(.planning)
        try await buffer.record(.failed, failure: report)
        let snapshot = await buffer.snapshot()
        #expect(snapshot.records.map(\.sequence) == [2, 3])
        #expect(snapshot.droppedRecordCount == 1)
        #expect(snapshot.isTruncated)
        let exported = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        for secret in secrets { #expect(!exported.contains(secret)) }
        let foreign = HLSFailureReport.classify(CancellationError(), backend: .liveWatch, operationID: UUID())
        await #expect(throws: HLSIncidentError.mismatchedOperation) {
            try await buffer.record(.cancelled, failure: foreign)
        }
        #expect(await buffer.snapshot() == snapshot)
        #expect(throws: HLSIncidentError.invalidCapacity) {
            try HLSIncidentBuffer(operationID: id, maximumRecords: 129)
        }
        let encrypted = HLSFailureReport.classify(
            HLSDownloadError.encryptedPlaylistUnsupported(method: "secret-method"), backend: .singleFileDownload)
        #expect(!String(decoding: try JSONEncoder().encode(encrypted), as: UTF8.self).contains("secret-method"))
    }
}
