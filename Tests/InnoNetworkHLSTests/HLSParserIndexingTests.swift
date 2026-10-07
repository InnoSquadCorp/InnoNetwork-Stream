import Foundation
import Testing

@testable import InnoNetworkHLS

@Suite("HLS parser indexed validation")
struct HLSParserIndexingTests {
    @Test("many groups preserve kind, membership, and variant order", arguments: [1, 128, 512])
    func manyRenditionGroups(count: Int) throws {
        let source = try #require(URL(string: "https://media.example/master.m3u8"))
        var lines = ["#EXTM3U", "#EXT-X-VERSION:7"]
        for index in 0..<count {
            let group = "g\(index)"
            lines.append("#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"\(group)\",NAME=\"Audio\"")
            lines.append("#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID=\"\(group)\",NAME=\"Video\"")
            lines.append("#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"\(group)\",NAME=\"Subtitles\",URI=\"s\(index).m3u8\"")
            lines.append("#EXT-X-MEDIA:TYPE=CLOSED-CAPTIONS,GROUP-ID=\"\(group)\",NAME=\"Captions\",INSTREAM-ID=\"CC1\"")
            lines.append(
                "#EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO=\"\(group)\",VIDEO=\"\(group)\",SUBTITLES=\"\(group)\",CLOSED-CAPTIONS=\"\(group)\""
            )
            lines.append("v\(index).m3u8")
            lines.append("#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=100,VIDEO=\"\(group)\",URI=\"i\(index).m3u8\"")
        }
        let input = lines.joined(separator: "\n")
        #expect(input.utf8.count < 512 * 1_024)
        let document = try HLSPlaylistParser().parse(input, relativeTo: source)
        guard case .multivariant(let playlist) = document else {
            Issue.record("Expected a multivariant playlist")
            return
        }
        #expect(playlist.renditions.count == count * 4)
        #expect(playlist.variants.count == count)
        #expect(playlist.iFrameVariants.count == count)
        for index in 0..<count {
            let group = "g\(index)"
            #expect(playlist.variants[index].audioGroupID == group)
            #expect(playlist.variants[index].videoGroupID == group)
            #expect(playlist.variants[index].subtitleGroupID == group)
            #expect(playlist.variants[index].closedCaptions == .group(group))
            #expect(playlist.variants[index].url.lastPathComponent == "v\(index).m3u8")
            #expect(playlist.iFrameVariants[index].videoGroupID == group)
        }
    }

    @Test(
        "a matching group name in the wrong rendition kind is rejected",
        arguments: ["AUDIO", "VIDEO", "SUBTITLES", "CLOSED-CAPTIONS", "I-FRAME-VIDEO"]
    )
    func groupKindRemainsRequired(reference: String) throws {
        let source = try #require(URL(string: "https://media.example/master.m3u8"))
        let kind = reference == "AUDIO" ? "VIDEO" : "AUDIO"
        let lines = [
            "#EXTM3U",
            "#EXT-X-MEDIA:TYPE=\(kind),GROUP-ID=\"shared\",NAME=\"Track\"",
            reference == "I-FRAME-VIDEO"
                ? "#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=100,VIDEO=\"shared\",URI=\"i.m3u8\""
                : "#EXT-X-STREAM-INF:BANDWIDTH=1000,\(reference)=\"shared\"",
            "v.m3u8",
        ]
        let renditions = try HLSMultivariantPlaylistParser.parseRenditions(lines, relativeTo: source)
        #expect(throws: HLSDownloadError.invalidPlaylist) {
            if reference == "I-FRAME-VIDEO" {
                _ = try HLSMultivariantPlaylistParser.parseIFrameVariants(
                    lines, renditions: renditions, relativeTo: source
                )
            } else {
                _ = try HLSMultivariantPlaylistParser.parseVariants(
                    lines, renditions: renditions, relativeTo: source
                )
            }
        }
    }

    @Test("many interleaved classes retain same-class timeline validation", arguments: [1, 128, 1_024])
    func manyDateRangeClasses(count: Int) throws {
        let start = Date(timeIntervalSince1970: 0)
        var ranges: [HLSDateRange] = []
        for offset in [20, 0, 10] {
            for index in 0..<count {
                ranges.append(
                    HLSDateRange(
                        id: "\(index)-\(offset)", className: "c\(index)",
                        startDate: start.addingTimeInterval(Double(offset)),
                        duration: offset == 0 ? nil : 10,
                        endsOnNext: offset == 0
                    )
                )
            }
        }
        try HLSTimelineParser.validateClassTimelines(ranges)
        // An unrelated class (or no class) can overlap these timelines.
        ranges.append(HLSDateRange(id: "unclassified", startDate: start, duration: 100))
        ranges.append(HLSDateRange(id: "unrelated", className: "other", startDate: start, duration: 100))
        try HLSTimelineParser.validateClassTimelines(ranges)
        ranges.append(
            HLSDateRange(
                id: "overlap", className: "c\(count - 1)",
                startDate: start.addingTimeInterval(15), duration: 1
            )
        )
        #expect(throws: HLSDownloadError.invalidPlaylist) {
            try HLSTimelineParser.validateClassTimelines(ranges)
        }
    }

    @Test("class validation preserves original Date Range presentation order")
    func timelinePresentationOrder() throws {
        let source = try #require(URL(string: "https://media.example/index.m3u8"))
        let input = """
            #EXTM3U
            #EXT-X-PROGRAM-DATE-TIME:2026-10-07T00:00:00Z
            #EXTINF:1,
            s.ts
            #EXT-X-ENDLIST
            #EXT-X-DATERANGE:ID="last",CLASS="chapter",START-DATE="2026-10-07T00:00:20Z",DURATION=10
            #EXT-X-DATERANGE:ID="first",CLASS="chapter",START-DATE="2026-10-07T00:00:00Z",END-ON-NEXT=YES
            #EXT-X-DATERANGE:ID="middle",CLASS="chapter",START-DATE="2026-10-07T00:00:10Z",DURATION=10
            """
        let document = try HLSPlaylistParser().parse(input, relativeTo: source)
        #expect(document.legacyPlaylist.dateRanges.map(\.id) == ["last", "first", "middle"])
    }
}
