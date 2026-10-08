import Foundation
import Testing

@testable import InnoNetworkHLS

@Suite("HLS definition-time variable expansion")
struct HLSVariableDefinitionTests {
    private let source = URL(string: "https://media.example/index.m3u8")!

    @Test("VALUE references resolve against prior definitions before retention")
    func chainedDefinitions() throws {
        let input = """
            #EXTM3U
            #EXT-X-VERSION:8
            #EXT-X-DEFINE:NAME="a",VALUE="video"
            #EXT-X-DEFINE:NAME="b",VALUE="{$a}"
            #EXT-X-DEFINE:NAME="c",VALUE="{$b}/main"
            #EXT-X-TARGETDURATION:1
            #EXTINF:1,
            {$b}.ts
            #EXT-X-ENDLIST
            """
        let expansion = try expand(input)
        #expect(expansion.variables == ["a": "video", "b": "video", "c": "video/main"])
        #expect(expansion.contents.contains("\nvideo.ts\n"))
        let parsed = try HLSPlaylistParser().parse(input, relativeTo: source)
        #expect(
            parsed.legacyPlaylist.media?.resources.first?.url.absoluteString
                == "https://media.example/video.ts"
        )
    }

    @Test(
        "undefined, forward, self, and malformed references fail even in unused definitions",
        arguments: [
            "#EXT-X-DEFINE:NAME=\"a\",VALUE=\"{$missing}\"",
            "#EXT-X-DEFINE:NAME=\"a\",VALUE=\"{$a}\"",
            "#EXT-X-DEFINE:NAME=\"a\",VALUE=\"{$b}\"\n#EXT-X-DEFINE:NAME=\"b\",VALUE=\"video\"",
            "#EXT-X-DEFINE:NAME=\"a\",VALUE=\"{$missing\"",
            "#EXT-X-DEFINE:NAME=\"a\",VALUE=\"{$}\"",
            "#EXT-X-DEFINE:NAME=\"a\",VALUE=\"one\"\n#EXT-X-DEFINE:NAME=\"a\",VALUE=\"two\"",
        ]
    )
    func invalidDefinitions(_ definitions: String) throws {
        #expect(throws: HLSDownloadError.invalidPlaylist) {
            try expand("#EXTM3U\n\(definitions)\n")
        }
    }

    @Test("imported and query values support definitions without recursive substitution", arguments: [false, true])
    func replacementsStayLiteral(queryParameter: Bool) throws {
        let sourceURL = try #require(
            URL(string: "https://media.example/index.m3u8?token=%7B%24missing%7D")
        )
        let selector = queryParameter ? "QUERYPARAM" : "IMPORT"
        let input = """
            #EXTM3U
            #EXT-X-DEFINE:\(selector)="token"
            #EXT-X-DEFINE:NAME="b",VALUE="prefix-{$token}"
            {$b}.ts
            """
        let expansion = try HLSVariableSubstituter.expand(
            input,
            sourceURL: sourceURL,
            multivariantVariables: ["token": "{$missing}"],
            maximumBytes: 1_024
        )
        #expect(expansion.variables["b"] == "prefix-{$missing}")
        #expect(expansion.contents == "#EXTM3U\nprefix-{$missing}.ts\n")
    }

    @Test("retained names and UTF8 values share one exact byte limit", arguments: [false, true])
    func retainedDefinitionBoundary(imported: Bool) throws {
        let input =
            "#EXTM3U\n"
            + (imported
                ? "#EXT-X-DEFINE:IMPORT=\"a\"\n#EXT-X-DEFINE:IMPORT=\"b\"\n"
                : "#EXT-X-DEFINE:NAME=\"a\",VALUE=\"🎬🎬\"\n#EXT-X-DEFINE:NAME=\"b\",VALUE=\"{$a}\"\n")
        let variables = ["a": "🎬🎬", "b": "🎬🎬"]
        let limit = variables.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
        #expect(limit == 18)
        let expansion = try expand(input, variables: variables, limit: limit)
        #expect(expansion.contents == "#EXTM3U\n")
        #expect(expansion.variables == variables)
        #expect(throws: HLSDownloadError.playlistTooLarge(limit: limit - 1)) {
            try expand(input, variables: variables, limit: limit - 1)
        }
    }

    @Test("unused imported and query values cannot exceed the retained budget", arguments: [false, true])
    func oversizedExternalDefinition(queryParameter: Bool) throws {
        let value = String(repeating: "x", count: 128)
        let sourceURL = try #require(URL(string: "https://media.example/index.m3u8?v=\(value)"))
        let selector = queryParameter ? "QUERYPARAM" : "IMPORT"
        #expect(throws: HLSDownloadError.playlistTooLarge(limit: 128)) {
            try HLSVariableSubstituter.expand(
                "#EXTM3U\n#EXT-X-DEFINE:\(selector)=\"v\"\n",
                sourceURL: sourceURL,
                multivariantVariables: ["v": value],
                maximumBytes: 128
            )
        }
    }

    @Test("multiplicative unused definitions fail within the retained budget")
    func multiplicativeDefinitions() throws {
        var lines = ["#EXTM3U", "#EXT-X-VERSION:8", "#EXT-X-DEFINE:NAME=\"v0\",VALUE=\"x\""]
        for index in 1...20 {
            let reference = "{$v\(index - 1)}"
            lines.append("#EXT-X-DEFINE:NAME=\"v\(index)\",VALUE=\"\(reference)\(reference)\"")
        }
        let input = lines.joined(separator: "\n")
        let limit = 1_024
        #expect(input.utf8.count < limit)
        #expect(throws: HLSDownloadError.playlistTooLarge(limit: limit)) {
            try HLSPlaylistParser(maximumPlaylistBytes: limit).parse(input, relativeTo: source)
        }
    }

    @Test("one definition expansion is bounded before appending repeated replacements")
    func oversizedDefinition() throws {
        let input = """
            #EXTM3U
            #EXT-X-DEFINE:IMPORT="a"
            #EXT-X-DEFINE:NAME="b",VALUE="\(String(repeating: "{$a}", count: 100))"
            """
        #expect(throws: HLSDownloadError.playlistTooLarge(limit: 1_024)) {
            try expand(input, variables: ["a": String(repeating: "x", count: 128)], limit: 1_024)
        }
    }

    @Test("empty chained values stay valid and trailing empty expansions are omitted")
    func emptyDefinitions() throws {
        let input = """
            #EXTM3U
            #EXT-X-DEFINE:NAME="a",VALUE=""
            #EXT-X-DEFINE:NAME="b",VALUE="{$a}"
            {$b}

            """
        let expansion = try expand(input, limit: "#EXTM3U\n".utf8.count)
        #expect(expansion.variables == ["a": "", "b": ""])
        #expect(expansion.contents == "#EXTM3U\n")
    }

    private func expand(
        _ input: String,
        variables: [String: String]? = nil,
        limit: Int = 1_024
    ) throws -> HLSVariableExpansion {
        try HLSVariableSubstituter.expand(
            input, sourceURL: source, multivariantVariables: variables, maximumBytes: limit
        )
    }
}
