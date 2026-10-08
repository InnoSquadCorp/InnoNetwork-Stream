#if canImport(AVFoundation) && !os(tvOS)
import AVFoundation
import Foundation
import Testing
import os

@testable import InnoNetworkHLSAVFoundation

@MainActor
@Suite("AVFoundation background completion lifecycle")
struct HLSAssetDownloadBackgroundCompletionTests {
    @Test("all registered handlers are delivered once on the main thread")
    func registeredHandlersFinishOnMainThread() async {
        let store = HLSAssetDownloadBackgroundCompletionStore()
        let calls = OSAllocatedUnfairLock(initialState: [Bool]())
        for _ in 0..<2 {
            store.set {
                calls.withLock { $0.append(Thread.isMainThread) }
            }
        }

        await Task.detached {
            store.finishEvents()
            store.finishEvents()
        }.value
        await flushMainQueue()

        #expect(calls.withLock { $0 } == [true, true])
    }

    @Test("preconstruction registration survives immediate restored events")
    func preconstructionRegistration() async {
        let calls = OSAllocatedUnfairLock(initialState: [Bool]())
        let store = HLSAssetDownloadBackgroundCompletionStore {
            calls.withLock { $0.append(Thread.isMainThread) }
        }
        // The delegate may finish synchronously with native session creation.
        // Its handler is already installed by the store initializer.
        store.finishEvents()
        store.invalidate()
        await flushMainQueue()

        #expect(calls.withLock { $0 } == [true])
    }

    @Test("ordinary application closures stay main-actor owned across native delivery")
    func nonSendableApplicationCompletion() async {
        let captured = ApplicationCallbackState()
        let applicationCompletion: () -> Void = {
            captured.calls.append(Thread.isMainThread)
        }
        let owner = HLSAssetDownloadApplicationCompletion(applicationCompletion)
        let store = HLSAssetDownloadBackgroundCompletionStore {
            owner.complete()
        }

        await Task.detached {
            store.finishEvents()
            store.invalidate()
        }.value
        await flushMainQueue()
        owner.complete()

        #expect(captured.calls == [true])
    }

    @Test("unclaimed and duplicate finishes never release a later batch")
    func finishesDoNotLeakAcrossBatches() async {
        let store = HLSAssetDownloadBackgroundCompletionStore()
        let calls = OSAllocatedUnfairLock(initialState: 0)
        store.finishEvents()
        store.finishEvents()
        store.set { calls.withLock { $0 += 1 } }
        await flushMainQueue()
        #expect(calls.withLock { $0 } == 0)

        store.finishEvents()
        store.finishEvents()
        await flushMainQueue()
        #expect(calls.withLock { $0 } == 1)

        store.set { calls.withLock { $0 += 1 } }
        await flushMainQueue()
        #expect(calls.withLock { $0 } == 1)
        store.finishEvents()
        await flushMainQueue()
        #expect(calls.withLock { $0 } == 2)
    }

    @Test("invalidation drains pending and future handlers exactly once")
    func invalidationClosesRegistration() async {
        let store = HLSAssetDownloadBackgroundCompletionStore()
        let calls = OSAllocatedUnfairLock(initialState: [Bool]())
        store.set { calls.withLock { $0.append(Thread.isMainThread) } }
        await Task.detached {
            store.invalidate()
            store.invalidate()
            store.finishEvents()
            store.set { calls.withLock { $0.append(Thread.isMainThread) } }
        }.value
        await flushMainQueue()

        #expect(calls.withLock { $0 } == [true, true])
    }

    @Test("registration racing finish and invalidation cannot lose or repeat a handler")
    func concurrentRegistrationAndInvalidation() async {
        let calls = OSAllocatedUnfairLock(initialState: [Bool]())
        for _ in 0..<64 {
            let store = HLSAssetDownloadBackgroundCompletionStore()
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    store.set {
                        calls.withLock { $0.append(Thread.isMainThread) }
                    }
                }
                group.addTask { store.finishEvents() }
                group.addTask { store.invalidate() }
            }
        }
        await flushMainQueue()

        #expect(calls.withLock { $0.count } == 64)
        #expect(calls.withLock { $0.allSatisfy { $0 } })
    }

    @Test("delegate finish and invalidation both use the main-thread delivery path")
    func nativeDelegateDelivery() async {
        let store = HLSAssetDownloadBackgroundCompletionStore()
        let calls = OSAllocatedUnfairLock(initialState: [Bool]())
        let delegate = HLSAssetDownloadDelegate(
            eventHub: HLSAssetDownloadEventHub(),
            backgroundCompletions: store,
            invalidationGate: HLSAssetDownloadInvalidationGate(),
            onInvalidation: {}
        )
        store.set { calls.withLock { $0.append(Thread.isMainThread) } }
        await Task.detached {
            delegate.urlSessionDidFinishEvents(
                forBackgroundURLSession: .shared
            )
            delegate.urlSession(.shared, didBecomeInvalidWithError: nil)
        }.value
        await flushMainQueue()

        #expect(calls.withLock { $0 } == [true])
    }

    private func flushMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

// Deliberately non-Sendable, like state captured by a UIKit completion.
private final class ApplicationCallbackState {
    var calls: [Bool] = []
}
#endif
