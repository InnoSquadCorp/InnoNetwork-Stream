import Foundation
import InnoNetwork
import Testing

@testable import InnoNetworkHLS

@Suite("Content Steering expansion budgets")
struct HLSSteeringExpansionBudgetTests {
    @Test("clone counts are bounded even when priority never selects the clones")
    func unusedCloneBudget() throws {
        let playlist = try playlist(variantCount: 1)
        let admitted = try manifest(cloneCount: 64)
        #expect(HLSPathwayCatalogBuilder.make(playlist: playlist, manifest: admitted) != nil)
        let rejected = try manifest(cloneCount: 65)
        #expect(HLSPathwayCatalogBuilder.make(playlist: playlist, manifest: rejected) == nil)
    }

    @Test("expanded record budget includes source and cloned records")
    func crossProductBudget() throws {
        let playlist = try playlist(variantCount: 3)
        let manifest = try manifest(cloneCount: 2)
        #expect(
            HLSPathwayCatalogBuilder.make(
                playlist: playlist, manifest: manifest,
                limits: .init(maximumRecords: 9)
            ) != nil)
        #expect(
            HLSPathwayCatalogBuilder.make(
                playlist: playlist, manifest: manifest,
                limits: .init(maximumRecords: 8)
            ) == nil)
    }

    @Test("cloned URL text is independently bounded at its exact byte limit")
    func aggregateTextBudget() throws {
        let playlist = try playlist(variantCount: 1)
        let manifest = try manifest(cloneCount: 1)
        let bytes = try #require(playlist.variants.first).url.absoluteString.utf8.count
        #expect(
            HLSPathwayCatalogBuilder.make(
                playlist: playlist, manifest: manifest,
                limits: .init(maximumExpandedTextBytes: bytes)
            ) != nil)
        #expect(
            HLSPathwayCatalogBuilder.make(
                playlist: playlist, manifest: manifest,
                limits: .init(maximumExpandedTextBytes: bytes - 1)
            ) == nil)
    }

    @Test("query rewrites are rejected before multiplying oversized values")
    func rewrittenURLBudget() throws {
        let playlist = try playlist(variantCount: 1)
        let normal = try manifest(cloneCount: 1, parameters: ["q": "ok"])
        #expect(
            HLSPathwayCatalogBuilder.make(
                playlist: playlist, manifest: normal,
                limits: .init(maximumURLBytes: 128)
            ) != nil)
        let oversized = try manifest(cloneCount: 1, parameters: ["q": String(repeating: "a", count: 129)])
        #expect(
            HLSPathwayCatalogBuilder.make(
                playlist: playlist, manifest: oversized,
                limits: .init(maximumURLBytes: 128)
            ) == nil)
    }

    @Test("rendition references repeated across output pathways share one record budget")
    func repeatedRenditionBudget() throws {
        let source = try #require(URL(string: "https://media.example/master.m3u8"))
        let contents = """
            #EXTM3U
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="one",URI="one.m3u8"
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="two",URI="two.m3u8"
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="three",URI="three.m3u8"
            #EXT-X-STREAM-INF:BANDWIDTH=1,PATHWAY-ID="p0",AUDIO="a"
            v0.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=1,PATHWAY-ID="p1",AUDIO="a"
            v1.m3u8
            """
        let playlist = try HLSPlaylistParser().parse(contents, relativeTo: source).legacyPlaylist
        let manifest = try decode(["VERSION": 1, "TTL": 60, "PATHWAY-PRIORITY": ["p0", "p1"]])
        #expect(
            HLSPathwayCatalogBuilder.make(
                playlist: playlist, manifest: manifest,
                limits: .init(maximumRecords: 8)
            ) != nil)
        #expect(
            HLSPathwayCatalogBuilder.make(
                playlist: playlist, manifest: manifest,
                limits: .init(maximumRecords: 7)
            ) == nil)
    }

    @Test("oversized optional Steering falls back to the declared initial pathway")
    func safeFallback() async throws {
        let data = try JSONSerialization.data(withJSONObject: wire(cloneCount: 65, parameters: [:]))
        let directive = "data:application/json;base64," + data.base64EncodedString()
        let playlist = try playlist(variantCount: 1, serverURI: directive)
        let resolver = HLSContentSteeringResolver(
            client: HLSHTTPClient(
                session: .shared, requestContext: NetworkRequestContext(), requestPolicy: HLSRequestPolicy()
            ),
            settings: HLSContentSteeringPack().resolvedSettings
        )
        let catalog = try await resolver.catalog(for: playlist)
        #expect(catalog.pathways.count == 1)
        #expect(catalog.pathways.first?.id == "base")
        #expect(catalog.pathways.first?.variants.count == 1)
    }

    @Test("cancelled catalog construction never expands clones")
    func cancelledExpansion() async throws {
        let playlist = try playlist(variantCount: 1)
        let manifest = try manifest(cloneCount: 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return HLSPathwayCatalogBuilder.make(playlist: playlist, manifest: manifest) == nil
        }
        #expect(await task.value)
    }

    @Test("fallback bounds original pathway and shared rendition amplification")
    func boundedOriginalFallback() async throws {
        for (pathways, renditions) in [(65, 2), (16, 1_024)] {
            let playlist = try fallbackPlaylist(pathwayCount: pathways, renditionCount: renditions)
            let resolver = fallbackResolver()
            let catalog = try await resolver.catalog(for: playlist)
            #expect(catalog.pathways.count == 1)
            #expect(catalog.pathways.first?.id == "p\(pathways - 1)")
            #expect(catalog.pathways.first?.variants.count == 1)
            #expect(catalog.pathways.first?.renditions.count == renditions)
        }
    }

    @Test("ordinary fallback retains ordered cross-pathway recovery")
    func ordinaryOriginalFallback() async throws {
        let playlist = try fallbackPlaylist(pathwayCount: 2, renditionCount: 2)
        let catalog = try await fallbackResolver().catalog(for: playlist)
        #expect(catalog.pathways.map(\.id) == ["p1", "p0"])
        #expect(catalog.pathways.allSatisfy { $0.renditions.count == 2 })
    }

    private func fallbackResolver() -> HLSContentSteeringResolver {
        HLSContentSteeringResolver(
            client: HLSHTTPClient(
                session: .shared, requestContext: NetworkRequestContext(), requestPolicy: HLSRequestPolicy()
            ),
            settings: HLSContentSteeringPack.disabled.resolvedSettings
        )
    }

    private func fallbackPlaylist(pathwayCount: Int, renditionCount: Int) throws -> HLSPlaylist {
        let source = try #require(URL(string: "https://media.example/master.m3u8"))
        var lines = [
            "#EXTM3U", "#EXT-X-VERSION:12",
            "#EXT-X-CONTENT-STEERING:SERVER-URI=\"steering.json\",PATHWAY-ID=\"p\(pathwayCount - 1)\"",
        ]
        for index in 0..<renditionCount {
            lines.append("#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a\",NAME=\"a\(index)\",URI=\"a\(index).m3u8\"")
        }
        for index in 0..<pathwayCount {
            lines.append("#EXT-X-STREAM-INF:BANDWIDTH=1,PATHWAY-ID=\"p\(index)\",AUDIO=\"a\"")
            lines.append("v\(index).m3u8")
        }
        return try HLSPlaylistParser().parse(lines.joined(separator: "\n"), relativeTo: source).legacyPlaylist
    }

    private func playlist(variantCount: Int, serverURI: String? = nil) throws -> HLSPlaylist {
        let source = try #require(URL(string: "https://media.example/master.m3u8"))
        var lines = ["#EXTM3U", "#EXT-X-VERSION:12"]
        if let serverURI {
            lines.append("#EXT-X-CONTENT-STEERING:SERVER-URI=\"\(serverURI)\",PATHWAY-ID=\"base\"")
        }
        for index in 0..<variantCount {
            lines.append("#EXT-X-STREAM-INF:BANDWIDTH=1,PATHWAY-ID=\"base\",STABLE-VARIANT-ID=\"v\(index)\"")
            lines.append("v\(index).m3u8")
        }
        return try HLSPlaylistParser().parse(lines.joined(separator: "\n"), relativeTo: source).legacyPlaylist
    }

    private func manifest(cloneCount: Int, parameters: [String: String] = [:]) throws -> HLSContentSteeringManifest {
        try decode(wire(cloneCount: cloneCount, parameters: parameters))
    }

    private func wire(cloneCount: Int, parameters: [String: String]) -> [String: Any] {
        [
            "VERSION": 1, "TTL": 60, "PATHWAY-PRIORITY": ["base"],
            "PATHWAY-CLONES": (0..<cloneCount).map { index -> [String: Any] in
                ["BASE-ID": "base", "ID": "c\(index)", "URI-REPLACEMENT": ["PARAMS": parameters]]
            },
        ]
    }

    private func decode(_ wire: [String: Any]) throws -> HLSContentSteeringManifest {
        let source = try #require(URL(string: "https://media.example/steering.json"))
        let data = try JSONSerialization.data(withJSONObject: wire)
        return try #require(HLSContentSteeringManifest.decode(data, finalURL: source))
    }
}
