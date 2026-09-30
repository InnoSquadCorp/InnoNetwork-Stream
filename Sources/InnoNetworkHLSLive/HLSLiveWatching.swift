import Foundation
import InnoNetworkHLS

/// Owns a foreground watch; releasing it cancels reloads, not committed media.
/// Observers are independent. Zero observers do not stop the watch.
public final class HLSLiveWatching: Sendable {
    private let channel: HLSOperationChannel<HLSLivePlaylistSnapshot, HLSLivePlaylistSnapshot>
    private let worker: Task<Void, Never>
    public var id: UUID { channel.id }
    public var state: HLSDownloadTaskState { channel.state }

    init(client: HLSLivePlaylistClient, sourceURL: URL) {
        let channel = HLSOperationChannel<HLSLivePlaylistSnapshot, HLSLivePlaylistSnapshot>()
        self.channel = channel
        self.worker = Task {
            do {
                var latest: HLSLivePlaylistSnapshot?
                for try await snapshot in client.snapshots(from: sourceURL) {
                    try Task.checkCancellation()
                    latest = snapshot
                    channel.emit(snapshot)
                }
                try Task.checkCancellation()
                guard let latest else { throw HLSDownloadError.invalidPlaylist }
                channel.finish(.success(latest))
            } catch { channel.finish(.failure(error)) }
        }
    }
    deinit { worker.cancel() }
    public func cancel() { worker.cancel() }
    public func observations() throws -> AsyncThrowingStream<HLSOperationObservation<HLSLivePlaylistSnapshot>, Error> {
        try channel.subscribe(buffer: 1)
    }
    /// Completes when ENDLIST terminates the watch. Cancelling the waiter only
    /// cancels its observation; explicitly cancel the handle to stop reloads.
    public func finalSnapshot() async throws -> HLSLivePlaylistSnapshot { try await channel.value() }
}

public extension HLSLivePlaylistClient {
    func watch(from sourceURL: URL) -> HLSLiveWatching { HLSLiveWatching(client: self, sourceURL: sourceURL) }
}
