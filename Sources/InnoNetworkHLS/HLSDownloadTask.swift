import Foundation
import os

/// A bounded observation channel could not be admitted.
public enum HLSOperationObservationError: Error, Equatable, Sendable {
    /// At most 64 concurrent subscriptions or result waiters are supported.
    case capacityExceeded
}

/// A download's terminal disposition, independent of progress consumption.
public enum HLSDownloadTaskState: Equatable, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

/// A sequenced event from an independently observed download.
/// The terminal payload can contain an application-owned file URL; this is not
/// an automatically redacted telemetry/export format.
public struct HLSDownloadObservation: Sendable {
    /// Correlates subscriptions to one operation, without revealing its URL.
    public let operationID: UUID
    /// Monotonically increasing operation event sequence.
    public let sequence: UInt64
    /// Cumulative drops observed before this event was enqueued. Enqueuing this
    /// event can evict one more value; sequence gaps identify that loss. This
    /// is not a post-delivery or final-channel drop count.
    public let droppedEventCount: UInt64
    /// Existing progress or terminal event contract.
    public let event: HLSDownloadEvent
}

/// Owns one foreground download independently of its progress subscribers.
///
/// Retain the handle until completion. Releasing it or calling ``cancel()``
/// cancels its work. Cancelling an events/result observer cancels only that
/// observation. Use ``receipt()`` for the authoritative terminal result;
/// bounded progress may coalesce. A committed receipt wins late cancellation.
public final class HLSDownloadTask: Sendable {
    public let id: UUID
    private let hub: HLSDownloadTaskHub
    private let worker: Task<Void, Never>

    init(
        operation: HLSDownloadOperation,
        sourceURL: URL,
        destinationURL: URL
    ) {
        let id = UUID()
        let hub = HLSDownloadTaskHub(id: id)
        self.id = id
        self.hub = hub
        self.worker = Task {
            let outcome = await operation.execute(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                onProgress: { hub.emit(.progress($0)) }
            )
            hub.finish(outcome)
        }
    }

    deinit { worker.cancel() }

    public var state: HLSDownloadTaskState { hub.state }

    /// Requests cancellation; completed output is never implicitly deleted.
    public func cancel() { worker.cancel() }

    /// Creates an independent subscription with a newest-16 event buffer.
    /// A terminal subscription replays its terminal event and then finishes.
    public func events() throws -> AsyncStream<HLSDownloadObservation> {
        try hub.subscribe()
    }

    /// Waits for a committed receipt or typed failure. Cancelling this waiter
    /// does not cancel the operation or other waiters; call ``cancel()`` to do so.
    public func receipt() async throws -> HLSDownloadReceipt {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                hub.wait(id: waiterID, continuation: continuation)
            }
        } onCancel: {
            hub.cancelWaiter(waiterID)
        }
    }
}

private final class HLSDownloadTaskHub: Sendable {
    private struct Subscriber {
        let continuation: AsyncStream<HLSDownloadObservation>.Continuation
        var dropped: UInt64 = 0
    }

    private struct Storage {
        var outcome: HLSDownloadOutcome?
        var sequence: UInt64 = 0
        var subscribers: [UUID: Subscriber] = [:]
        var waiters: [UUID: CheckedContinuation<HLSDownloadReceipt, Error>] = [:]
    }

    private let id: UUID
    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    init(id: UUID) { self.id = id }

    var state: HLSDownloadTaskState {
        storage.withLock {
            switch $0.outcome {
            case nil: .running
            case .completed: .completed
            case .failed: .failed
            case .cancelled: .cancelled
            }
        }
    }

