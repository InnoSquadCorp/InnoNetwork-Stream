import Foundation
import Testing

@testable import InnoNetworkHLS

@Suite("Pure discriminated playlist documents")
struct HLSPlaylistParserTests {
    let source = URL(string: "https://user:secret@media.example/index.m3u8?token=private")!

    @Test("multivariant metadata is lossless across legacy projection")
    func multivariantProjection() throws {
        let text = """
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-INDEPENDENT-SEGMENTS
            #EXT-X-SESSION-DATA:DATA-ID="org.example.title",VALUE="Movie"
            #EXT-X-START:TIME-OFFSET=1.5,PRECISE=YES
            #EXT-X-STREAM-INF:BANDWIDTH=100000,CODECS="avc1.42e01e"
            video.m3u8
            """
        let document = try HLSPlaylistParser().parse(text, relativeTo: source)
        guard case .multivariant(let master) = document else {
            Issue.record("wrong kind")
            return
        }
        #expect(master.variants.count == 1)
        #expect(master.sessionData.count == 1)
        #expect(master.hasIndependentSegments)
        #expect(master.preferredStartPosition != nil)
        #expect(VariantSelector().highestQuality(in: master) == master.variants.first)
        #expect(document.legacyPlaylist == (try PlaylistResolver().resolve(text, relativeTo: source)))
        #expect(document.sourceURL == source)
    }

    @Test("contradictory internal fixtures cannot enter validated planning")
    func contradictoryLegacyValue() throws {
        let invalid = HLSPlaylist(sourceURL: source, kind: .multivariant, variants: [], mediaContainer: .fragmentedMP4)
        #expect(throws: HLSDownloadError.invalidPlaylist) { try HLSPlaylistDocument(parsed: invalid) }
        let mediaWithoutTimeline = HLSPlaylist(sourceURL: source, kind: .media, variants: [])
        #expect(throws: HLSDownloadError.invalidPlaylist) { try HLSPlaylistDocument(parsed: mediaWithoutTimeline) }
    }

    @Test("media inspection does not assert execution support", arguments: [false, true])
    func mediaEligibility(ended: Bool) throws {
        let text =
            "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:11\n#EXTINF:4,\nvideo.ts\n"
            + (ended ? "#EXT-X-ENDLIST\n" : "")
        let document = try HLSPlaylistParser().parse(text, relativeTo: source)
        guard case .media(let media) = document else {
            Issue.record("wrong kind")
            return
        }
        #expect(media.mediaSequence == 11)
        #expect(media.segmentCount == 1)
        #expect(media.hasEndList == ended)
        #expect(document.legacyPlaylist == (try PlaylistResolver().resolve(text, relativeTo: source)))
        if ended {
            try media.validateSingleFileDownload()
        } else {
            #expect(throws: HLSDownloadError.livePlaylistUnsupported) { try media.validateSingleFileDownload() }
        }
    }

    @Test("pure parser keeps bounded input and import context explicit")
    func inputLimits() throws {
        #expect(throws: HLSConfigurationError.invalidPlaylistByteLimit) {
            try HLSPlaylistParser(maximumPlaylistBytes: 0)
        }
        // The established expansion contract appends a terminal newline.
        let input = "#EXTM3U"
        let limit = input.utf8.count + 1
        let parser = try HLSPlaylistParser(maximumPlaylistBytes: limit)
        _ = try parser.parse(input, relativeTo: source)
        #expect(throws: HLSDownloadError.playlistTooLarge(limit: limit)) {
            try parser.parse(input + "xx", relativeTo: source)
        }
        let imported = """
            #EXTM3U
            #EXT-X-VERSION:8
            #EXT-X-DEFINE:IMPORT="track"
            #EXTINF:4,
            {$track}
            #EXT-X-ENDLIST
            """
        let document = try HLSPlaylistParser().parse(
            imported, relativeTo: source, multivariantVariables: ["track": "video.ts"])
        guard case .media(let media) = document else {
            Issue.record("wrong kind")
            return
        }
        try media.validateSingleFileDownload()
        #expect(throws: HLSDownloadError.invalidPlaylist) {
            try HLSPlaylistParser().parse(imported, relativeTo: source)
        }
    }
}
