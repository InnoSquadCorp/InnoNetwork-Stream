import Foundation

/// Shared media response validation; Core continues to own bounded transport.
package struct HLSContentRange {
    package let offset: Int64
    package let length: Int64

    package init?(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.lowercased().hasPrefix("bytes ") else { return nil }
        let fields = value.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
        guard fields.count == 2 else { return nil }
        let bounds = fields[0].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2,
            let lower = Self.decimal(bounds[0]), let upper = Self.decimal(bounds[1]), upper >= lower
        else { return nil }
        let (length, overflow) = (upper - lower).addingReportingOverflow(1)
        guard !overflow else { return nil }
        if fields[1] != "*" {
            guard let total = Self.decimal(fields[1]), total > upper else { return nil }
        }
        self.offset = lower
        self.length = length
    }

    private static func decimal(_ value: Substring) -> Int64? {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int64(value)
    }
}
