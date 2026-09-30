import AVFoundation
import InnoNetworkHLS

@attached(member, names: named(configuration))
@attached(extension, conformances: HLSPlaybackDefining)
public macro HLSPlaybackDefinition(
    maximumPeakBitRate: Int = 10_000_000, maximumWidth: Int = 1920, maximumHeight: Int = 1080
) = #externalMacro(module: "InnoNetworkStreamMacros", type: "HLSWorkflowDefinitionMacro")

public protocol HLSPlaybackDefining { static func configuration() throws -> HLSPlaybackConfiguration }

public extension HLSPlaybackDefining {
    /// Applies to a caller-owned item on MainActor. Never creates/plays a player.
    @MainActor
    static func apply(to item: AVPlayerItem) async throws -> HLSPlaybackConfigurationResult {
        try await HLSPlaybackConfigurator().apply(configuration(), to: item)
    }
}

public enum HLSPlaybackLimitError: Error, Equatable, Sendable { case invalidLimits }

public extension HLSPlaybackConfiguration {
    static func validated(maximumPeakBitRate: Int = 10_000_000, maximumWidth: Int = 1920, maximumHeight: Int = 1080)
        throws -> Self
    {
        guard (1...Int(Int32.max)).contains(maximumPeakBitRate), (1...Int(Int32.max)).contains(maximumWidth),
            (1...Int(Int32.max)).contains(maximumHeight)
        else { throw HLSPlaybackLimitError.invalidLimits }
        return advanced(
            variant: HLSPlaybackVariantPack(
                maximumPeakBitRate: maximumPeakBitRate, maximumWidth: maximumWidth, maximumHeight: maximumHeight))
    }
}
