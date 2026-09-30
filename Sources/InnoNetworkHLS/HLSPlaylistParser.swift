import Foundation

/// A pure, bounded parser. Construction and parsing perform no transport,
/// authentication, resource loading, key acquisition or file effects.
public struct HLSPlaylistParser: Sendable {
    public let maximumPlaylistBytes: Int

    public init(maximumPlaylistBytes: Int = 2 * 1_024 * 1_024) throws {
        guard (1...Int(Int32.max)).contains(maximumPlaylistBytes) else {
            throw HLSConfigurationError.invalidPlaylistByteLimit
        }
        self.maximumPlaylistBytes = maximumPlaylistBytes
    }

    /// Imports are caller-provided values, never implicitly fetched resources.
    /// A parsed media document can still be unsupported for a chosen backend.
    public func parse(
        _ contents: String,
        relativeTo sourceURL: URL,
        multivariantVariables: [String: String]? = nil
    ) throws -> HLSPlaylistDocument {
        guard contents.utf8.count <= maximumPlaylistBytes else {
            throw HLSDownloadError.playlistTooLarge(limit: maximumPlaylistBytes)
        }
        let expansion = try HLSVariableSubstituter.expand(
            contents,
            sourceURL: sourceURL,
            multivariantVariables: multivariantVariables,
            maximumBytes: maximumPlaylistBytes
        )
        let playlist = try HLSPlaylistDocumentParser.parse(
            expansion.contents, relativeTo: sourceURL, expansion: expansion
        )
        return try HLSPlaylistDocument(parsed: playlist)
    }
}

/// Discriminates parser-produced documents without contradictory public
/// construction. Payloads are read-only views of the complete parsed metadata.
public enum HLSPlaylistDocument: Equatable, Sendable {
    case multivariant(HLSMultivariantDocument)
    case media(HLSMediaDocument)

    init(parsed playlist: HLSPlaylist) throws {
        switch playlist.kind {
        case .multivariant:
            guard !playlist.variants.isEmpty, playlist.media == nil,
                playlist.mediaContainer == nil, playlist.programDateTimes.isEmpty,
                playlist.dateRanges.isEmpty, playlist.lowLatency == nil
            else { throw HLSDownloadError.invalidPlaylist }
            self = .multivariant(HLSMultivariantDocument(playlist: playlist))
        case .media:
            guard playlist.media != nil, playlist.variants.isEmpty,
                playlist.iFrameVariants.isEmpty, playlist.renditions.isEmpty,
                playlist.contentSteering == nil, playlist.sessionData.isEmpty,
                playlist.sessionKeys.isEmpty
            else { throw HLSDownloadError.invalidPlaylist }
            self = .media(HLSMediaDocument(playlist: playlist))
        }
    }

    /// Lossless interoperability with inspection APIs during migration.
    /// Unlike legacy construction, these values originate in the parser.
    public var legacyPlaylist: HLSPlaylist {
        switch self {
        case .multivariant(let value): value.playlist
        case .media(let value): value.playlist
        }
    }

    public var sourceURL: URL { legacyPlaylist.sourceURL }
}

/// Multivariant metadata, with no media-sequence or segment optionals.
public struct HLSMultivariantDocument: Equatable, Sendable {
    let playlist: HLSPlaylist
    public var sourceURL: URL { playlist.sourceURL }
    public var variants: [HLSVariant] { playlist.variants }
    public var iFrameVariants: [HLSVariant] { playlist.iFrameVariants }
    public var renditions: [HLSRendition] { playlist.renditions }
    public var protocolVersion: Int? { playlist.protocolVersion }
    public var hasIndependentSegments: Bool { playlist.hasIndependentSegments }
    public var contentSteering: HLSContentSteering? { playlist.contentSteering }
    public var sessionData: [HLSSessionData] { playlist.sessionData }
    public var sessionKeys: [HLSSessionKey] { playlist.sessionKeys }
    public var preferredStartPosition: HLSPreferredStartPosition? { playlist.preferredStartPosition }
}

/// Media metadata. Absence of a target duration remains inspectable; parsing
/// does not pretend that every syntactically valid document is downloadable.
public struct HLSMediaDocument: Equatable, Sendable {
    let playlist: HLSPlaylist
    public var sourceURL: URL { playlist.sourceURL }
    public var protocolVersion: Int? { playlist.protocolVersion }
    public var hasIndependentSegments: Bool { playlist.hasIndependentSegments }
    public var preferredStartPosition: HLSPreferredStartPosition? { playlist.preferredStartPosition }
    public var programDateTimes: [HLSProgramDateTime] { playlist.programDateTimes }
    public var dateRanges: [HLSDateRange] { playlist.dateRanges }
    public var lowLatency: HLSLowLatencyMetadata? { playlist.lowLatency }
    public var mediaContainer: HLSMediaContainer? { playlist.mediaContainer }
    public var targetDuration: Int? { playlist.targetDuration }
    public var mediaSequence: Int64 { playlist.mediaSequence ?? 0 }
    public var discontinuitySequence: Int64 { playlist.discontinuitySequence ?? 0 }
    public var mediaPlaylistType: HLSMediaPlaylistType? { playlist.mediaPlaylistType }
    public var segmentBitrates: [HLSSegmentBitrate] { playlist.segmentBitrates }
    public var segmentCount: Int { playlist.media?.segmentCount ?? 0 }
    public var hasEndList: Bool { playlist.media?.hasEndList ?? false }

    /// Checks the same raw single-file backend rules as execution. This is
    /// advisory, not an executable retained snapshot: start() resolves again.
    public func validateSingleFileDownload() throws {
        guard let media = playlist.media else { throw HLSDownloadError.invalidPlaylist }
        try HLSMediaPlaylistValidator.validate(media)
    }
}
