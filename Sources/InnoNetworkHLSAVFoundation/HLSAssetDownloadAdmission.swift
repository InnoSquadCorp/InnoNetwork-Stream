#if canImport(AVFoundation) && !os(tvOS)
import Foundation
import InnoNetwork

enum HLSAssetDownloadAdmission {
    static func validateSourceURL(_ sourceURL: URL) throws {
        guard sourceURL.scheme?.lowercased() == "https" else {
            throw HLSAssetDownloadSessionError.insecureSourceURL
        }
        do {
            try NetworkURLValidator.validate(
                sourceURL,
                policy: .http()
            )
        } catch {
            throw HLSAssetDownloadSessionError.invalidSourceURL
        }
    }
}
#endif
