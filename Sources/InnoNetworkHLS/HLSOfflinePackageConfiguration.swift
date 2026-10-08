import Foundation
import InnoNetwork

/// Groups storage limits for an offline HLS package.
///
/// Offline packages are committed atomically as a complete directory. Durable
/// partial state remains private to the downloader.
public struct HLSOfflinePackageStoragePack: Sendable {
    private let maximumMediaResourceBytes: Int
    private let maximumTotalDownloadBytes: Int64
    private let diskCapacityPolicy: HLSDiskCapacityPolicy
    private let resumePolicy: HLSResumePolicy

    /// Creates an offline package storage pack.
    public init(
        maximumMediaResourceBytes: Int = 128 * 1_024 * 1_024,
        maximumTotalDownloadBytes: Int64 = 8 * 1_024 * 1_024 * 1_024,
        diskCapacityPolicy: HLSDiskCapacityPolicy = .required(
            minimumAvailableCapacity: 512 * 1_024 * 1_024
        ),
        resumePolicy: HLSResumePolicy = .automatic
    ) {
        self.maximumMediaResourceBytes = maximumMediaResourceBytes
        self.maximumTotalDownloadBytes = maximumTotalDownloadBytes
        self.diskCapacityPolicy = diskCapacityPolicy
        self.resumePolicy = resumePolicy
    }

    func apply(
        to builder: inout HLSOfflinePackageConfiguration.Builder
    ) {
        builder.maximumMediaResourceBytes = max(
            1,
            maximumMediaResourceBytes
        )
        builder.maximumTotalDownloadBytes = max(
            1,
            maximumTotalDownloadBytes
        )
        builder.diskCapacityPolicy = diskCapacityPolicy
        builder.resumePolicy = resumePolicy
    }
}

/// Configures bounded multi-rendition HLS offline packages.
public struct HLSOfflinePackageConfiguration: Sendable {
    /// Effective maximum bytes accepted for one media resource.
    public let maximumMediaResourceBytes: Int
    /// Effective retained-byte limit across the package's resources.
    public let maximumTotalDownloadBytes: Int64
    /// Effective destination-volume admission policy.
    public let diskCapacityPolicy: HLSDiskCapacityPolicy
    /// Effective interrupted-package retention policy.
    public let resumePolicy: HLSResumePolicy
    /// Effective maximum concurrent resource transfers (`1...8`).
    public let maximumConcurrentResourceTransfers: Int
    let retryPolicy: (any RetryPolicy)?
    /// Effective primary variant selection policy.
    public let variantSelectionPolicy: HLSVariantSelectionPolicy
    let renditionPack: HLSOfflineRenditionPack
    let contentSteering: HLSContentSteeringSettings
    let sessionKeyPreloadPolicy: HLSSessionKeyPreloadPolicy

    struct Builder {
        var maximumMediaResourceBytes = 128 * 1_024 * 1_024
        var maximumTotalDownloadBytes: Int64 =
            8 * 1_024 * 1_024 * 1_024
        var diskCapacityPolicy: HLSDiskCapacityPolicy = .required(
            minimumAvailableCapacity: 512 * 1_024 * 1_024
        )
        var resumePolicy: HLSResumePolicy = .automatic
        var maximumConcurrentResourceTransfers = 3
        var retryPolicy: (any RetryPolicy)? =
            ExponentialBackoffRetryPolicy()
        var variantSelectionPolicy: HLSVariantSelectionPolicy =
            .highestQuality
        var renditionPack = HLSOfflineRenditionPack()
        var contentSteering = HLSContentSteeringPack().resolvedSettings
        var sessionKeyPreloadPolicy: HLSSessionKeyPreloadPolicy = .disabled
    }

    private init(builder: Builder) {
        self.maximumMediaResourceBytes =
            builder.maximumMediaResourceBytes
        self.maximumTotalDownloadBytes =
            builder.maximumTotalDownloadBytes
        self.diskCapacityPolicy = builder.diskCapacityPolicy
        self.resumePolicy = builder.resumePolicy
        self.maximumConcurrentResourceTransfers =
            builder.maximumConcurrentResourceTransfers
        self.retryPolicy = builder.retryPolicy
        self.variantSelectionPolicy =
            builder.variantSelectionPolicy
        self.renditionPack = builder.renditionPack
        self.contentSteering = builder.contentSteering
        self.sessionKeyPreloadPolicy = builder.sessionKeyPreloadPolicy
    }

