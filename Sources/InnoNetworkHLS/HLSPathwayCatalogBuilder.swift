import Foundation

enum HLSPathwayCatalogBuilder {
    struct Limits {
        var maximumClones = 64
        var maximumPathways = 64
        var maximumRecords = 16_384
        var maximumURLBytes = 64 * 1_024
        var maximumExpandedTextBytes = 8 * 1_024 * 1_024
    }

    private struct Budget {
        var remainingRecords: Int
        var remainingTextBytes: Int

        mutating func reserveRecords(_ count: Int) -> Bool {
            guard count >= 0, count <= remainingRecords else { return false }
            remainingRecords -= count
            return true
        }

        mutating func reserveText(_ count: Int) -> Bool {
            guard count >= 0, count <= remainingTextBytes else { return false }
            remainingTextBytes -= count
            return true
        }
    }

    static func make(
        playlist: HLSPlaylist,
        manifest: HLSContentSteeringManifest,
        limits: Limits = Limits()
    ) -> HLSPathwayCatalog? {
        guard !Task.isCancelled,
            manifest.pathwayClones.count <= limits.maximumClones,
            manifest.pathwayPriority.count <= limits.maximumPathways
        else { return nil }
        var budget = Budget(
            remainingRecords: limits.maximumRecords,
            remainingTextBytes: limits.maximumExpandedTextBytes
        )
        guard budget.reserveRecords(playlist.variants.count),
            budget.reserveRecords(playlist.iFrameVariants.count),
            budget.reserveRecords(playlist.renditions.count)
        else { return nil }
        var variants = playlist.variants
        var iFrameVariants = playlist.iFrameVariants
        var renditions = playlist.renditions
        var knownPathwayIDs = Set(
            variants.map { $0.pathwayID ?? HLSPathwayID.implicit }
        )

        for clone in manifest.pathwayClones {
            guard !Task.isCancelled else { return nil }
            guard knownPathwayIDs.contains(clone.baseID) else {
                continue
            }
            guard !knownPathwayIDs.contains(clone.id) else {
                return nil
            }
            let baseVariants = variants.filter {
                ($0.pathwayID ?? HLSPathwayID.implicit) == clone.baseID
            }
            let baseIFrameVariants = iFrameVariants.filter {
                ($0.pathwayID ?? HLSPathwayID.implicit) == clone.baseID
            }
            guard budget.reserveRecords(baseVariants.count),
                budget.reserveRecords(baseIFrameVariants.count),
                let groupMappings = makeGroupMappings(
                    variants: baseVariants + baseIFrameVariants,
                    cloneID: clone.id,
                    budget: &budget
                )
            else { return nil }
            let baseRenditions = renditions.filter { rendition in
                groupMappings[
                    GroupKey(
                        kind: rendition.kind,
                        groupID: rendition.groupID
                    )
                ] != nil
            }
            guard budget.reserveRecords(baseRenditions.count) else { return nil }
            let clonedRenditions = baseRenditions.compactMap {
                clonedRendition(
                    $0,
                    groupMappings: groupMappings,
                    clone: clone,
                    maximumURLBytes: limits.maximumURLBytes,
                    budget: &budget
                )
            }
            let clonedVariants = baseVariants.compactMap {
                clonedVariant(
                    $0,
                    groupMappings: groupMappings,
                    clone: clone,
                    maximumURLBytes: limits.maximumURLBytes,
                    budget: &budget
                )
            }
            let clonedIFrameVariants = baseIFrameVariants.compactMap {
                clonedVariant(
                    $0,
                    groupMappings: groupMappings,
                    clone: clone,
                    maximumURLBytes: limits.maximumURLBytes,
                    budget: &budget
                )
            }
            guard clonedVariants.count == baseVariants.count,
                clonedIFrameVariants.count == baseIFrameVariants.count,
                clonedRenditions.count == baseRenditions.count
            else {
                return nil
            }
            renditions.append(contentsOf: clonedRenditions)
            variants.append(contentsOf: clonedVariants)
            iFrameVariants.append(contentsOf: clonedIFrameVariants)
            knownPathwayIDs.insert(clone.id)
        }

        var pathways: [HLSPathway] = []
        var outputBudget = Budget(remainingRecords: limits.maximumRecords, remainingTextBytes: 0)
        for pathwayID in manifest.pathwayPriority
        where knownPathwayIDs.contains(pathwayID) {
            guard !Task.isCancelled else { return nil }
            let pathwayVariants = variants.filter {
                ($0.pathwayID ?? HLSPathwayID.implicit) == pathwayID
            }
            let pathwayIFrameVariants = iFrameVariants.filter {
                ($0.pathwayID ?? HLSPathwayID.implicit) == pathwayID
            }
            guard !pathwayVariants.isEmpty else {
                continue
            }
            let pathwayRenditions = referencedRenditions(
                variants: pathwayVariants + pathwayIFrameVariants,
                renditions: renditions
            )
            guard outputBudget.reserveRecords(pathwayVariants.count),
                outputBudget.reserveRecords(pathwayIFrameVariants.count),
                outputBudget.reserveRecords(pathwayRenditions.count)
            else { return nil }
            pathways.append(
                HLSPathway(
                    id: pathwayID,
                    variants: pathwayVariants,
                    iFrameVariants: pathwayIFrameVariants,
                    renditions: pathwayRenditions
                )
            )
        }
        return HLSPathwayCatalog(pathways: pathways)
    }

