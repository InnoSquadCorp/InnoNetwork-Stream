import Foundation
import InnoNetworkHLS
import Testing

@testable import InnoNetworkHLSLive

extension HLSLivePlaylistClientTests {
    @Test("DVR coverage checks interval unions without filling shared timeline holes",
        arguments: DVRCoverageScenario.allCases)
    func validatesRetainedIntervalUnions(scenario: DVRCoverageScenario) throws {
        let fixture = try DVRTimelineFixture()
        defer { fixture.cleanup() }
        let primary = scenario.primary.enumerated().map { index, interval in
            timelineSegment(index, start: interval.0, duration: interval.1)
        }
        let audio = scenario.audio.enumerated().map { index, interval in
            timelineSegment(index, start: interval.0, duration: interval.1,
                gap: scenario == .explicitGap && index == 1)
        }
        let rendition = HLSRendition(kind: .audio, groupID: "audio", name: "Stereo")
        let selected = HLSLiveDVRSelectedRendition(
            identity: HLSLiveDVRRenditionIdentity(rendition), rendition: rendition,
            track: HLSLiveDVRTrack(kind: .audio, name: "Stereo", language: nil,
                stableID: nil, relativePlaylistPath: "audio/index.m3u8"),
            relativeDirectoryPath: "audio")
        let limits = HLSLiveDVRLimitPack(retentionPolicy: .rollingWindow)
        var state = HLSLiveDVRRecordingState(
            configuration: .advanced(limits: limits, startPosition: .currentWindow),
            workspace: HLSLiveDVRWorkspace(directoryURL: fixture.rootURL))
        state.segments = primary
        state.recordedDuration = primary.reduce(0) { $0 + $1.duration }
        state.renditionStates = [try HLSLiveDVRRenditionRecordingState(
            selection: selected,
            checkpoint: HLSLiveDVRCheckpoint.Track(
                container: "mpegTransportStream", initializationSourceIdentity: nil,
                initializationPlaylistPath: nil, initialization: nil, initializations: [],
                segments: audio.map { HLSLiveDVRCheckpoint.Segment($0) }),
            limits: limits)]
        if scenario.shouldFail {
            #expect(throws: HLSLiveDVRError.unsupportedFeature(.incompleteExternalRendition)) {
                try state.validateRenditionCoverage()
            }
        } else {
            try state.validateRenditionCoverage()
        }
    }

    @Test("An interior dated audio hole preserves the preceding resumable boundary")
    func rejectsInteriorAudioHoleWithMultipleRetainedSegments() async throws {
        let fixture = try DVRTimelineFixture()
        defer {
            fixture.cleanup()
            HLSLiveURLProtocol.reset()
        }
        let source = try timelineURL("https://media.example/union-master.m3u8")
        HLSLiveURLProtocol.register(timelinePlaylistResponse("""
            #EXTM3U
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Stereo",DEFAULT=YES,URI="union-audio.m3u8"
            #EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO="audio"
            union-video.m3u8
            """), for: source)
        for track in ["video", "audio"] {
            let secondStart = track == "audio" ? 6 : 4
            HLSLiveURLProtocol.register(timelinePlaylistResponse("""
                #EXTM3U
                #EXT-X-TARGETDURATION:4
                #EXT-X-MEDIA-SEQUENCE:0
                #EXT-X-PROGRAM-DATE-TIME:2026-09-01T00:00:00Z
                #EXTINF:4,
                union-\(track)-0.ts
                #EXT-X-DISCONTINUITY
                #EXT-X-PROGRAM-DATE-TIME:2026-09-01T00:00:0\(secondStart)Z
                #EXTINF:4,
                union-\(track)-1.ts
                #EXT-X-ENDLIST
                """), for: try timelineURL("https://media.example/union-\(track).m3u8"))
            for index in 0...1 {
                HLSLiveURLProtocol.register(timelineMediaResponse("\(track)-\(index)"),
                    for: try timelineURL("https://media.example/union-\(track)-\(index).ts"))
            }
        }
        let recorder = timelineRecorder(fixture: fixture, maximumSegmentCount: 3)
        await #expect(throws: HLSLiveDVRError.unsupportedFeature(.incompleteExternalRendition)) {
            try await recorder.record(from: source, to: fixture.destinationURL)
        }
        let store = HLSLiveDVRCheckpointStore(destinationURL: fixture.destinationURL)
        let checkpoint = try timelineCheckpoint(store)
        #expect(checkpoint.primary.segments.map(\.sequenceNumber) == [0])
        #expect(checkpoint.renditions.first?.track.segments.map(\.sequenceNumber) == [0])
        for file in checkpoint.files {
            #expect(try Data(contentsOf: store.workspace.directoryURL
                .appendingPathComponent(file.relativePath)).count == Int(file.byteCount))
        }
    }

    @Test("Packaged rolling expiry keeps metadata, files, accounting and resume coherent",
        arguments: DVRTimelineExpiryScenario.allCases)
    func rollsAndResumesPackagedTimeline(scenario: DVRTimelineExpiryScenario) async throws {
        let fixture = try DVRTimelineFixture()
        defer {
            fixture.cleanup()
            HLSLiveURLProtocol.reset()
        }
        let source = try timelineURL("https://media.example/expiry.m3u8")
        let a = timelineEvent("a", start: 0, ending: scenario.attributes)
        let b = timelineEvent("b", start: 4)
        try registerTimelineAsset("a")
        try registerTimelineAsset("b")
        HLSLiveURLProtocol.register(timelinePlaylistResponse(
            timelinePrimary(sequence: 0, start: 0, ranges: a)), for: source)
        HLSLiveURLProtocol.register(timelineMediaResponse("primary-0"),
            for: try timelineURL("https://media.example/timeline-0.ts"))
        let recorder = timelineRecorder(fixture: fixture)
        let first = recorder.startRecording(from: source, to: fixture.destinationURL)
        var firstEvents = first.events.makeAsyncIterator()
        guard case .progress = try await firstEvents.next() else {
            Issue.record("Expected the first durable event boundary")
            return
        }
        await first.interrupt()
        let store = HLSLiveDVRCheckpointStore(destinationURL: fixture.destinationURL)
        let before = try timelineCheckpoint(store)
        let aRecord = try #require(before.interstitials?.first { $0.id == "a" })

        HLSLiveURLProtocol.register(timelinePlaylistResponse(
            timelinePrimary(sequence: 1, start: 4, ranges: a + "\n" + b)), for: source)
        HLSLiveURLProtocol.register(timelineMediaResponse("primary-1"),
            for: try timelineURL("https://media.example/timeline-1.ts"))
        let second = recorder.resumeRecording(from: source, to: fixture.destinationURL)
        var secondEvents = second.events.makeAsyncIterator()
        guard case .progress(let progress) = try await secondEvents.next() else {
            Issue.record("Expected the rolled durable event boundary")
            return
        }
        await second.interrupt()
        let expectedIDs: Set<String> = scenario.expires ? ["b"] : ["a", "b"]
        let after = try timelineCheckpoint(store)
        #expect(Set(after.interstitials?.map(\.id) ?? []) == expectedIDs)
        #expect(Set(after.dateRanges.map(\.id)) == expectedIDs)
        #expect(progress.interstitialStatistics.retainedEventCount == expectedIDs.count)
        let interstitialBytes = (after.interstitials ?? []).flatMap(\.files)
            .reduce(Int64(0)) { $0 + $1.byteCount }
        #expect(progress.interstitialStatistics.retainedByteCount == interstitialBytes)
        #expect(progress.mediaByteCount == after.files.reduce(Int64(0)) { $0 + $1.byteCount })
        #expect(FileManager.default.fileExists(atPath: store.workspace.directoryURL
            .appendingPathComponent(aRecord.eventDirectoryPath).path) == !scenario.expires)
        #expect(progress.retentionStatistics.evictedMediaByteCount
            == Int64("primary-0".utf8.count)
                + (scenario.expires ? aRecord.files.reduce(Int64(0)) { $0 + $1.byteCount } : 0))

        // Repeated expired source metadata must not repackage A into its
        // former directory or put an orphan record back into the checkpoint.
        HLSLiveURLProtocol.register(timelinePlaylistResponse(
            timelinePrimary(sequence: 1, start: 4, ranges: a + "\n" + b, ended: true)),
            for: source)
        let receipt = try await recorder.resume(from: source, to: fixture.destinationURL)
        #expect(receipt.interstitialStatistics.retainedEventCount == expectedIDs.count)
        #expect(receipt.firstMediaSequence == 1)
        for name in ["a", "b"] {
            let asset = try timelineURL("https://ads.example/timeline-\(name).m3u8")
            #expect(HLSLiveURLProtocol.capturedRequests().filter { $0.url == asset }.count == 1)
        }
        _ = try HLSLocalPlaybackPackageSnapshot(source: receipt.playbackSource)
    }

    @Test("Metadata-only expiry checkpoints before deleting old files when commit fails")
    func checkpointsMetadataOnlyExpiryBeforeFailedCommit() async throws {
        let fixture = try DVRTimelineFixture()
        defer {
            fixture.cleanup()
            HLSLiveURLProtocol.reset()
        }
        let source = try timelineURL("https://media.example/metadata-only.m3u8")
        let a = timelineEvent("a", start: 0, ending: "END-ON-NEXT=YES")
        let b = timelineEvent("b", start: 4)
        try registerTimelineAsset("a")
        try registerTimelineAsset("b")
        HLSLiveURLProtocol.register(timelinePlaylistResponse(
            timelinePrimary(sequence: 1, start: 4, ranges: a)), for: source)
        HLSLiveURLProtocol.register(timelineMediaResponse("primary-1"),
            for: try timelineURL("https://media.example/timeline-1.ts"))
        let recorder = timelineRecorder(fixture: fixture)
        let first = recorder.startRecording(from: source, to: fixture.destinationURL)
        var events = first.events.makeAsyncIterator()
        guard case .progress = try await events.next() else {
            Issue.record("Expected the open event checkpoint")
            return
        }
        await first.interrupt()
        let store = HLSLiveDVRCheckpointStore(destinationURL: fixture.destinationURL)
        let oldCheckpoint = try timelineCheckpoint(store)
        let oldEvent = try #require(oldCheckpoint.interstitials?.first)
        let destination = fixture.destinationURL
        let bAsset = try timelineURL("https://ads.example/timeline-b.m3u8")
        let failingRecorder = timelineRecorder(fixture: fixture,
            requestPolicy: HLSRequestPolicy { request, _ in
                if request.url == bAsset {
                    // A has expired in memory, but the durable old checkpoint
                    // must still be readable until the new one is installed.
                    for file in oldCheckpoint.files {
                        #expect(FileManager.default.fileExists(atPath:
                            store.workspace.directoryURL.appendingPathComponent(file.relativePath).path))
                    }
                    try FileManager.default.createDirectory(at: destination,
                        withIntermediateDirectories: false)
                }
                return request
            })
        let ended = timelinePrimary(sequence: 1, start: 4, ranges: a + "\n" + b, ended: true)
        HLSLiveURLProtocol.register(timelinePlaylistResponse(ended), for: source)
        await #expect(throws: HLSLiveDVRError.destinationAlreadyExists) {
            try await failingRecorder.resume(from: source, to: destination)
        }
        let current = try timelineCheckpoint(store)
        #expect(current.primary.segments.map(\.sequenceNumber) == [1])
        #expect(current.interstitials?.map(\.id) == ["b"])
        #expect(current.dateRanges.map(\.id) == ["b"])
        #expect(!FileManager.default.fileExists(atPath: store.workspace.directoryURL
            .appendingPathComponent(oldEvent.eventDirectoryPath).path))
        try FileManager.default.removeItem(at: destination)
        HLSLiveURLProtocol.register(timelinePlaylistResponse(ended), for: source)
        let receipt = try await recorder.resume(from: source, to: destination)
        #expect(receipt.interstitialStatistics.retainedEventCount == 1)
        _ = try HLSLocalPlaybackPackageSnapshot(source: receipt.playbackSource)
    }

    @Test("A first-boundary checkpoint retains eagerly packaged future event metadata")
    func resumesFutureInterstitialFromFirstBoundary() async throws {
        let fixture = try DVRTimelineFixture()
        defer {
            fixture.cleanup()
            HLSLiveURLProtocol.reset()
        }
        let source = try timelineURL("https://media.example/future-event.m3u8")
        let ranges = timelineEvent("a", start: 0, ending: "END-ON-NEXT=YES")
            + "\n" + timelineEvent("b", start: 4)
        try registerTimelineAsset("a")
        try registerTimelineAsset("b")
        let playlist = timelinePrimary(sequence: 0, start: 0, ranges: ranges)
            + "\n#EXTINF:4,\ntimeline-1.ts\n#EXT-X-ENDLIST"
        HLSLiveURLProtocol.register(timelinePlaylistResponse(playlist), for: source)
        HLSLiveURLProtocol.register(timelineMediaResponse("primary-0"),
            for: try timelineURL("https://media.example/timeline-0.ts"))
        let secondURL = try timelineURL("https://media.example/timeline-1.ts")
        // A deterministic transfer failure stops immediately after the first
        // checkpoint, without racing the asynchronous progress consumer.
        HLSLiveURLProtocol.register(HLSLiveURLProtocol.Response(
            statusCode: 404, data: Data(), headers: [:]), for: secondURL)
        let recorder = timelineRecorder(fixture: fixture, maximumSegmentCount: 2)
        await #expect(throws: HLSLiveDVRError.invalidMediaResponseStatus(404)) {
            try await recorder.record(from: source, to: fixture.destinationURL)
        }
        let store = HLSLiveDVRCheckpointStore(destinationURL: fixture.destinationURL)
        let checkpoint = try timelineCheckpoint(store)
        #expect(checkpoint.primary.segments.map(\.sequenceNumber) == [0])
        #expect(Set(checkpoint.dateRanges.map(\.id)) == ["a", "b"])
        let future = try #require(checkpoint.interstitials?.first { $0.id == "b" })
        #expect(!future.files.isEmpty)
        HLSLiveURLProtocol.register(timelinePlaylistResponse(playlist), for: source)
        HLSLiveURLProtocol.register(timelineMediaResponse("primary-1"), for: secondURL)
        let receipt = try await recorder.resume(from: source, to: fixture.destinationURL)
        #expect(receipt.segmentCount == 2)
        #expect(receipt.interstitialStatistics.retainedEventCount == 2)
        for file in future.files {
            #expect(try Data(contentsOf: receipt.directoryURL
                .appendingPathComponent(file.relativePath)).count == Int(file.byteCount))
        }
        let futureAsset = try timelineURL("https://ads.example/timeline-b.m3u8")
        #expect(HLSLiveURLProtocol.capturedRequests().filter { $0.url == futureAsset }.count == 1)
        _ = try HLSLocalPlaybackPackageSnapshot(source: receipt.playbackSource)
    }

    private func timelineSegment(
        _ index: Int, start: Double?, duration: Double, gap: Bool = false
    ) -> HLSLiveDVRStoredSegment {
        let date = start.map { Date(timeIntervalSinceReferenceDate: $0) }
        if gap {
            return .gap(sequenceNumber: Int64(index), duration: duration,
                beginsDiscontinuity: index > 0, programDateTime: date,
                initializationSourceIdentity: nil, initializationFileName: nil,
                fileName: "resources/gap-\(index).ts")
        }
        return HLSLiveDVRStoredSegment(sequenceNumber: Int64(index), duration: duration,
            beginsDiscontinuity: index > 0, programDateTime: date,
            fileName: "resources/segment-\(index).ts", byteCount: 1,
            contentSHA256: String(repeating: "0", count: 64))
    }

    private func timelineRecorder(
        fixture: DVRTimelineFixture,
        maximumSegmentCount: Int = 1,
        requestPolicy: HLSRequestPolicy = HLSRequestPolicy()
    ) -> HLSLiveDVRRecorder {
        HLSLiveDVRRecorder(
            client: HLSLivePlaylistClient(session: fixture.session, requestPolicy: requestPolicy),
            configuration: .advanced(
                limits: HLSLiveDVRLimitPack(maximumDuration: 60,
                    maximumSegmentCount: maximumSegmentCount, maximumMediaResourceBytes: 1_024,
                    maximumTotalMediaBytes: 64 * 1_024, retentionPolicy: .rollingWindow),
                startPosition: .currentWindow,
                recovery: HLSLiveDVRRecoveryPack(policy: .resumable),
                interstitials: HLSLiveDVRInterstitialPack(policy: .package)))
    }

    private func timelineCheckpoint(_ store: HLSLiveDVRCheckpointStore) throws -> HLSLiveDVRCheckpoint {
        try JSONDecoder().decode(HLSLiveDVRCheckpoint.self,
            from: Data(contentsOf: store.rootURL.appendingPathComponent("checkpoint.json")))
    }

    private func timelinePrimary(
        sequence: Int, start: Int, ranges: String, ended: Bool = false
    ) -> String {
        """
        #EXTM3U
        #EXT-X-TARGETDURATION:60
        #EXT-X-MEDIA-SEQUENCE:\(sequence)
        #EXT-X-PROGRAM-DATE-TIME:2026-09-01T00:00:0\(start)Z
        \(ranges)
        #EXTINF:4,
        timeline-\(sequence).ts
        \(ended ? "#EXT-X-ENDLIST" : "")
        """
    }

    private func timelineEvent(_ id: String, start: Int, ending: String = "") -> String {
        let suffix = ending.isEmpty ? "" : "," + ending
        return "#EXT-X-DATERANGE:ID=\"\(id)\",CLASS=\"com.apple.hls.interstitial\",START-DATE=\"2026-09-01T00:00:0\(start)Z\",X-ASSET-URI=\"https://ads.example/timeline-\(id).m3u8\"\(suffix)"
    }

    private func registerTimelineAsset(_ id: String) throws {
        HLSLiveURLProtocol.register(timelinePlaylistResponse("""
            #EXTM3U
            #EXT-X-TARGETDURATION:4
            #EXTINF:4,
            timeline-\(id).ts
            #EXT-X-ENDLIST
            """), for: try timelineURL("https://ads.example/timeline-\(id).m3u8"))
        HLSLiveURLProtocol.register(timelineMediaResponse("event-\(id)"),
            for: try timelineURL("https://ads.example/timeline-\(id).ts"))
    }

    private func timelinePlaylistResponse(_ value: String) -> HLSLiveURLProtocol.Response {
        HLSLiveURLProtocol.Response(statusCode: 200, data: Data(value.utf8),
            headers: ["Content-Type": "application/vnd.apple.mpegurl"])
    }

    private func timelineMediaResponse(_ value: String) -> HLSLiveURLProtocol.Response {
        HLSLiveURLProtocol.Response(statusCode: 200, data: Data(value.utf8),
            headers: ["Content-Length": "\(value.utf8.count)", "Content-Type": "application/octet-stream"])
    }

    private func timelineURL(_ value: String) throws -> URL {
        try #require(URL(string: value))
    }
}

