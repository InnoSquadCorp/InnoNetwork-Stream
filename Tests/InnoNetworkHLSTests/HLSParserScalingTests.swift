import Foundation
import Testing

@testable import InnoNetworkHLS

@Suite("HLS parser scaling gate", .serialized)
struct HLSParserScalingTests {
    @Test("doubling groups and variants stays below quadratic growth", arguments: [false, true])
    func renditionGroupScaling(iFrames: Bool) throws {
        let sourceURL = try #require(URL(string: "https://media.example/master.m3u8"))
        let small = makeGroupedVariants(count: 256, iFrames: iFrames)
        let large = makeGroupedVariants(count: 512, iFrames: iFrames)
        try expectSubquadratic(
            small: {
                let variants = try parseGroupedVariants(small, iFrames: iFrames, sourceURL: sourceURL)
                #expect(variants.count == 256)
            },
            large: {
                let variants = try parseGroupedVariants(large, iFrames: iFrames, sourceURL: sourceURL)
                #expect(variants.count == 512)
            }
        )
    }

    @Test("doubling END-ON-NEXT classes stays below quadratic growth")
    func dateRangeClassScaling() throws {
        let small = makeDateRanges(classCount: 1_024)
        let large = makeDateRanges(classCount: 2_048)
        try expectSubquadratic(
            small: { try HLSTimelineParser.validateClassTimelines(small) },
            large: { try HLSTimelineParser.validateClassTimelines(large) }
        )
    }

    @Test("doubling a large playlist stays below quadratic growth")
    func nearLinearScaling() throws {
        let sourceURL = try #require(
            URL(string: "https://media.example/large.m3u8")
        )
        let resolver = PlaylistResolver()
        let small = makePlaylist(segmentCount: 400)
        let large = makePlaylist(segmentCount: 800)

        _ = try resolver.resolve(small, relativeTo: sourceURL)
        _ = try resolver.resolve(large, relativeTo: sourceURL)

        var smallSamples: [Double] = []
        var largeSamples: [Double] = []
        for sample in 0..<5 {
            if sample.isMultiple(of: 2) {
                smallSamples.append(
                    try measureBatch(
                        small,
                        segmentCount: 400,
                        resolver: resolver,
                        sourceURL: sourceURL
                    )
                )
                largeSamples.append(
                    try measureBatch(
                        large,
                        segmentCount: 800,
                        resolver: resolver,
                        sourceURL: sourceURL
                    )
                )
            } else {
                largeSamples.append(
                    try measureBatch(
                        large,
                        segmentCount: 800,
                        resolver: resolver,
                        sourceURL: sourceURL
                    )
                )
                smallSamples.append(
                    try measureBatch(
                        small,
                        segmentCount: 400,
                        resolver: resolver,
                        sourceURL: sourceURL
                    )
                )
            }
        }

        let smallMedian = median(smallSamples)
        let largeMedian = median(largeSamples)
        #expect(smallMedian > 0)
        // The ratio is the primary regression signal. This broad wall-clock
        // ceiling catches a runaway parser without coupling CI to one CPU.
        #expect(largeMedian < 10)
        #expect(largeMedian / smallMedian < 3.5)
    }

    private func makePlaylist(
        segmentCount: Int
    ) -> String {
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:9",
            "#EXT-X-TARGETDURATION:4",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:VOD",
        ]
        lines.reserveCapacity(segmentCount * 2 + 6)
        for index in 0..<segmentCount {
            lines.append("#EXTINF:4,")
            lines.append("segment-\(index).ts")
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n")
    }

    private func makeGroupedVariants(
        count: Int,
        iFrames: Bool
    ) -> (lines: [String], renditions: [HLSRendition]) {
        var lines: [String] = []
        var renditions: [HLSRendition] = []
        for index in 0..<count {
            let group = "g\(index)"
            for kind in [HLSRenditionKind.audio, .subtitles, .video, .closedCaptions] {
                renditions.append(HLSRendition(kind: kind, groupID: group, name: "Track"))
            }
            if iFrames {
                lines.append("#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=100,VIDEO=\"\(group)\",URI=\"i\(index).m3u8\"")
            } else {
                lines.append(
                    "#EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO=\"\(group)\",VIDEO=\"\(group)\",SUBTITLES=\"\(group)\",CLOSED-CAPTIONS=\"\(group)\""
                )
                lines.append("v\(index).m3u8")
            }
        }
        return (lines, renditions)
    }

    private func parseGroupedVariants(
        _ input: (lines: [String], renditions: [HLSRendition]),
        iFrames: Bool,
        sourceURL: URL
    ) throws -> [HLSVariant] {
        if iFrames {
            return try HLSMultivariantPlaylistParser.parseIFrameVariants(
                input.lines, renditions: input.renditions, relativeTo: sourceURL
            )
        }
        return try HLSMultivariantPlaylistParser.parseVariants(
            input.lines, renditions: input.renditions, relativeTo: sourceURL
        )
    }

    private func makeDateRanges(classCount: Int) -> [HLSDateRange] {
        var ranges: [HLSDateRange] = []
        for offset in [20, 0, 10] {
            for index in 0..<classCount {
                ranges.append(
                    HLSDateRange(
                        id: "\(index)-\(offset)", className: "c\(index)",
                        startDate: Date(timeIntervalSince1970: Double(offset)),
                        duration: offset == 0 ? nil : 10,
                        endsOnNext: offset == 0
                    )
                )
            }
        }
        return ranges
    }

    private func expectSubquadratic(
        small: () throws -> Void,
        large: () throws -> Void
    ) throws {
        try small()
        try large()
        var smallSamples: [Double] = []
        var largeSamples: [Double] = []
        for sample in 0..<5 {
            if sample.isMultiple(of: 2) {
                smallSamples.append(try measureBatch(small))
                largeSamples.append(try measureBatch(large))
            } else {
                largeSamples.append(try measureBatch(large))
                smallSamples.append(try measureBatch(small))
            }
        }
        let smallMedian = median(smallSamples)
        let largeMedian = median(largeSamples)
        #expect(smallMedian > 0)
        #expect(largeMedian < 10)
        #expect(largeMedian / smallMedian < 3.5)
    }

    private func measureBatch(_ operation: () throws -> Void) rethrows -> Double {
        try elapsedSeconds {
            for _ in 0..<8 {
                try operation()
            }
        }
    }

    private func measureBatch(
        _ playlist: String,
        segmentCount: Int,
        resolver: PlaylistResolver,
        sourceURL: URL
    ) throws -> Double {
        var parsedSegmentCount = 0
        let elapsed = try elapsedSeconds {
            for _ in 0..<8 {
                parsedSegmentCount =
                    try resolver.resolve(
                        playlist,
                        relativeTo: sourceURL
                    ).media?.resources.count ?? 0
            }
        }
        #expect(parsedSegmentCount == segmentCount)
        return elapsed
    }

    private func elapsedSeconds(
        _ operation: () throws -> Void
    ) rethrows -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        try operation()
        let elapsed = start.duration(to: clock.now)
        return
            Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds)
            / 1_000_000_000_000_000_000
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