    private static func clonedRendition(
        _ rendition: HLSRendition,
        groupMappings: [GroupKey: String],
        clone: HLSContentSteeringManifest.PathwayClone,
        maximumURLBytes: Int,
        budget: inout Budget
    ) -> HLSRendition? {
        let key = GroupKey(
            kind: rendition.kind,
            groupID: rendition.groupID
        )
        guard let clonedGroupID = groupMappings[key] else {
            return nil
        }
        let clonedURL = rendition.url.flatMap {
            transformedURL(
                $0,
                stableID: rendition.stableID,
                overrideURLs: clone.perRenditionURLs,
                clone: clone,
                maximumURLBytes: maximumURLBytes,
                budget: &budget
            )
        }
        guard rendition.url == nil || clonedURL != nil else {
            return nil
        }
        return HLSRendition(
            kind: rendition.kind,
            groupID: clonedGroupID,
            name: rendition.name,
            language: rendition.language,
            associatedLanguage: rendition.associatedLanguage,
            stableID: rendition.stableID,
            instreamID: rendition.instreamID,
            characteristics: rendition.characteristics,
            channels: rendition.channels,
            audioBitDepth: rendition.audioBitDepth,
            audioSampleRate: rendition.audioSampleRate,
            url: clonedURL,
            isDefault: rendition.isDefault,
            isAutoselect: rendition.isAutoselect,
            isForced: rendition.isForced
        )
    }

    private static func clonedVariant(
        _ variant: HLSVariant,
        groupMappings: [GroupKey: String],
        clone: HLSContentSteeringManifest.PathwayClone,
        maximumURLBytes: Int,
        budget: inout Budget
    ) -> HLSVariant? {
        guard
            let url = transformedURL(
                variant.url,
                stableID: variant.stableID,
                overrideURLs: clone.perVariantURLs,
                clone: clone,
                maximumURLBytes: maximumURLBytes,
                budget: &budget
            )
        else {
            return nil
        }
        return HLSVariant(
            url: url,
            bandwidth: variant.bandwidth,
            averageBandwidth: variant.averageBandwidth,
            score: variant.score,
            width: variant.width,
            height: variant.height,
            audioGroupID: mappedGroupID(
                variant.audioGroupID,
                kind: .audio,
                mappings: groupMappings
            ),
            subtitleGroupID: mappedGroupID(
                variant.subtitleGroupID,
                kind: .subtitles,
                mappings: groupMappings
            ),
            videoGroupID: mappedGroupID(
                variant.videoGroupID,
                kind: .video,
                mappings: groupMappings
            ),
            closedCaptions: mappedClosedCaptions(
                variant.closedCaptions,
                mappings: groupMappings
            ),
            codecs: variant.codecs,
            supplementalCodecs: variant.supplementalCodecs,
            frameRate: variant.frameRate,
            videoRange: variant.videoRange,
            hdcpLevel: variant.hdcpLevel,
            allowedContentProtectionConfigurations:
                variant.allowedContentProtectionConfigurations,
            requiredVideoLayouts: variant.requiredVideoLayouts,
            stableID: variant.stableID,
            pathwayID: clone.id
        )
    }

    private static func makeGroupMappings(
        variants: [HLSVariant],
        cloneID: String,
        budget: inout Budget
    ) -> [GroupKey: String]? {
        var mappings: [GroupKey: String] = [:]
        for variant in variants {
            let captionGroup: String?
            if case .group(let groupID) = variant.closedCaptions { captionGroup = groupID }
            else { captionGroup = nil }
            let groups: [(HLSRenditionKind, String?)] = [
                (.audio, variant.audioGroupID), (.subtitles, variant.subtitleGroupID),
                (.video, variant.videoGroupID), (.closedCaptions, captionGroup),
            ]
            for (kind, groupID) in groups {
                guard let groupID else { continue }
                let key = GroupKey(kind: kind, groupID: groupID)
                guard mappings[key] == nil else { continue }
                // Reserve before concatenation: a long clone ID multiplied
                // across groups must not allocate outside the text budget.
                guard budget.reserveText(groupID.utf8.count),
                    budget.reserveText(1), budget.reserveText(cloneID.utf8.count)
                else { return nil }
                mappings[key] = "\(groupID)@\(cloneID)"
            }
        }
        return mappings
    }

