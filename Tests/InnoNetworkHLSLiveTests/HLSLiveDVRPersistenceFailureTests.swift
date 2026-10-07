import Foundation
import InnoNetworkHLS
import Testing

@testable import InnoNetworkHLSLive

@Suite("DVR checkpoint persistence failure recovery")
struct HLSLiveDVRPersistenceFailureTests {
    enum FailurePoint: CaseIterable, Equatable, Sendable {
        case resourceFileSync
        case resourceDirectorySync
        case checkpointWrite
        case checkpointFileSync
        case checkpointDirectorySync

        var replacesCheckpoint: Bool {
            self == .checkpointFileSync || self == .checkpointDirectorySync
        }
    }

    @Test("failed persistence recovers a complete checkpoint and permits retry", arguments: FailurePoint.allCases)
    func recoversAfterPersistenceFailure(at point: FailurePoint) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HLSLiveDVRPersistenceFailureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("recording", isDirectory: true)
        let source = try #require(URL(string: "https://media.example/live.m3u8"))
        let store = HLSLiveDVRCheckpointStore(destinationURL: destination)
        let workspace = try store.prepareFresh()
        let first = try writeSegment(1, in: workspace)
        let initial = checkpoint([first], source: source)
        try store.save(initial, synchronizing: initial.files)
        let checkpointURL = store.rootURL.appendingPathComponent("checkpoint.json")
        let originalData = try Data(contentsOf: checkpointURL)
        let second = try writeSegment(2, in: workspace)
        let next = checkpoint([first, second], source: source)
        let secondFile = try #require(next.files.last)

        var persistence = HLSLiveDVRCheckpointStore.Persistence()
        let synchronizeFile = persistence.synchronizeFile
        persistence.synchronizeFile = { url in
            if (point == .resourceFileSync && url.lastPathComponent == "segment-2.ts")
                || (point == .checkpointFileSync && url == checkpointURL)
            {
                throw POSIXError(.EIO)
            }
            try synchronizeFile(url)
        }
        let synchronizeDirectory = persistence.synchronizeDirectory
        persistence.synchronizeDirectory = { url in
            if (point == .resourceDirectorySync && url.lastPathComponent == "resources")
                || (point == .checkpointDirectorySync && url == store.rootURL)
            {
                throw POSIXError(.EIO)
            }
            try synchronizeDirectory(url)
        }
        let writeCheckpoint = persistence.writeCheckpoint
        persistence.writeCheckpoint = { data, url in
            if point == .checkpointWrite { throw POSIXError(.ENOSPC) }
            try writeCheckpoint(data, url)
        }
        let failing = HLSLiveDVRCheckpointStore(
            destinationURL: destination, persistence: persistence)
        #expect(throws: HLSLiveDVRError.storageFailed) {
            try failing.save(next, synchronizing: [secondFile])
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        if !point.replacesCheckpoint {
            #expect(try Data(contentsOf: checkpointURL) == originalData)
        }

        // Reconstruct the store to avoid relying on any in-memory state.
        // Post-rename fsync failures may expose the new complete checkpoint.
        // This verifies process-level recovery, not power-loss durability.
        let reopened = HLSLiveDVRCheckpointStore(destinationURL: destination)
        let (recoveredWorkspace, recovered) = try reopened.resume(sourceURL: source)
        let expectedSequences: [Int64] = point.replacesCheckpoint ? [1, 2] : [1]
        #expect(recovered.primary.segments.map(\.sequenceNumber) == expectedSequences)
        for file in recovered.files {
            let url = recoveredWorkspace.directoryURL.appendingPathComponent(file.relativePath)
            #expect(try Data(contentsOf: url).count == Int(file.byteCount))
            #expect(try HLSContentFingerprint.sha256(contentsOf: url) == file.contentSHA256)
        }
        let secondURL = recoveredWorkspace.directoryURL.appendingPathComponent("resources/segment-2.ts")
        #expect(FileManager.default.fileExists(atPath: secondURL.path) == point.replacesCheckpoint)
        #expect(try reopened.resume(sourceURL: source).1.primary.segments.map(\.sequenceNumber) == expectedSequences)

        // Repair/re-fetch an orphan removed by recovery and save normally.
        _ = try writeSegment(2, in: recoveredWorkspace)
        try reopened.save(next, synchronizing: [secondFile])
        let retried = try HLSLiveDVRCheckpointStore(destinationURL: destination).resume(sourceURL: source).1
        #expect(retried.primary.segments.map(\.sequenceNumber) == [1, 2])
        #expect(retried.files == next.files)
    }

    @Test("a missing newly staged resource does not replace the preceding checkpoint")
    func recoversAfterMissingResource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HLSLiveDVRMissingResourceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("recording", isDirectory: true)
        let source = try #require(URL(string: "https://media.example/live.m3u8"))
        let store = HLSLiveDVRCheckpointStore(destinationURL: destination)
        let workspace = try store.prepareFresh()
        let first = try writeSegment(1, in: workspace)
        let initial = checkpoint([first], source: source)
        try store.save(initial, synchronizing: initial.files)
        let second = try writeSegment(2, in: workspace)
        let next = checkpoint([first, second], source: source)
        try FileManager.default.removeItem(
            at: workspace.directoryURL.appendingPathComponent("resources/segment-2.ts"))
        // A missing file may fail URL metadata lookup before the regular-file
        // guard; either typed storage/corruption result must preserve the commit.
        let secondFile = try #require(next.files.last)
        do {
            try store.save(next, synchronizing: [secondFile])
            Issue.record("Expected missing resource persistence to fail")
        } catch let error as HLSLiveDVRError {
            #expect(error == .storageFailed || error == .recoveryCorrupted)
        }
        let recovered = try HLSLiveDVRCheckpointStore(destinationURL: destination).resume(sourceURL: source).1
        #expect(recovered.files == initial.files)
        #expect(recovered.primary.segments.map(\.sequenceNumber) == [1])
        _ = try writeSegment(2, in: workspace)
        try store.save(next, synchronizing: [secondFile])
        #expect(try store.resume(sourceURL: source).1.files == next.files)
    }

    private func writeSegment(
        _ sequence: Int64, in workspace: HLSLiveDVRWorkspace
    ) throws -> HLSLiveDVRCheckpoint.Segment {
        let path = "resources/segment-\(sequence).ts"
        let url = workspace.directoryURL.appendingPathComponent(path)
        let data = Data("media-segment-\(sequence)".utf8)
        try data.write(to: url, options: .atomic)
        return HLSLiveDVRCheckpoint.Segment(
            HLSLiveDVRStoredSegment(
                sequenceNumber: sequence, duration: 4, beginsDiscontinuity: false,
                programDateTime: nil, fileName: path, byteCount: Int64(data.count),
                contentSHA256: try HLSContentFingerprint.sha256(contentsOf: url)))
    }

    private func checkpoint(
        _ segments: [HLSLiveDVRCheckpoint.Segment], source: URL
    ) -> HLSLiveDVRCheckpoint {
        HLSLiveDVRCheckpoint(
            schemaVersion: HLSLiveDVRCheckpoint.schemaVersion,
            sourceURLSHA256: HLSLiveDVRRecoveryIdentity.sourceURLSHA256(source),
            variantIdentity: nil,
            primary: HLSLiveDVRCheckpoint.Track(
                container: "mpegTransportStream", initializationSourceIdentity: nil,
                initializationPlaylistPath: nil, initialization: nil,
                initializations: nil, segments: segments),
            renditions: [], inBandClosedCaptionIdentities: [], dateRanges: [], promotedPartCount: 0)
    }
}
