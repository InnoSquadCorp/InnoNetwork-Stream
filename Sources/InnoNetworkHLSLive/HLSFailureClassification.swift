import InnoNetworkHLS

extension HLSLiveConfigurationError: HLSFailureCategorizing {
    public var hlsFailureCategory: HLSFailureCategory { .configuration }
}
extension HLSLiveDVRError: HLSFailureCategorizing {
    public var hlsFailureCategory: HLSFailureCategory {
        switch self {
        case .invalidDestination: .configuration
        case .transferFailed: .transport
        case .invalidByteRangeResponse, .noSegmentsRecorded, .liveWindowAdvanced: .invalidInput
        case .unsupportedFeature, .recoveryDisabled: .unsupported
        case .mediaResourceTooLarge, .insufficientDiskCapacity, .renditionLimitExceeded,
            .playbackSnapshotRequestLimitExceeded, .interstitialEventLimitExceeded, .interstitialPlaylistLimitExceeded,
            .interstitialStorageLimitReached:
            .resourceLimit
        case .invalidEncryptionKey, .decryptionFailed: .security
        case .invalidMediaResponseStatus(let status), .invalidEncryptionKeyResponseStatus(let status):
            status == 401 || status == 403 ? .authorization : .transport
        default: .storage
        }
    }
    public var hlsRecoveryAction: HLSRecoveryAction? {
        switch self {
        case .invalidMediaResponseStatus(let status), .invalidEncryptionKeyResponseStatus(let status):
            if status == 401 || status == 403 { return .provideFreshAuthorization }
            return [408, 429, 500, 502, 503, 504].contains(status) ? .resumeSubjectToCheckpoint : .inspectInput
        default: return nil
        }
    }
}
