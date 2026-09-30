import Foundation
import InnoNetwork
import InnoNetworkHLS

@attached(member, names: named(configuration))
@attached(extension, conformances: HLSLiveDefining)
public macro HLSLiveDefinition(
    minimumPollingMilliseconds: Int = 500, maximumPollingMilliseconds: Int = 30_000, requestTimeoutSeconds: Int = 45
) = #externalMacro(module: "InnoNetworkStreamMacros", type: "HLSWorkflowDefinitionMacro")

public protocol HLSLiveDefining { static func configuration() throws -> HLSLiveConfiguration }

public extension HLSLiveDefining {
    static func makeClient(
        session: URLSession = .shared, requestContext: NetworkRequestContext = NetworkRequestContext(),
        requestPolicy: HLSRequestPolicy = HLSRequestPolicy()
    ) throws -> HLSLivePlaylistClient {
        HLSLivePlaylistClient(
            session: session, configuration: try configuration(), requestContext: requestContext,
            requestPolicy: requestPolicy)
    }
    static func watch(
        from sourceURL: URL, session: URLSession = .shared,
        requestContext: NetworkRequestContext = NetworkRequestContext(),
        requestPolicy: HLSRequestPolicy = HLSRequestPolicy()
    ) throws -> HLSLiveWatching {
        try makeClient(session: session, requestContext: requestContext, requestPolicy: requestPolicy).watch(
            from: sourceURL)
    }
}

@attached(member, names: named(configuration))
@attached(extension, conformances: HLSDVRDefining)
public macro HLSDVRDefinition(
    maximumDurationSeconds: Int = 1800, maximumSegmentCount: Int = 900, maximumMediaResourceBytes: Int = 134_217_728,
    maximumTotalMediaBytes: Int64 = 8_589_934_592
) = #externalMacro(module: "InnoNetworkStreamMacros", type: "HLSWorkflowDefinitionMacro")

public protocol HLSDVRDefining { static func configuration() throws -> HLSLiveDVRConfiguration }

public extension HLSDVRDefining {
    /// Reuses the caller's configured Live transport, key and steering policy.
    static func startRecording(from sourceURL: URL, to destinationDirectoryURL: URL, client: HLSLivePlaylistClient)
        throws -> HLSLiveDVRRecording
    {
        HLSLiveDVRRecorder(client: client, configuration: try configuration()).startRecording(
            from: sourceURL, to: destinationDirectoryURL)
    }
}

public enum HLSLiveConfigurationError: Error, Equatable, Sendable {
    case invalidReloadTiming
    case invalidRecordingLimits
}

public extension HLSLiveConfiguration {
    var minimumPollingInterval: TimeInterval { reload.minimumPollingInterval }
    var maximumPollingInterval: TimeInterval { reload.maximumPollingInterval }
    var requestTimeout: TimeInterval { reload.requestTimeout }
    /// Dynamic equivalent of the macro. Rejects, rather than silently clamps.
    static func validated(
        minimumPollingMilliseconds: Int = 500, maximumPollingMilliseconds: Int = 30_000, requestTimeoutSeconds: Int = 45
    ) throws -> Self {
        guard (50...3_600_000).contains(minimumPollingMilliseconds),
            (minimumPollingMilliseconds...3_600_000).contains(maximumPollingMilliseconds),
            (1...300).contains(requestTimeoutSeconds)
        else {
            throw HLSLiveConfigurationError.invalidReloadTiming
        }
        return advanced(
            reload: HLSLiveReloadPack(
                minimumPollingInterval: Double(minimumPollingMilliseconds) / 1000,
                maximumPollingInterval: Double(maximumPollingMilliseconds) / 1000,
                requestTimeout: Double(requestTimeoutSeconds)))
    }
}

public extension HLSLiveDVRConfiguration {
    var effectiveLimits: HLSLiveDVRLimitPack { limits }
    static func validated(
        maximumDurationSeconds: Int = 1800, maximumSegmentCount: Int = 900,
        maximumMediaResourceBytes: Int = 134_217_728, maximumTotalMediaBytes: Int64 = 8_589_934_592
    ) throws -> Self {
        guard (1...86_400).contains(maximumDurationSeconds), (1...10_000).contains(maximumSegmentCount),
            (1...1_073_741_824).contains(maximumMediaResourceBytes),
            (1...68_719_476_736).contains(maximumTotalMediaBytes),
            Int64(maximumMediaResourceBytes) <= maximumTotalMediaBytes
        else {
            throw HLSLiveConfigurationError.invalidRecordingLimits
        }
        return advanced(
            limits: HLSLiveDVRLimitPack(
                maximumDuration: Double(maximumDurationSeconds), maximumSegmentCount: maximumSegmentCount,
                maximumMediaResourceBytes: maximumMediaResourceBytes, maximumTotalMediaBytes: maximumTotalMediaBytes))
    }
}
