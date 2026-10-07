import Foundation
import os

// Hold two response completions until both transports have entered. A safety
// release unblocks a broken serialized implementation but can never certify
// overlap, even if the second request subsequently arrives.
final class HLSURLProtocolResponseGate: Sendable {
    private struct State {
        var completions: [@Sendable () -> Void] = []
        var released = false
        var overlapped = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var didOverlap: Bool {
        state.withLock { $0.overlapped }
    }

    var heldResponseCount: Int {
        state.withLock { $0.completions.count }
    }

    func arrive(_ completion: @escaping @Sendable () -> Void) {
        let ready = state.withLock { state -> [@Sendable () -> Void] in
            guard !state.released else { return [completion] }
            state.completions.append(completion)
            guard state.completions.count == 2 else { return [] }
            state.overlapped = true
            state.released = true
            let ready = state.completions
            state.completions.removeAll()
            return ready
        }
        for completion in ready {
            completion()
        }
    }

    func releaseForSafety() {
        let ready = state.withLock { state -> [@Sendable () -> Void] in
            state.released = true
            let ready = state.completions
            state.completions.removeAll()
            return ready
        }
        for completion in ready {
            completion()
        }
    }
}
