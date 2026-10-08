import Foundation

/// Owns one atomic offline package operation. Retain until completion; releasing
/// the handle or calling `cancel()` cancels unfinished work. Observers and receipt
/// waiters are independent: cancelling either does not cancel the operation.
public final class HLSOfflinePackageTask: Sendable {
    private let channel: HLSOperationChannel<HLSOfflinePackageEvent, HLSOfflinePackageReceipt>
    private let worker: Task<Void, Never>

    public var id: UUID { channel.id }
    public var state: HLSDownloadTaskState { channel.state }
    public var failureReport: HLSFailureReport? {
        channel.failure.map { .classify($0, backend: .offlinePackage, operationID: id) }
    }

    var pendingReceiptCount: Int { channel.pendingWaiterCount }

    init(operation: HLSOfflinePackageOperation, sourceURL: URL, destinationDirectoryURL: URL) {
        let channel = HLSOperationChannel<HLSOfflinePackageEvent, HLSOfflinePackageReceipt>()
        self.channel = channel
        self.worker = Task {
            let outcome = await operation.execute(
                sourceURL: sourceURL, destinationDirectoryURL: destinationDirectoryURL,
                onProgress: { channel.emit(.progress($0)) })
            // execute has released its destination lease and completed cleanup.
            // A committed receipt wins cancellation arriving after publication.
            switch outcome {
            case .completed(let receipt):
                channel.emit(.completed(receipt))
                channel.finish(.success(receipt))
            case .failed(let error):
                channel.emit(.failed(error))
                channel.finish(.failure(error))
            case .cancelled:
                channel.emit(.cancelled)
                channel.finish(.failure(CancellationError()))
            }
        }
    }

    deinit { worker.cancel() }

    /// Requests cancellation, preserving any already committed package.
    public func cancel() { worker.cancel() }

    /// Independent, bounded observation (16 newest events, at most 64 observers).
    /// Replays the latest event; failure/cancellation also terminates by throwing.
    /// Use `receipt()` for authoritative completion, not progress delivery.
    public func events() throws -> AsyncThrowingStream<HLSOperationObservation<HLSOfflinePackageEvent>, Error> {
        try channel.subscribe()
    }

    /// Waits for atomic publication. At most 64 pending receipt waiters are
    /// supported. Cancellation removes only this waiter; call `cancel()` to stop
    /// the producer. An already terminal result is returned even after cancellation.
    public func receipt() async throws -> HLSOfflinePackageReceipt { try await channel.value() }
}