    /// Returns conservative package defaults.
    ///
    /// The defaults retain one external audio rendition, omit video,
    /// subtitles, and I-frame trick-play, limit resource concurrency to three,
    /// and apply the same byte and disk capacity bounds as
    /// ``HLSDownloadConfiguration/safeDefaults()``.
    public static func safeDefaults()
        -> HLSOfflinePackageConfiguration
    {
        advanced()
    }

    /// Builds immutable settings without normalizing invalid limits.
    ///
    /// The offline macro and manual workflows share the single-file workflow's
    /// byte, concurrency and disk validation. Renditions retain separate HLS
    /// timelines and are committed together as one atomic package.
    public static func validated(
        maximumMediaResourceBytes: Int = 134_217_728,
        maximumTotalDownloadBytes: Int64 = 8_589_934_592,
        maximumConcurrentResourceTransfers: Int = 3,
        diskCapacityPolicy: HLSDiskCapacityPolicy = .required(minimumAvailableCapacity: 536_870_912),
        resumePolicy: HLSResumePolicy = .automatic,
        variantSelectionPolicy: HLSVariantSelectionPolicy = .highestQuality,
        renditions: HLSOfflineRenditionPack = HLSOfflineRenditionPack(),
        contentSteering: HLSContentSteeringPack = HLSContentSteeringPack(),
        retryPolicy: (any RetryPolicy)? = ExponentialBackoffRetryPolicy()
    ) throws -> HLSOfflinePackageConfiguration {
        let common = try HLSDownloadConfiguration.validated(
            maximumMediaResourceBytes: maximumMediaResourceBytes,
            maximumTotalDownloadBytes: maximumTotalDownloadBytes,
            maximumConcurrentResourceTransfers: maximumConcurrentResourceTransfers,
            diskCapacityPolicy: diskCapacityPolicy, resumePolicy: resumePolicy,
            variantSelectionPolicy: variantSelectionPolicy, contentSteering: contentSteering,
            retryPolicy: retryPolicy)
        var builder = Builder()
        builder.maximumMediaResourceBytes = common.maximumMediaResourceBytes
        builder.maximumTotalDownloadBytes = common.maximumTotalDownloadBytes
        builder.maximumConcurrentResourceTransfers = common.maximumConcurrentResourceTransfers
        builder.diskCapacityPolicy = common.diskCapacityPolicy
        builder.resumePolicy = common.resumePolicy
        builder.variantSelectionPolicy = common.variantSelectionPolicy
        builder.contentSteering = common.contentSteering
        builder.retryPolicy = common.retryPolicy
        builder.renditionPack = renditions
        return HLSOfflinePackageConfiguration(builder: builder)
    }

    /// Returns an explicitly tuned offline-package configuration.
    public static func advanced(
        storage: HLSOfflinePackageStoragePack =
            HLSOfflinePackageStoragePack(),
        variantSelectionPolicy: HLSVariantSelectionPolicy =
            .highestQuality,
        renditions: HLSOfflineRenditionPack =
            HLSOfflineRenditionPack(),
        contentSteering: HLSContentSteeringPack =
            HLSContentSteeringPack(),
        transfer: HLSTransferPack = HLSTransferPack()
    ) -> HLSOfflinePackageConfiguration {
        var builder = Builder()
        storage.apply(to: &builder)
        let transferSettings = transfer.resolvedSettings()
        builder.maximumConcurrentResourceTransfers =
            transferSettings.maximumConcurrentResourceTransfers
        builder.retryPolicy = transferSettings.retryPolicy
        builder.sessionKeyPreloadPolicy =
            transferSettings.sessionKeyPreloadPolicy
        builder.variantSelectionPolicy = variantSelectionPolicy
        builder.renditionPack = renditions
        builder.contentSteering = contentSteering.resolvedSettings
        return HLSOfflinePackageConfiguration(builder: builder)
    }
}
