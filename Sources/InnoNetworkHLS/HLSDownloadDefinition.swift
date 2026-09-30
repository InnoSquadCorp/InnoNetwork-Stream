import Foundation
import InnoNetwork

/// Defines a declarative download workflow with compile-time checked limits.
///
/// Attach to a struct or enum. Generated configuration is immutable and uses
/// the same runtime validation as the advanced manual equivalent. Macros do
/// not issue requests; ``HLSDownloadDefining/start(sourceURL:destinationURL:session:requestContext:requestPolicy:)``
/// explicitly starts work with caller-owned policy and credentials.
@attached(member, names: named(configuration))
@attached(extension, conformances: HLSDownloadDefining)
public macro HLSDownloadDefinition(
    maximumMediaResourceBytes: Int = 134_217_728,
    maximumTotalDownloadBytes: Int64 = 8_589_934_592,
    maximumConcurrentResourceTransfers: Int = 3
) = #externalMacro(module: "InnoNetworkStreamMacros", type: "HLSDownloadDefinitionMacro")

/// The generated workflow contract, also available as an advanced manual
/// compiler-plugin recovery boundary. Prefer ``HLSDownloadDefinition``.
public protocol HLSDownloadDefining {
    static func configuration() throws -> HLSDownloadConfiguration
}

public extension HLSDownloadDefining {
    /// Requests a validated selection preview without writing media. The
    /// preview never authorizes a stale snapshot to bypass a fresh start.
    static func prepare(
        sourceURL: URL,
        session: URLSession = .shared,
        requestContext: NetworkRequestContext = NetworkRequestContext(),
        requestPolicy: HLSRequestPolicy = HLSRequestPolicy()
    ) async throws -> HLSDownloadPreparation {
        try await makeDownloader(
            session: session, requestContext: requestContext, requestPolicy: requestPolicy
        ).prepare(sourceURL: sourceURL)
    }

    /// Constructs a downloader without starting any effects.
    static func makeDownloader(
        session: URLSession = .shared,
        requestContext: NetworkRequestContext = NetworkRequestContext(),
        requestPolicy: HLSRequestPolicy = HLSRequestPolicy()
    ) throws -> HLSDownloader {
        HLSDownloader(
            session: session,
            configuration: try configuration(),
            requestContext: requestContext,
            requestPolicy: requestPolicy
        )
    }

    /// Starts an explicitly owned foreground operation. Observation never
    /// grants authority to alter its trust policy or delete its committed output.
    static func start(
        sourceURL: URL,
        destinationURL: URL,
        session: URLSession = .shared,
        requestContext: NetworkRequestContext = NetworkRequestContext(),
        requestPolicy: HLSRequestPolicy = HLSRequestPolicy()
    ) throws -> HLSDownloadTask {
        try makeDownloader(
            session: session,
            requestContext: requestContext,
            requestPolicy: requestPolicy
        ).start(sourceURL: sourceURL, destinationURL: destinationURL)
    }
}
