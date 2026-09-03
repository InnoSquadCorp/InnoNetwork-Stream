import Foundation

/// Internal time seam shared by HLS planners and retry integration.
package protocol HLSClock: Sendable {
    func sleep(for duration: Duration) async throws
    func now() -> Date
}

package struct HLSSystemClock: HLSClock {
    package init() {}

    package func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }

    package func now() -> Date {
        Date()
    }
}

extension Duration {
    var hlsTimeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
