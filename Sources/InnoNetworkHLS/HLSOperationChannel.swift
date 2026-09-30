import Foundation
import os

/// Sequenced, bounded observation. Raw payloads are not export-safe telemetry.
public struct HLSOperationObservation<Event: Sendable>: Sendable {
    public let operationID: UUID
    public let sequence: UInt64
    /// Losses observed before enqueue; the current enqueue may evict another value.
    public let droppedEventCount: UInt64
    public let event: Event
}

/// Shared delivery only, not a shared execution or native ownership policy.
package final class HLSOperationChannel<Event: Sendable, Output: Sendable>: Sendable {
    private struct Subscriber {
        let continuation: AsyncThrowingStream<HLSOperationObservation<Event>, Error>.Continuation
        var drops: UInt64 = 0
    }
    private struct Storage {
        var result: Result<Output, Error>?
        var latest: Event?
        var sequence: UInt64 = 0
        var subscribers: [UUID: Subscriber] = [:]
        var waiters: [UUID: CheckedContinuation<Output, Error>] = [:]
    }
    package let id = UUID()
    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    package init() {}

    package var state: HLSDownloadTaskState {
        storage.withLock {
            switch $0.result {
            case nil: .running
            case .success: .completed
            case .failure(let error): error is CancellationError ? .cancelled : .failed
            }
        }
    }

    package func subscribe(buffer: Int = 16) throws -> AsyncThrowingStream<HLSOperationObservation<Event>, Error> {
        let subscriberID = UUID()
        let (stream, continuation) = AsyncThrowingStream<HLSOperationObservation<Event>, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(min(64, max(1, buffer)))
        )
        // Termination can occur synchronously during yield/finish. Removal must
        // not re-enter the delivery lock on that callback stack.
        continuation.onTermination = { [weak self] _ in
            Task { self?.removeSubscriber(subscriberID) }
        }
        let terminal: Result<Output, Error>? = try storage.withLock { state in
            guard state.subscribers.count < 64 else { throw HLSOperationObservationError.capacityExceeded }
            if let latest = state.latest {
                continuation.yield(
                    .init(operationID: id, sequence: state.sequence, droppedEventCount: 0, event: latest))
            }
            if let result = state.result { return result }
            state.subscribers[subscriberID] = Subscriber(continuation: continuation)
            return nil
        }
        if let terminal { complete(continuation, terminal) }
        return stream
    }

    package func emit(_ event: Event) {
        storage.withLock { state in
            guard state.result == nil else { return }
            state.sequence &+= 1
            state.latest = event
            for subscriberID in Array(state.subscribers.keys) {
                guard var subscriber = state.subscribers[subscriberID] else { continue }
                let outcome = subscriber.continuation.yield(
                    .init(
                        operationID: id, sequence: state.sequence, droppedEventCount: subscriber.drops, event: event
                    ))
                if case .dropped = outcome { subscriber.drops &+= 1 }
                if case .terminated = outcome {
                    state.subscribers.removeValue(forKey: subscriberID)
                } else {
                    state.subscribers[subscriberID] = subscriber
                }
            }
        }
    }

    package func finish(_ result: Result<Output, Error>) {
        let delivery = storage.withLock { state -> ([Subscriber], [CheckedContinuation<Output, Error>]) in
            guard state.result == nil else { return ([], []) }
            state.result = result
            let delivery = (Array(state.subscribers.values), Array(state.waiters.values))
            state.subscribers.removeAll()
            state.waiters.removeAll()
            return delivery
        }
        for subscriber in delivery.0 { complete(subscriber.continuation, result) }
        for waiter in delivery.1 { waiter.resume(with: result) }
    }

    package func value() async throws -> Output {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let immediate = storage.withLock { state -> Result<Output, Error>? in
                    if let result = state.result { return result }
                    if Task.isCancelled { return .failure(CancellationError()) }
                    guard state.waiters.count < 64 else {
                        return .failure(HLSOperationObservationError.capacityExceeded)
                    }
                    state.waiters[waiterID] = continuation
                    return nil
                }
                if let immediate { continuation.resume(with: immediate) }
            }
        } onCancel: {
            let waiter = self.storage.withLock { $0.waiters.removeValue(forKey: waiterID) }
            waiter?.resume(throwing: CancellationError())
        }
    }

    private func removeSubscriber(_ id: UUID) { storage.withLock { $0.subscribers.removeValue(forKey: id) } }
    private func complete(
        _ continuation: AsyncThrowingStream<HLSOperationObservation<Event>, Error>.Continuation,
        _ result: Result<Output, Error>
    ) {
        switch result {
        case .success: continuation.finish()
        case .failure(let error): continuation.finish(throwing: error)
        }
    }
}
