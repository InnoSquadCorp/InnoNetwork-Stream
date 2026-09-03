import Foundation
import os

/// HLS-local parser for RFC 9110 HTTP-date values.
enum HLSHTTPDateParser {
    private static let dateFormats = [
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEEE, dd-MMM-yy HH:mm:ss zzz",
        "EEE MMM  d HH:mm:ss yyyy",
        "EEE MMM d HH:mm:ss yyyy",
    ]

    private static let formatter = OSAllocatedUnfairLock<DateFormatter>(
        initialState: {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter
        }()
    )

    static func parse(
        _ value: String,
        requiresGMTZone: Bool = false
    ) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized =
            trimmed
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
        let candidates =
            normalized == trimmed
            ? [trimmed]
            : [trimmed, normalized]

        for candidate in candidates {
            guard !requiresGMTZone || hasGMTZoneOrNoZone(candidate) else {
                continue
            }
            if let date = parseCandidate(candidate) {
                return date
            }
        }
        return nil
    }

    private static func parseCandidate(_ value: String) -> Date? {
        formatter.withLock { formatter in
            for format in dateFormats {
                formatter.dateFormat = format
                if let date = formatter.date(from: value) {
                    return date
                }
            }
            return nil
        }
    }

    private static func hasGMTZoneOrNoZone(_ value: String) -> Bool {
        guard value.contains(",") else { return true }
        guard let zone = value.split(separator: " ").last else {
            return false
        }
        return zone.caseInsensitiveCompare("GMT") == .orderedSame
    }
}
