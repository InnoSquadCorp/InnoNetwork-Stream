import Foundation
import InnoNetwork

/// Defines an atomic multi-rendition offline package workflow.
///
/// Prefer this to single-file assembly when preserving audio/subtitle timelines
/// or the local HLS presentation is required. Limits are checked at expansion
/// and at runtime; no request, task or file is created by the macro itself.
@attached(member, names: named(configuration))
@attached(extension, conformances: HLSOfflinePackageDefining)
public macro HLSOfflinePackageDefinition(
    maximumMediaResourceBytes: Int = 134_217_728,
    maximumTotalDownloadBytes: Int64 = 8_589_934_592,
    maximumConcurrentResourceTransfers: Int = 3
) = #externalMacro(module: "InnoNetworkStreamMacros", type: "HLSWorkflowDefinitionMacro")

/// Manual equivalent and compiler-plugin recovery boundary for an offline
/// workflow. Prefer
/// ``HLSOfflinePackageDefinition(maximumMediaResourceBytes:maximumTotalDownloadBytes:maximumConcurrentResourceTransfers:)``
/// for declarative limits.
public protocol HLSOfflinePackageDefining {
    static func configuration() throws -> HLSOfflinePackageConfiguration
}

public extension HLSOfflinePackageDefining {
    /// Creates an effect-free downloader with caller-owned transport policy.
    static func makeDownloader(
        session: URLSession = .shared,
        requestContext: NetworkRequestContext = NetworkRequestContext(),
        requestPolicy: HLSRequestPolicy = HLSRequestPolicy()
    ) throws -> HLSOfflinePackageDownloader {
        HLSOfflinePackageDownloader(
            session: session, configuration: try configuration(),
            requestContext: requestContext, requestPolicy: requestPolicy)
    }

    /// Resolves an advisory selection without writing or fetching media. The
    /// subsequent download independently resolves and validates its plan.
    static func prepare(
        sourceURL: URL,
        session: URLSession = .shared,
        requestContext: NetworkRequestContext = NetworkRequestContext(),
        requestPolicy: HLSRequestPolicy = HLSRequestPolicy()
    ) async throws -> HLSOfflinePackagePreparation {
        try await makeDownloader(session: session, requestContext: requestContext, requestPolicy: requestPolicy)
            .prepare(sourceURL: sourceURL)
    }

    /// Downloads in the calling task, preserving its cancellation, bounded
    /// checkpoint recovery and atomic publication. Only a committed package
    /// produces a receipt. Existing destinations are never overwritten.
    static func downloadPackage(
        sourceURL: URL,
        destinationDirectoryURL: URL,
        session: URLSession = .shared,
        requestContext: NetworkRequestContext = NetworkRequestContext(),
        requestPolicy: HLSRequestPolicy = HLSRequestPolicy()
    ) async throws -> HLSOfflinePackageReceipt {
        try await makeDownloader(session: session, requestContext: requestContext, requestPolicy: requestPolicy)
            .downloadPackage(sourceURL: sourceURL, destinationDirectoryURL: destinationDirectoryURL)
    }
}
