import Foundation
import Testing

@testable import InnoNetworkHLS

@Suite("HLS hostile input limits")
struct HLSInputLimitTests {
    @Test("normalized output charges actual LF bytes and omits terminal blank lines")
    func normalizedLineBoundaries() throws {
        let source = try #require(URL(string: "https://media.example/index.m3u8"))
        let expected = "#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\ns.ts\n#EXT-X-ENDLIST\n"
        let limit = expected.utf8.count
        #expect(limit == 63)
        let inputs = [
            String(expected.dropLast()),
            expected,
            expected + "\n\n",
            expected.replacingOccurrences(of: "\n", with: "\r\n"),
            expected.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n\r\n",
        ]
        for input in inputs {
            let expansion = try HLSVariableSubstituter.expand(
                input, sourceURL: source, multivariantVariables: nil, maximumBytes: limit
            )
            #expect(expansion.contents == expected)
            #expect(expansion.contents.utf8.count == limit)
            #expect(throws: HLSDownloadError.playlistTooLarge(limit: limit - 1)) {
                try HLSVariableSubstituter.expand(
                    input, sourceURL: source, multivariantVariables: nil, maximumBytes: limit - 1
                )
            }
            // The public parser independently bounds raw input, including CRLF
            // and trailing blanks, before it normalizes or removes anything.
            let parser = try HLSPlaylistParser(maximumPlaylistBytes: max(limit, input.utf8.count))
            let document = try parser.parse(input, relativeTo: source)
            #expect(document.legacyPlaylist.media?.segmentCount == 1)
            if input.utf8.count > limit {
                #expect(throws: HLSDownloadError.playlistTooLarge(limit: limit)) {
                    try HLSPlaylistParser(maximumPlaylistBytes: limit).parse(input, relativeTo: source)
                }
            }
        }
        #expect(throws: HLSDownloadError.playlistTooLarge(limit: limit - 1)) {
            try HLSPlaylistParser(maximumPlaylistBytes: limit - 1).parse(
                String(expected.dropLast()), relativeTo: source
            )
        }
    }

    @Test("interior blanks count but blanks before trailing definitions do not")
    func interiorAndTrailingDefinitionBlanks() throws {
        let source = try #require(URL(string: "https://media.example/index.m3u8"))
        let input = "#EXTM3U\r\n\r\n🎬.ts\r\n\r\n#EXT-X-DEFINE:NAME=\"v\",VALUE=\"\"\r\n"
        let expected = "#EXTM3U\n\n🎬.ts\n"
        let limit = expected.utf8.count
        let expansion = try HLSVariableSubstituter.expand(
            input, sourceURL: source, multivariantVariables: nil, maximumBytes: limit
        )
        #expect(expansion.contents == expected)
        #expect(expansion.contents.utf8.count == limit)
        #expect(expansion.variables == ["v": ""])
        #expect(throws: HLSDownloadError.playlistTooLarge(limit: limit - 1)) {
            try HLSVariableSubstituter.expand(
                input, sourceURL: source, multivariantVariables: nil, maximumBytes: limit - 1
            )
        }
    }

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

    @Test("URI and attribute expansion are bounded before append", arguments: ["uri", "quoted", "hexadecimal"])
    func repeatedVariableIsBounded(position: String) throws {
        let source = try #require(URL(string: "https://media.example/index.m3u8"))
        let value = String(repeating: "a", count: 64 * 1_024)
        let references = String(repeating: "{$v}", count: 1_000)
        let line: String
        switch position {
        case "quoted":
            line = "#EXT-X-MAP:URI=\"\(references)\""
        case "hexadecimal":
            line = "#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\",IV=0x\(references)"
        default:
            line = references
        }
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

    @Test("hexadecimal attribute expansion includes field and whitespace bytes")
    func hexadecimalExpansionBoundary() throws {
        let source = try #require(URL(string: "https://media.example/index.m3u8"))
        let value = "0x" + String(repeating: "A", count: 32)
        let input = """
            #EXTM3U
            #EXT-X-DEFINE:NAME="iv",VALUE="\(value)"
            #EXT-X-KEY:METHOD=AES-128,IV=  {$iv}  ,URI="key.bin"
            """
        let expected = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,IV=  \(value)  ,URI=\"key.bin\"\n"
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

    @Test("multiple expanded lines share the original playlist byte budget")
    func cumulativeExpansionBoundary() throws {
        let source = try #require(URL(string: "https://media.example/index.m3u8"))
        let input = """
            #EXTM3U
            #EXT-X-DEFINE:IMPORT="part"
            #EXT-X-MAP:URI="{$part}-init.mp4"
            {$part}.m4s
            {$part}.m4s
            """
        let expected = "#EXTM3U\n#EXT-X-MAP:URI=\"🎬-init.mp4\"\n🎬.m4s\n🎬.m4s\n"
        let variables = ["part": "🎬"]
        let limit = expected.utf8.count
        let result = try HLSVariableSubstituter.expand(
            input, sourceURL: source, multivariantVariables: variables, maximumBytes: limit
        )
        #expect(result.contents == expected)
        #expect(result.variables == variables)
        #expect(result.containsImports)
        #expect(throws: HLSDownloadError.playlistTooLarge(limit: limit - 1)) {
            try HLSVariableSubstituter.expand(
                input, sourceURL: source, multivariantVariables: variables, maximumBytes: limit - 1
            )
        }
    }
}
