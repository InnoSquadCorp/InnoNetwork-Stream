import Foundation

public enum HLSOperationBackend: String, Codable, Sendable {
    case playlistInspection, singleFileDownload, offlinePackage, liveWatch, liveDVR
    case nativeBackgroundDownload, nativePlayback, decodedAudio
}
public enum HLSExecutionOwnership: String, Codable, Sendable {
    case none, foreground, systemManaged, callerNative, realtime
}

/// Describes backend ownership, not server content support or credentials.
public struct HLSBackendCapabilities: Equatable, Sendable {
    public let ownership: HLSExecutionOwnership
    public let supportsCheckpointRecovery: Bool
    public let supportsSystemRestoration: Bool
    public static func forBackend(_ backend: HLSOperationBackend) -> Self {
        switch backend {
        case .playlistInspection:
            Self(ownership: .none, supportsCheckpointRecovery: false, supportsSystemRestoration: false)
        case .liveWatch:
            Self(ownership: .foreground, supportsCheckpointRecovery: false, supportsSystemRestoration: false)
        case .singleFileDownload, .offlinePackage, .liveDVR:
            Self(ownership: .foreground, supportsCheckpointRecovery: true, supportsSystemRestoration: false)
        case .nativeBackgroundDownload:
            Self(ownership: .systemManaged, supportsCheckpointRecovery: false, supportsSystemRestoration: true)
        case .nativePlayback:
            Self(ownership: .callerNative, supportsCheckpointRecovery: false, supportsSystemRestoration: false)
        case .decodedAudio:
            Self(ownership: .realtime, supportsCheckpointRecovery: false, supportsSystemRestoration: false)
        }
    }
}

public enum HLSFailureCategory: String, Codable, Sendable {
    case invalidInput, configuration, transport, authorization, resourceLimit, storage, unsupported, security,
        cancelled, unknown
}
public enum HLSRecoveryAction: String, Codable, Sendable {
    case none, inspectInput, reconfigure, provideFreshAuthorization, retrySubjectToRequestPolicy
    case resumeSubjectToCheckpoint, restoreNativeTasks, inspectBackendSupport
}

/// Cross-module typed classification without transporting arbitrary error text.
public protocol HLSFailureCategorizing: Error {
    var hlsFailureCategory: HLSFailureCategory { get }
    var hlsRecoveryAction: HLSRecoveryAction? { get }
}
public extension HLSFailureCategorizing { var hlsRecoveryAction: HLSRecoveryAction? { nil } }

/// Export-safe classification. No source URL, error description, userInfo,
/// credentials, key bytes or arbitrary NSError domain is retained. Recovery is
/// advice, never authority to retry, refresh credentials or bypass policy.
public struct HLSFailureReport: Error, Codable, Equatable, Sendable {
    public let operationID: UUID?
    public let backend: HLSOperationBackend
    public let category: HLSFailureCategory
    /// Existing HLS NSError code only; unknown/underlying codes are suppressed.
    public let legacyHLSCode: Int?
    public let recovery: HLSRecoveryAction

    public static func classify(_ error: any Error, backend: HLSOperationBackend, operationID: UUID? = nil) -> Self {
        let category: HLSFailureCategory
        var code: Int?
        var recovery: HLSRecoveryAction?
        if error is CancellationError {
            category = .cancelled
        } else if let error = error as? HLSDownloadError {
            code = error.errorCode
            switch error {
            case .invalidResponseStatus(let status), .invalidMediaResponseStatus(let status),
                .invalidAES128KeyResponseStatus(let status):
                if status == 401 || status == 403 {
                    category = .authorization
                } else {
                    category = .transport
                    recovery =
                        [408, 429, 500, 502, 503, 504].contains(status) ? .retrySubjectToRequestPolicy : .inspectInput
                }
            case .playlistTooLarge, .mediaResourceTooLarge, .totalDownloadTooLarge, .offlineRenditionLimitExceeded,
                .insufficientDiskCapacity:
                category = .resourceLimit
            case .livePlaylistUnsupported, .encryptedPlaylistUnsupported, .byteRangePlaylistUnsupported,
                .separateAudioRenditionUnsupported, .unsupportedMediaFeature, .unsupportedOfflinePackageSchema:
                category = .unsupported
            case .diskCapacityUnavailable, .destinationAlreadyExists, .destinationInUse: category = .storage
            case .invalidDestination, .noVariantMatchesSelectionPolicy: category = .configuration
            case .transferFailed(let underlying):
                if let coreCategory = HLSDownloadError.nonTransientCoreFailureCategory(underlying) {
                    category = coreCategory
                    recovery = coreCategory == .configuration ? .reconfigure : HLSRecoveryAction.none
                } else {
                    category =
                        underlying.domain == NSURLErrorDomain && underlying.code == NSURLErrorCancelled
                        ? .cancelled : .transport
                    if underlying.domain == NSURLErrorDomain {
                        recovery =
                            HLSDownloadError.isTransientURLFailure(underlying.code)
                            ? .retrySubjectToRequestPolicy : HLSRecoveryAction.none
                    }
                }
            case .invalidAES128Key, .aes128DecryptionFailed: category = .security
            default: category = .invalidInput
            }
        } else if error is HLSConfigurationError {
            category = .configuration
        } else if let error = error as? HLSMediaCatalogError {
            switch error {
            case .invalidLimits, .invalidReference: category = .configuration
            case .capacityExceeded, .snapshotTooLarge: category = .resourceLimit
            case .unsupportedVersion: category = .unsupported
            default: category = .storage
            }
        } else if error is HLSOperationObservationError {
            category = .resourceLimit
        } else if let error = error as? URLError {
            category = error.code == .cancelled ? .cancelled : .transport
            recovery =
                HLSDownloadError.isTransientURLFailure(error.code.rawValue)
                ? .retrySubjectToRequestPolicy : HLSRecoveryAction.none
        } else if let error = error as? any HLSFailureCategorizing {
            category = error.hlsFailureCategory
            recovery = error.hlsRecoveryAction
        } else {
            category = .unknown
        }
        let fallback: HLSRecoveryAction
        switch category {
        case .configuration, .resourceLimit: fallback = .reconfigure
        case .invalidInput, .security, .storage: fallback = .inspectInput
        case .authorization: fallback = .provideFreshAuthorization
        case .unsupported: fallback = .inspectBackendSupport
        case .transport: fallback = .retrySubjectToRequestPolicy
        case .cancelled, .unknown: fallback = .none
        }
        var advice = recovery ?? fallback
        if category == .transport, advice == .retrySubjectToRequestPolicy {
            if backend == .liveDVR || backend == .singleFileDownload || backend == .offlinePackage {
                advice = .resumeSubjectToCheckpoint
            }
            if backend == .nativeBackgroundDownload { advice = .restoreNativeTasks }
        }
        return Self(
            operationID: operationID, backend: backend, category: category, legacyHLSCode: code, recovery: advice)
    }
}

public extension HLSPlaylistParser {
    /// Structured inspection without changing the existing throwing parse API
    /// or claiming line-level diagnostics not supplied by the legacy parser.
    func inspect(_ contents: String, relativeTo sourceURL: URL) -> Result<HLSPlaylistDocument, HLSFailureReport> {
        do { return .success(try parse(contents, relativeTo: sourceURL)) } catch {
            return .failure(.classify(error, backend: .playlistInspection))
        }
    }
}
