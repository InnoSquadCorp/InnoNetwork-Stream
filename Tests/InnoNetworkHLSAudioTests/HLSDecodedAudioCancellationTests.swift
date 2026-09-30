#if compiler(>=6.4) && canImport(AVFoundation)
import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import InnoNetworkHLSAudio

@Suite("Decoded audio client/native completion ownership")
@MainActor
struct HLSDecodedAudioCancellationTests {
    @Test("Cancelled waiter releases promptly without admitting another native reader")
    @available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
    func cancelPendingRead() async throws {
        let reads = HLSDecodedAudioReadCoordinator()
        let native = HeldAudioRead()
        let waiter = Task { try await reads.next { await native.read() } }
        await native.waitForEntry()
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(native.calls == 1)
        #expect(throws: HLSDecodedAudioError.readAlreadyInProgress) { try reads.checkAdmission() }
        await #expect(throws: HLSDecodedAudioError.readAlreadyInProgress) {
            try await reads.next {
                Issue.record("Second native read must not start")
                return nil
            }
        }
        native.finish(Self.marker())
        await native.waitForExit()
        await Task.yield()
        #expect(try await reads.next { nil } == nil)
        reads.detach()
    }

    @Test("Detachment completes client once and rejects every later read")
    @available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
    func detachPendingRead() async throws {
        let reads = HLSDecodedAudioReadCoordinator()
        let native = HeldAudioRead()
        let waiter = Task { try await reads.next { await native.read() } }
        await native.waitForEntry()
        reads.detach()
        reads.detach()
        await #expect(throws: HLSDecodedAudioError.outputDetached) { try await waiter.value }
        waiter.cancel()
        native.finish(nil)
        await native.waitForExit()
        #expect(throws: HLSDecodedAudioError.outputDetached) { try reads.checkAdmission() }
    }

    @Test("Normal sample and end preserve delivery and release the read slot")
    @available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
    func normalCompletion() async throws {
        let reads = HLSDecodedAudioReadCoordinator()
        let sample = try #require(try await reads.next { Self.marker() })
        #expect(sample.isMarkerOnly)
        #expect(sample.sequenceWasRestarted)
        #expect(try await reads.next { nil } == nil)
        try reads.checkAdmission()
    }

    @Test("Pending native work does not retain a cancelled coordinator")
    @available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
    func cancelledOwnerLifetime() async throws {
        let native = HeldAudioRead()
        var reads: HLSDecodedAudioReadCoordinator? = HLSDecodedAudioReadCoordinator()
        weak var weakReads = reads
        let waiter = Task { [owner = try #require(reads)] in try await owner.next { await native.read() } }
        await native.waitForEntry()
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        reads = nil
        #expect(weakReads == nil)
        native.finish(nil)
        await native.waitForExit()
    }

    @Test("Already cancelled clients never start native work")
    @available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
    func cancelledBeforeAdmission() async throws {
        let reads = HLSDecodedAudioReadCoordinator()
        let waiter = Task {
            await Task.yield()
            return try await reads.next {
                Issue.record("Cancelled native work started")
                return nil
            }
        }
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        try reads.checkAdmission()
    }

    @Test("Cancellation/completion races resume only once, including before installation")
    @available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
    func completionRaces() async throws {
        for _ in 0..<100 {
            let completion = HLSDecodedAudioReadCompletion()
            completion.finish(.failure(CancellationError()))
            completion.finish(.success(Self.marker()))
            await #expect(throws: CancellationError.self) {
                try await withCheckedThrowingContinuation { completion.install($0) }
            }
            let raced = HLSDecodedAudioReadCompletion()
            let result = Task { try await withCheckedThrowingContinuation { raced.install($0) } }
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<8 {
                    group.addTask {
                        raced.finish(index.isMultiple(of: 2) ? .success(nil) : .failure(CancellationError()))
                    }
                }
            }
            do { #expect(try await result.value == nil) } catch { #expect(error is CancellationError) }
        }
    }

    @Test("Actual unplayed output cancellation completes without detaching the caller item")
    @available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
    func nativePendingRead() async throws {
        let item = AVPlayerItem(url: try #require(URL(string: "https://review.invalid/unplayed.m3u8")))
        let output = HLSDecodedAudioOutput(playerItem: item, configuration: try .float32())
        defer { output.detach() }
        var entered = false
        var completed = false
        var cancelled = false
        let waiter = Task {
            entered = true
            do { _ = try await output.nextSample() } catch { cancelled = error is CancellationError }
            completed = true
        }
        while !entered { await Task.yield() }
        #expect(throws: HLSDecodedAudioError.readAlreadyInProgress) { try output.nextAvailableSample() }
        waiter.cancel()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !completed && clock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(completed && cancelled)
        #expect(output.isAttached)
        #expect(item.outputs.contains { $0 === output.output })
        if completed { await waiter.value }
    }

    @available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
    private static func marker() -> HLSDecodedAudioSample {
        let marker = CMReadySampleBuffer<Never>(markerAt: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600))
        return HLSDecodedAudioSample(
            .init(sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(marker), sequenceWasRestarted: true))
    }
}

@available(macOS 27, iOS 27, tvOS 27, watchOS 27, visionOS 27, *)
@MainActor
private final class HeldAudioRead {
    private var entry: CheckedContinuation<Void, Never>?
    private var exit: CheckedContinuation<Void, Never>?
    private var result: CheckedContinuation<HLSDecodedAudioSample?, Never>?
    private var didExit = false
    private(set) var calls = 0
    func read() async -> HLSDecodedAudioSample? {
        calls += 1
        let sample = await withCheckedContinuation { continuation in
            result = continuation
            entry?.resume()
            entry = nil
        }
        didExit = true
        exit?.resume()
        exit = nil
        return sample
    }
    func waitForEntry() async {
        if result == nil { await withCheckedContinuation { entry = $0 } }
    }
    func finish(_ sample: HLSDecodedAudioSample?) {
        result?.resume(returning: sample)
        result = nil
    }
    func waitForExit() async {
        if !didExit { await withCheckedContinuation { exit = $0 } }
    }
}
#endif
