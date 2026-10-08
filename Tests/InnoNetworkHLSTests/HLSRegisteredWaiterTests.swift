import Testing

@testable import InnoNetworkHLS

@Suite("Registered operation waiters")
struct HLSRegisteredWaiterTests {
    @Test("registered cancellation releases capacity without stopping survivors")
    func capacityReuse() async throws {
        let channel = HLSOperationChannel<Int, Int>()
        var waiters = (0..<64).map { _ in Task { try await channel.value() } }
        defer {
            for waiter in waiters { waiter.cancel() }
            channel.finish(.success(7))
        }
        do {
            try await registeredEventually { channel.pendingWaiterCount == 64 }
            await #expect(throws: HLSOperationObservationError.capacityExceeded) { try await channel.value() }
            waiters[0].cancel()
            await #expect(throws: CancellationError.self) { try await waiters[0].value }
            #expect(channel.pendingWaiterCount == 63)
            waiters.append(Task { try await channel.value() })
            try await registeredEventually { channel.pendingWaiterCount == 64 }
            channel.finish(.success(7))
            for waiter in waiters.dropFirst() { #expect(try await waiter.value == 7) }
            #expect(channel.pendingWaiterCount == 0)
        } catch {
            for waiter in waiters { waiter.cancel() }
            channel.finish(.success(7))
            for waiter in waiters { _ = await waiter.result }
            throw error
        }
    }

    @Test("registered finish and cancellation ordering", arguments: [false, true])
    func orderedCompletion(cancelFirst: Bool) async throws {
        let channel = HLSOperationChannel<Int, Int>()
        let waiter = Task { try await channel.value() }
        defer {
            waiter.cancel()
            channel.finish(.success(7))
        }
        try await registeredEventually { channel.pendingWaiterCount == 1 }
        if cancelFirst {
            waiter.cancel()
            await #expect(throws: CancellationError.self) { try await waiter.value }
            channel.finish(.success(7))
        } else {
            channel.finish(.success(7))
            waiter.cancel()
            #expect(try await waiter.value == 7)
        }
        #expect(channel.state == .completed)
        #expect(channel.pendingWaiterCount == 0)
        let late = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await channel.value()
        }
        #expect(try await late.value == 7)
    }

    @Test("registered finish cancellation races settle exactly once")
    func completionRace() async throws {
        for _ in 0..<200 {
            let channel = HLSOperationChannel<Int, Int>()
            let waiter = Task { try await channel.value() }
            do { try await registeredEventually { channel.pendingWaiterCount == 1 } } catch {
                waiter.cancel()
                _ = await waiter.result
                throw error
            }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { channel.finish(.success(7)) }
                group.addTask { waiter.cancel() }
            }
            switch await waiter.result {
            case .success(let value): #expect(value == 7)
            case .failure(let error): #expect(error is CancellationError)
            }
            #expect(channel.state == .completed)
            #expect(channel.pendingWaiterCount == 0)
        }
    }
}

private func registeredEventually(_ condition: @Sendable () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw RegisteredWaiterTimeout() }
        try Task.checkCancellation()
        await Task.yield()
    }
}
private struct RegisteredWaiterTimeout: Error {}
