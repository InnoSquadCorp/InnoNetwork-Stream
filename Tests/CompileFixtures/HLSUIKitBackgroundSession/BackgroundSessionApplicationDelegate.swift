#if os(iOS) && canImport(UIKit)
import InnoNetworkHLSAVFoundation
import UIKit

// Compile this non-exported target explicitly with each supported iOS SDK.
// macOS unit tests cannot validate the actual UIKit protocol signature.
@MainActor
final class BackgroundSessionApplicationDelegate: NSObject, UIApplicationDelegate {
    private var sessions: [String: HLSAssetDownloadSession] = [:]

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if let session = sessions[identifier] {
            session.handleBackgroundSessionCompletion(
                identifier,
                completion: completionHandler
            )
            return
        }

        do {
            // A real app restores its original options as well as the ID.
            sessions[identifier] = try HLSAssetDownloadSession(
                configuration: HLSAssetDownloadSessionPack(
                    identifier: identifier
                ),
                backgroundSessionCompletion: completionHandler
            )
        } catch {
            // Construction failed before accepting ownership of the handler.
            completionHandler()
        }
    }
}
#endif
