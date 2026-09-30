import Foundation
import Testing

@testable import InnoNetworkHLS

@Suite("HLS hostile input limits")
struct HLSInputLimitTests {
    @Test("finite durations beyond Int range produce advisory diagnostics")
    func hugeAuthoringDuration() throws {
        let source = try #require(URL(string: "https://media.example/index.m3u8"))
        for duration in ["5", "1e100"] {
            let inspection = PlaylistResolver().inspect(
                "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:\(duration),\nsegment.ts\n#EXT-X-ENDLIST\n",
                relativeTo: source,
                using: .appleAuthoring
            )
            #expect(
                inspection.diagnostics.contains {
                    $0.code == .appleSegmentExceedsTargetDuration
                })
        }
    }

    @Test("URI and quoted attribute expansion are bounded before append", arguments: [false, true])
    func repeatedVariableIsBounded(attribute: Bool) throws {
        let source = try #require(URL(string: "https://media.example/index.m3u8"))
        let value = String(repeating: "a", count: 64 * 1_024)
        let references = String(repeating: "{$v}", count: 1_000)
        let line = attribute ? "#EXT-X-MAP:URI=\"\(references)\"" : references
        let input = "#EXTM3U\n#EXT-X-DEFINE:NAME=\"v\",VALUE=\"\(value)\"\n\(line)\n"
        #expect(throws: HLSDownloadError.playlistTooLarge(limit: 2 * 1_024 * 1_024)) {
            try HLSVariableSubstituter.expand(
                input,
                sourceURL: source,
                multivariantVariables: nil,
                maximumBytes: 2 * 1_024 * 1_024
            )
        }
    }

    @Test("expansion accounts for UTF8 and newline at exact boundaries", arguments: [false, true])
    func expansionBoundary(attribute: Bool) throws {
        let source = try #require(URL(string: "https://media.example/index.m3u8"))
        let line = attribute ? "#EXT-X-MAP:URI=\"{$v}\"" : "{$v}"
        let expanded = attribute ? "#EXT-X-MAP:URI=\"🎬🎬\"" : "🎬🎬"
        let input = "#EXTM3U\n#EXT-X-DEFINE:NAME=\"v\",VALUE=\"🎬🎬\"\n\(line)"
        let expected = "#EXTM3U\n\(expanded)\n"
        let limit = expected.utf8.count
        let result = try HLSVariableSubstituter.expand(
            input, sourceURL: source, multivariantVariables: nil, maximumBytes: limit
        )
        #expect(result.contents == expected)
        #expect(throws: HLSDownloadError.playlistTooLarge(limit: limit - 1)) {
            try HLSVariableSubstituter.expand(
                input, sourceURL: source, multivariantVariables: nil, maximumBytes: limit - 1
            )
        }
    }
}
