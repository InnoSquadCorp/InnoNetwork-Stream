#if compiler(>=6.4)
import Foundation
import os

/// Separates the cancellable client wait from one potentially uncancellable SDK
/// read. The SDK task is retained until it actually returns; cancelled samples
/// are discarded and never transferred to a later client.
@available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
@MainActor
final class HLSDecodedAudioReadCoordinator {
    private var worker: Task<Void, Never>?
    private var completion: HLSDecodedAudioReadCompletion?
    private var isDetached = false

    deinit { worker?.cancel() }

    func checkAdmission() throws(HLSDecodedAudioError) {
        guard !isDetached else { throw .outputDetached }
        guard worker == nil else { throw .readAlreadyInProgress }
    }

    func next(
        read: @escaping @MainActor @Sendable () async -> HLSDecodedAudioSample?
    ) async throws -> HLSDecodedAudioSample? {
        try checkAdmission()
        try Task.checkCancellation()
        let completion = HLSDecodedAudioReadCompletion()
        // A structured task group would wait for the native read on scope exit
        // and defeat client cancellation. This single owned task never captures
        // the wrapper or caller's player and cannot admit a second SDK read.
        let worker = Task { [weak self] in
            defer {
                self?.worker = nil
                self?.completion = nil
            }
            guard !Task.isCancelled else {
                completion.finish(.failure(CancellationError()))
                return
            }
            let sample = await read()
            completion.finish(.success(sample))
        }
        self.worker = worker
        self.completion = completion
        let sample = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { completion.install($0) }
        } onCancel: {
            worker.cancel()
            completion.finish(.failure(CancellationError()))
        }
        try Task.checkCancellation()
        guard !isDetached else { throw HLSDecodedAudioError.outputDetached }
        return sample
    }

    func detach() {
        guard !isDetached else { return }
        isDetached = true
        worker?.cancel()
        completion?.finish(.failure(HLSDecodedAudioError.outputDetached))
    }
}

/// Cancellation runs outside MainActor. Only the once-only continuation result
/// crosses that boundary; SDK access and read admission remain actor-isolated.
@available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
final class HLSDecodedAudioReadCompletion: Sendable {
    private enum State {
        case pending
        case waiting(CheckedContinuation<HLSDecodedAudioSample?, any Error>)
        case finished(Result<HLSDecodedAudioSample?, any Error>)
        case consumed
    }
    private let state = OSAllocatedUnfairLock(initialState: State.pending)

    func install(_ continuation: CheckedContinuation<HLSDecodedAudioSample?, any Error>) {
        let result = state.withLock { state -> Result<HLSDecodedAudioSample?, any Error>? in
            switch state {
            case .pending:
                state = .waiting(continuation)
                return nil
            case .finished(let result):
                state = .consumed
                return result
            case .waiting, .consumed:
                preconditionFailure("Decoded audio continuation must be installed once")
            }
        }
        if let result { continuation.resume(with: result) }
    }

    func finish(_ result: Result<HLSDecodedAudioSample?, any Error>) {
        let continuation = state.withLock { state -> CheckedContinuation<HLSDecodedAudioSample?, any Error>? in
            switch state {
            case .pending:
                state = .finished(result)
                return nil
            case .waiting(let continuation):
                state = .consumed
                return continuation
            case .finished, .consumed:
                return nil
            }
        }
        continuation?.resume(with: result)
    }
}
#endif
