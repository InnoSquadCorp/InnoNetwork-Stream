#if canImport(AVFoundation) && !os(tvOS)
import AVFoundation
import Foundation
import InnoNetwork
import os

@available(watchOS 10.0, *)
final class HLSAssetDownloadDelegate: NSObject, AVAssetDownloadDelegate {
    private let eventHub: HLSAssetDownloadEventHub
    private let backgroundCompletions: HLSAssetDownloadBackgroundCompletionStore
    private let invalidationGate: HLSAssetDownloadInvalidationGate
    private let onInvalidation: @Sendable () -> Void

    init(
        eventHub: HLSAssetDownloadEventHub,
        backgroundCompletions:
            HLSAssetDownloadBackgroundCompletionStore,
        invalidationGate: HLSAssetDownloadInvalidationGate,
        onInvalidation: @escaping @Sendable () -> Void
    ) {
        self.eventHub = eventHub
        self.backgroundCompletions = backgroundCompletions
        self.invalidationGate = invalidationGate
        self.onInvalidation = onInvalidation
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        eventHub.sendLocation(
            location,
            taskIdentifier: assetDownloadTask.taskIdentifier
        )
    }

    #if !os(watchOS)
    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        let expectedDuration = CMTimeGetSeconds(
            timeRangeExpectedToLoad.duration
        )
        guard expectedDuration.isFinite, expectedDuration > 0 else {
            return
        }
        let loadedDuration = loadedTimeRanges.reduce(0.0) {
            partialResult,
            value in
            let duration = CMTimeGetSeconds(value.timeRangeValue.duration)
            guard duration.isFinite, duration > 0 else {
                return partialResult
            }
            return partialResult + duration
        }
        eventHub.sendProgress(
            loadedDuration / expectedDuration,
            taskIdentifier: assetDownloadTask.taskIdentifier
        )
    }

    #endif

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error else {
            eventHub.sendCompletion(
                taskIdentifier: task.taskIdentifier
            )
            return
        }
        if Self.isCancellation(error) {
            eventHub.sendTerminal(
                .cancelled,
                taskIdentifier: task.taskIdentifier
            )
        } else {
            eventHub.sendTerminal(
                .failed(SendableUnderlyingError(error)),
                taskIdentifier: task.taskIdentifier
            )
        }
    }

    func urlSessionDidFinishEvents(
        forBackgroundURLSession session: URLSession
    ) {
        backgroundCompletions.finishEvents()
    }

    func urlSession(
        _ session: URLSession,
        didBecomeInvalidWithError error: (any Error)?
    ) {
        if let error {
            eventHub.failSession(
                SendableUnderlyingError(error)
            )
        }
        backgroundCompletions.invalidate()
        invalidationGate.complete()
        onInvalidation()
    }

    static func isCancellation(_ error: any Error) -> Bool {
        let cocoaError = error as NSError
        return
            (cocoaError.domain == NSURLErrorDomain
            && cocoaError.code == NSURLErrorCancelled)
            || (cocoaError.domain == NSCocoaErrorDomain
                && cocoaError.code
                    == CocoaError.Code.userCancelled.rawValue)
    }
}

@available(macOS 14.0, iOS 16.0, watchOS 10.0, visionOS 1.0, *)
extension HLSAssetDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        willDownloadVariants variants: [AVAssetVariant]
    ) {
        eventHub.sendVariantSelection(
            HLSAssetDownloadVariantSelection(variants),
            taskIdentifier: assetDownloadTask.taskIdentifier
        )
    }
}

@available(macOS 14.0, iOS 18.0, watchOS 10.0, visionOS 1.0, *)
extension HLSAssetDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        willDownloadTo location: URL
    ) {
        eventHub.sendLocation(
            location,
            taskIdentifier: assetDownloadTask.taskIdentifier
        )
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, visionOS 26.0, *)
extension HLSAssetDownloadDelegate {
    // AVFoundation invokes this optional delegate entry point dynamically.
    // periphery:ignore
    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didReceiveMetricEvent metricEvent: AVMetricEvent
    ) {
        guard
            let summary = HLSAssetDownloadMetricMapper.map(metricEvent)
        else {
            return
        }
        eventHub.sendSummary(
            summary,
            taskIdentifier: assetDownloadTask.taskIdentifier
        )
    }
}

// UIKit supplies an ordinary non-Sendable closure. Keep that closure on the
// main actor rather than asserting that it is safe to transfer between queues.
@MainActor
final class HLSAssetDownloadApplicationCompletion {
    private var completion: (() -> Void)?

    init(_ completion: @escaping () -> Void) {
        self.completion = completion
    }

    func complete() {
        let pending = completion
        completion = nil
        pending?()
    }
}

final class HLSAssetDownloadBackgroundCompletionStore: Sendable {
    typealias Completion = @MainActor @Sendable () -> Void

    private struct State {
        var completions: [Completion] = []
        var isInvalidated = false
    }

    private let state: OSAllocatedUnfairLock<State>

    init(completion: Completion? = nil) {
        self.state = OSAllocatedUnfairLock(
            initialState: State(completions: completion.map { [$0] } ?? [])
        )
    }

    func set(_ completion: @escaping Completion) {
        let shouldComplete = state.withLock { state in
            if state.isInvalidated {
                return true
            }
            state.completions.append(completion)
            return false
        }
        if shouldComplete {
            Self.deliver([completion])
        }
    }

    func finishEvents() {
        let completions: [Completion] = state.withLock { state in
            guard !state.isInvalidated else {
                return []
            }
            // A finish without a registered handler cannot be associated
            // with a future batch. Reconnection handlers must be installed
            // before the native session is constructed.
            let completions = state.completions
            state.completions.removeAll(keepingCapacity: true)
            return completions
        }
        Self.deliver(completions)
    }

    func invalidate() {
        let completions: [Completion] = state.withLock { state in
            state.isInvalidated = true
            let completions = state.completions
            state.completions.removeAll()
            return completions
        }
        Self.deliver(completions)
    }

    static func deliver(_ completions: [Completion]) {
        guard !completions.isEmpty else {
            return
        }
        // UIKit's background-session handlers must run on the main thread.
        // Always enqueue, including foreign/invalidating-session shortcuts,
        // and never invoke application code while holding the state lock.
        DispatchQueue.main.async {
            completions.forEach { $0() }
        }
    }
}

final class HLSAssetDownloadInvalidationGate: Sendable {
    private struct State {
        var continuations: [CheckedContinuation<Void, Never>] = []
        var isComplete = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResume = state.withLock { state in
                guard !state.isComplete else {
                    return true
                }
                state.continuations.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func complete() {
        let continuations: [CheckedContinuation<Void, Never>] =
            state.withLock { state in
                guard !state.isComplete else {
                    return []
                }
                state.isComplete = true
                let continuations = state.continuations
                state.continuations.removeAll()
                return continuations
            }
        continuations.forEach {
            $0.resume()
        }
    }
}
#endif