    private static func mappedGroupID(
        _ groupID: String?,
        kind: HLSRenditionKind,
        mappings: [GroupKey: String]
    ) -> String? {
        guard let groupID else {
            return nil
        }
        return mappings[GroupKey(kind: kind, groupID: groupID)]
    }

    private static func mappedClosedCaptions(
        _ closedCaptions: HLSClosedCaptionReference?,
        mappings: [GroupKey: String]
    ) -> HLSClosedCaptionReference? {
        guard case .group(let groupID) = closedCaptions else {
            return closedCaptions
        }
        guard
            let mapped = mappings[
                GroupKey(kind: .closedCaptions, groupID: groupID)
            ]
        else {
            return nil
        }
        return .group(mapped)
    }

    private static func referencedRenditions(
        variants: [HLSVariant],
        renditions: [HLSRendition]
    ) -> [HLSRendition] {
        var keys: Set<GroupKey> = []
        for variant in variants {
            if let groupID = variant.audioGroupID {
                keys.insert(GroupKey(kind: .audio, groupID: groupID))
            }
            if let groupID = variant.subtitleGroupID {
                keys.insert(GroupKey(kind: .subtitles, groupID: groupID))
            }
            if let groupID = variant.videoGroupID {
                keys.insert(GroupKey(kind: .video, groupID: groupID))
            }
            if case .group(let groupID) = variant.closedCaptions {
                keys.insert(
                    GroupKey(kind: .closedCaptions, groupID: groupID)
                )
            }
        }
        return renditions.filter {
            keys.contains(GroupKey(kind: $0.kind, groupID: $0.groupID))
        }
    }

    private static func transformedURL(
        _ sourceURL: URL,
        stableID: String?,
        overrideURLs: [String: URL],
        clone: HLSContentSteeringManifest.PathwayClone,
        maximumURLBytes: Int,
        budget: inout Budget
    ) -> URL? {
        guard !Task.isCancelled else { return nil }
        if let stableID, let override = overrideURLs[stableID] {
            let bytes = override.absoluteString.utf8.count
            guard bytes <= maximumURLBytes, budget.reserveText(bytes) else { return nil }
            return override
        }
        // A conservative pre-allocation envelope includes percent encoding.
        // Replaced old query fields remain counted, so oversized rewrites fail
        // back to the original pathway instead of building an enormous URL.
        var available = maximumURLBytes
        func reserve(_ bytes: Int, multiplier: Int = 1) -> Bool {
            guard available >= 0, bytes <= available / multiplier else { return false }
            available -= bytes * multiplier
            return true
        }
        guard reserve(sourceURL.absoluteString.utf8.count),
            reserve(clone.host?.utf8.count ?? 0, multiplier: 3)
        else { return nil }
        for (key, value) in clone.parameters {
            guard reserve(key.utf8.count, multiplier: 3),
                reserve(value.utf8.count, multiplier: 3), reserve(2)
            else { return nil }
        }
        guard
            var components = URLComponents(
                url: sourceURL,
                resolvingAgainstBaseURL: true
            )
        else {
            return nil
        }
        if let host = clone.host {
            components.host = host
        }
        if !clone.parameters.isEmpty {
            let replacementNames = Set(clone.parameters.keys)
            var queryItems = (components.queryItems ?? []).filter {
                !replacementNames.contains($0.name)
            }
            let sortedNames = clone.parameters.keys.sorted {
                Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8))
            }
            queryItems.append(
                contentsOf: sortedNames.map {
                    URLQueryItem(
                        name: $0,
                        value: clone.parameters[$0]
                    )
                }
            )
            components.queryItems = queryItems
        }
        guard let url = components.url,
            url.absoluteString.utf8.count <= maximumURLBytes,
            budget.reserveText(url.absoluteString.utf8.count)
        else { return nil }
        return url
    }

    private struct GroupKey: Hashable {
        let kind: HLSRenditionKind
        let groupID: String

        func hash(into hasher: inout Hasher) {
            hasher.combine(kind)
            hasher.combine(groupID)
        }
    }
}
