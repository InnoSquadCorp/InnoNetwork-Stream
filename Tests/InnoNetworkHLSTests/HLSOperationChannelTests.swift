import Foundation
import Testing

@testable import InnoNetworkHLS

@Suite("Independent operation delivery")
struct HLSOperationChannelTests {
    @Test("slow independent subscriptions remain bounded and replay the terminal snapshot")
    func delivery() async throws {
        let channel = HLSOperationChannel<Int, Int>()
        let first = try channel.subscribe(buffer: 1)
        let second = try channel.subscribe(buffer: 2)
        for value in 1...20 { channel.emit(value) }
        channel.finish(.success(42))
        channel.finish(.failure(CancellationError()))
        let a = try await first.reduce(into: []) { $0.append($1) }
        let b = try await second.reduce(into: []) { $0.append($1) }
        #expect(a.map(\.event) == [20])
        #expect(a.first?.sequence == 20)
        #expect(a.first?.droppedEventCount == 18)
        #expect(b.map(\.event) == [19, 20])
        #expect(channel.state == .completed)
        #expect(try await channel.value() == 42)
        let replay = try await channel.subscribe().reduce(into: []) { $0.append($1.event) }
        #expect(replay == [20])
    }

    @Test("cancelled result waiter never cancels operation or survivor")
    func waiterCancellation() async throws {
        let channel = HLSOperationChannel<Int, Int>()
        let waiter = Task { try await channel.value() }
        waiter.cancel()
        do {
            _ = try await waiter.value
            Issue.record("Expected cancellation")
        } catch { #expect(error is CancellationError) }
        #expect(channel.state == .running)
        let survivor = Task { try await channel.value() }
        channel.finish(.success(7))
        #expect(try await survivor.value == 7)
    }

    @Test("subscription capacity rejects admission without affecting existing observers")
    func capacity() async throws {
        let channel = HLSOperationChannel<Int, Int>()
        var streams: [AsyncThrowingStream<HLSOperationObservation<Int>, Error>] = []
        for _ in 0..<64 { streams.append(try channel.subscribe()) }
        #expect(throws: HLSOperationObservationError.capacityExceeded) { try channel.subscribe() }
        channel.emit(1)
        channel.finish(.success(2))
        for stream in streams {
            let values = try await stream.reduce(into: []) { $0.append($1.event) }
            #expect(values == [1])
        }
    }
}