    func subscribe() throws -> AsyncStream<HLSDownloadObservation> {
        let subscriberID = UUID()
        let (stream, continuation) = AsyncStream<HLSDownloadObservation>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
        // Never invoke a termination callback while holding the storage lock.
        continuation.onTermination = { [weak self] _ in
            self?.removeSubscriber(subscriberID)
        }
        let terminal: (HLSDownloadOutcome, UInt64)? = try storage.withLock {
            if let outcome = $0.outcome { return (outcome, $0.sequence) }
            guard $0.subscribers.count < 64 else {
                throw HLSOperationObservationError.capacityExceeded
            }
            $0.subscribers[subscriberID] = Subscriber(continuation: continuation)
            return nil
        }
        if let (outcome, sequence) = terminal {
            continuation.yield(observation(event: Self.event(outcome), sequence: sequence, dropped: 0))
            continuation.finish()
        }
        return stream
    }

    func wait(id: UUID, continuation: CheckedContinuation<HLSDownloadReceipt, Error>) {
        let immediate: Result<HLSDownloadReceipt, Error>? = storage.withLock {
            guard !Task.isCancelled else { return .failure(CancellationError()) }
            if let outcome = $0.outcome { return Self.result(outcome) }
            guard $0.waiters.count < 64 else {
                return .failure(HLSOperationObservationError.capacityExceeded)
            }
            $0.waiters[id] = continuation
            return nil
        }
        if let immediate { continuation.resume(with: immediate) }
    }

    func cancelWaiter(_ id: UUID) {
        let continuation = storage.withLock { $0.waiters.removeValue(forKey: id) }
        continuation?.resume(throwing: CancellationError())
    }

    func emit(_ event: HLSDownloadEvent) {
        // Serializing bounded yields preserves sequence order. Termination
        // removes asynchronously so no user callback re-enters this lock.
        storage.withLock {
            guard $0.outcome == nil else { return }
            $0.sequence = Self.increment($0.sequence)
            for subscriberID in Array($0.subscribers.keys) {
                guard var subscriber = $0.subscribers[subscriberID] else { continue }
                let value = observation(event: event, sequence: $0.sequence, dropped: subscriber.dropped)
                if case .dropped = subscriber.continuation.yield(value) {
                    subscriber.dropped = Self.increment(subscriber.dropped)
                }
                $0.subscribers[subscriberID] = subscriber
            }
        }
    }

    func finish(_ outcome: HLSDownloadOutcome) {
        let delivery = storage.withLock { state in
            guard state.outcome == nil else {
                return (UInt64(0), [Subscriber](), [CheckedContinuation<HLSDownloadReceipt, Error>]())
            }
            state.outcome = outcome
            state.sequence = Self.increment(state.sequence)
            let delivery = (state.sequence, Array(state.subscribers.values), Array(state.waiters.values))
            state.subscribers.removeAll()
            state.waiters.removeAll()
            return delivery
        }
        for subscriber in delivery.1 {
            subscriber.continuation.yield(
                observation(event: Self.event(outcome), sequence: delivery.0, dropped: subscriber.dropped)
            )
            subscriber.continuation.finish()
        }
        for waiter in delivery.2 { waiter.resume(with: Self.result(outcome)) }
    }

    private func removeSubscriber(_ id: UUID) {
        // AsyncStream can invoke onTermination synchronously inside yield.
        Task { [weak self] in
            self?.storage.withLock { $0.subscribers.removeValue(forKey: id) }
        }
    }

    private func observation(event: HLSDownloadEvent, sequence: UInt64, dropped: UInt64) -> HLSDownloadObservation {
        HLSDownloadObservation(operationID: id, sequence: sequence, droppedEventCount: dropped, event: event)
    }

    private static func increment(_ value: UInt64) -> UInt64 {
        value == .max ? .max : value + 1
    }

    private static func event(_ outcome: HLSDownloadOutcome) -> HLSDownloadEvent {
        switch outcome {
        case .completed(let receipt): .completed(receipt.destinationURL)
        case .failed(let error): .failed(error)
        case .cancelled: .cancelled
        }
    }

    private static func result(_ outcome: HLSDownloadOutcome) -> Result<HLSDownloadReceipt, Error> {
        switch outcome {
        case .completed(let receipt): .success(receipt)
        case .failed(let error): .failure(error)
        case .cancelled: .failure(CancellationError())
        }
    }
}