enum DVRCoverageScenario: CaseIterable, Sendable {
    case internalHole, holeAcrossPrimaryBoundary, alignedHole, overlap, reverseDates
    case roundingTolerance, excessTolerance, explicitGap, partialDates, partialShort, partialShifted

    var primary: [(Double?, Double)] {
        switch self {
        case .alignedHole: [(0, 4), (6, 4)]
        case .partialDates, .partialShort, .partialShifted: [(0, 4), (nil, 4), (8, 4)]
        default: [(0, 4), (4, 4)]
        }
    }

    var audio: [(Double?, Double)] {
        switch self {
        case .internalHole: [(0, 4), (6, 4)]
        case .holeAcrossPrimaryBoundary: [(0, 3.6), (4.4, 3.6)]
        case .alignedHole: [(0, 4), (6, 4)]
        case .overlap: [(0, 6), (4, 4)]
        case .reverseDates: [(4, 4), (0, 4)]
        case .roundingTolerance: [(0.5, 3.25), (4.25, 3.25)]
        case .excessTolerance: [(0, 3.749), (4.251, 3.749)]
        case .explicitGap: [(0, 4), (4, 4)]
        case .partialDates: [(0, 4), (nil, 4), (8, 4)]
        case .partialShort: [(0, 4), (nil, 4)]
        case .partialShifted: [(4, 4), (nil, 4), (12, 4)]
        }
    }

    var shouldFail: Bool {
        switch self {
        case .internalHole, .holeAcrossPrimaryBoundary, .excessTolerance, .partialShort, .partialShifted: true
        default: false
        }
    }
}

enum DVRTimelineExpiryScenario: CaseIterable, Sendable {
    case endOnNext, explicitEnd, duration, overlap, open

    var attributes: String {
        switch self {
        case .endOnNext: "END-ON-NEXT=YES"
        case .explicitEnd: "END-DATE=\"2026-09-01T00:00:04Z\""
        case .duration: "DURATION=4"
        case .overlap: "DURATION=12"
        case .open: ""
        }
    }

    var expires: Bool {
        switch self {
        case .endOnNext, .explicitEnd, .duration: true
        case .overlap, .open: false
        }
    }
}

private struct DVRTimelineFixture {
    let rootURL: URL
    let destinationURL: URL
    let session: URLSession

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InnoNetwork-DVRTimeline-\(UUID().uuidString)", isDirectory: true)
        destinationURL = rootURL.appendingPathComponent("recording", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HLSLiveURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    func cleanup() {
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: rootURL)
    }
}
