import Foundation
import InnoNetworkHLS
import Testing

@testable import InnoNetworkHLSLive

@HLSLiveDefinition(minimumPollingMilliseconds: 50, maximumPollingMilliseconds: 100, requestTimeoutSeconds: 1)
private enum TestWatch {}
@HLSDVRDefinition(
    maximumDurationSeconds: 5, maximumSegmentCount: 1, maximumMediaResourceBytes: 1024, maximumTotalMediaBytes: 2048)
private enum TestRecording {}

@Suite("Live workflow definitions", .serialized)
struct HLSWorkflowTests {
    @Test("DVR recovery advice distinguishes checkpoint, authorization and input")
    func failureAdvice() {
        #expect(
            HLSFailureReport.classify(HLSLiveDVRError.transferFailed, backend: .liveDVR).recovery
                == .resumeSubjectToCheckpoint)
        #expect(
            HLSFailureReport.classify(HLSLiveDVRError.invalidMediaResponseStatus(404), backend: .liveDVR).recovery
                == .inspectInput)
        #expect(
            HLSFailureReport.classify(HLSLiveDVRError.invalidMediaResponseStatus(401), backend: .liveDVR).recovery
                == .provideFreshAuthorization)
        #expect(
            HLSFailureReport.classify(HLSLiveConfigurationError.invalidReloadTiming, backend: .liveWatch).category
                == .configuration)
    }
    @Test("macro and dynamic validation expose the same accepted effective settings")
    func settings() throws {
        #expect(try TestWatch.configuration().minimumPollingInterval == 0.05)
        #expect(try TestWatch.configuration().maximumPollingInterval == 0.1)
        #expect(try TestRecording.configuration().effectiveLimits.maximumSegmentCount == 1)
        #expect(throws: HLSLiveConfigurationError.invalidReloadTiming) {
            try HLSLiveConfiguration.validated(minimumPollingMilliseconds: 0)
        }
        #expect(throws: HLSLiveConfigurationError.invalidReloadTiming) {
            try HLSLiveConfiguration.validated(maximumPollingMilliseconds: 50)
        }
        #expect(throws: HLSLiveConfigurationError.invalidRecordingLimits) {
            try HLSLiveDVRConfiguration.validated(maximumMediaResourceBytes: 2, maximumTotalMediaBytes: 1)
        }
        #expect(throws: HLSLiveConfigurationError.invalidRecordingLimits) {
            try HLSLiveDVRConfiguration.validated(maximumDurationSeconds: Int.max)
        }
    }

}

// Every user of the shared response/request registry belongs to the same
// serialized suite, not merely a different suite also marked serialized.
extension HLSLivePlaylistClientTests {
    @Test("watch finishes with zero observers and independently replays to two late observers")
    func watch() async throws {
        let url = try #require(URL(string: "https://workflow.example/end.m3u8"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HLSLiveURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            HLSLiveURLProtocol.reset()
        }
        let text = "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\nsegment.ts\n#EXT-X-ENDLIST\n"
        HLSLiveURLProtocol.register(.init(statusCode: 200, data: Data(text.utf8), headers: [:]), for: url)
        let handle = try TestWatch.watch(from: url, session: session)
        let final = try await handle.finalSnapshot()
        #expect(final.playlist.sourceURL == url)
        #expect(handle.state == .completed)
        for _ in 0..<2 {
            let observed = try await handle.observations().reduce(into: []) { $0.append($1) }
            #expect(observed.count == 1)
            #expect(observed.first?.operationID == handle.id)
        }
    }
}
