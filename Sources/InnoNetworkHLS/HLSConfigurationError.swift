/// A stable classification for invalid caller-provided runtime settings.
public enum HLSConfigurationError: Error, Equatable, Sendable {
    /// Playlist bytes must be in `1...Int32.max` on every supported platform.
    case invalidPlaylistByteLimit
    /// Per-resource bytes must be positive and no greater than the output limit.
    case invalidResourceByteLimit
    /// Retained output bytes must be positive.
    case invalidOutputByteLimit
    /// Resource concurrency must be in `1...8`.
    case invalidTransferConcurrency
    /// Required/best-effort disk thresholds must be non-negative.
    case invalidDiskCapacity
}
