import Foundation

struct HLSVariableExpansion: Sendable {
    let contents: String
    let variables: [String: String]
    let containsDefinitions: Bool
    let containsImports: Bool
    let containsQueryParameters: Bool
}

enum HLSVariableSubstituter {
    static func expand(
        _ playlist: String,
        sourceURL: URL,
        multivariantVariables: [String: String]?,
        maximumBytes: Int
    ) throws -> HLSVariableExpansion {
        let lines =
            playlist
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let queryItems =
            URLComponents(
                url: sourceURL,
                resolvingAgainstBaseURL: true
            )?.queryItems ?? []
        var variables: [String: String] = [:]
        var output: [String] = []
        var outputByteCount = 0
        var containsDefinitions = false
        var containsImports = false
        var containsQueryParameters = false

        for line in lines {
            if line.hasPrefix("#EXT-X-DEFINE:") {
                containsDefinitions = true
                let attributes = try HLSAttributeListParser.parse(
                    String(line.dropFirst("#EXT-X-DEFINE:".count))
                )
                let selectors = ["NAME", "IMPORT", "QUERYPARAM"].filter {
                    attributes[$0] != nil
                }
                guard selectors.count == 1 else {
                    throw HLSDownloadError.invalidPlaylist
                }

                let name: String
                let value: String
                switch selectors[0] {
                case "NAME":
                    guard
                        let declaredName = attributes["NAME"],
                        let declaredValue = attributes["VALUE"],
                        attributes.isQuoted("NAME"),
                        attributes.isQuoted("VALUE")
                    else {
                        throw HLSDownloadError.invalidPlaylist
                    }
                    name = declaredName
                    value = declaredValue
                case "IMPORT":
                    guard
                        attributes["VALUE"] == nil,
                        let importedName = attributes["IMPORT"],
                        attributes.isQuoted("IMPORT"),
                        let importedValue = multivariantVariables?[importedName]
                    else {
                        throw HLSDownloadError.invalidPlaylist
                    }
                    name = importedName
                    value = importedValue
                    containsImports = true
                case "QUERYPARAM":
                    guard
                        attributes["VALUE"] == nil,
                        let queryName = attributes["QUERYPARAM"],
                        attributes.isQuoted("QUERYPARAM"),
                        let queryValue = queryItems.first(where: {
                            $0.name == queryName && $0.value != nil
                        })?.value,
                        isValidQuotedString(queryValue)
                    else {
                        throw HLSDownloadError.invalidPlaylist
                    }
                    name = queryName
                    value = queryValue
                    containsQueryParameters = true
                default:
                    throw HLSDownloadError.invalidPlaylist
                }

                guard
                    isValidVariableName(name),
                    variables.updateValue(value, forKey: name) == nil
                else {
                    throw HLSDownloadError.invalidPlaylist
                }
                continue
            }

            // Include the newline in the reservation, before building a line.
            // The final-output bound alone cannot stop multiplicative variable
            // references from allocating a huge intermediate string.
            guard outputByteCount < maximumBytes else {
                throw HLSDownloadError.playlistTooLarge(limit: maximumBytes)
            }
            let remainingBytes = maximumBytes - outputByteCount - 1
            let expandedLine: String
            if !line.isEmpty, !line.hasPrefix("#") {
                expandedLine = try substituteReferences(
                    in: line,
                    variables: variables,
                    maximumBytes: remainingBytes,
                    reportedLimit: maximumBytes
                )
            } else if line.hasPrefix("#EXT-X-"), line.contains(":") {
                expandedLine = try substituteAttributeValues(
                    in: line,
                    variables: variables,
                    maximumBytes: remainingBytes,
                    reportedLimit: maximumBytes
                )
            } else {
                expandedLine = line
            }
            let expandedByteCount = expandedLine.utf8.count
            guard expandedByteCount <= remainingBytes else {
                throw HLSDownloadError.playlistTooLarge(limit: maximumBytes)
            }
            // The reservation proves both additions fit before arithmetic.
            outputByteCount += expandedByteCount + 1
            output.append(expandedLine)
        }

        while output.last?.isEmpty == true {
            output.removeLast()
        }
        return HLSVariableExpansion(
            contents: output.joined(separator: "\n") + "\n",
            variables: variables,
            containsDefinitions: containsDefinitions,
            containsImports: containsImports,
            containsQueryParameters: containsQueryParameters
        )
    }

    private static func substituteAttributeValues(
        in line: String,
        variables: [String: String],
        maximumBytes: Int,
        reportedLimit: Int
    ) throws -> String {
        guard let colon = line.firstIndex(of: ":") else {
            return line
        }
        let prefix = line[...colon]
        let value = line[line.index(after: colon)...]
        var output = BoundedOutput(
            maximumBytes: maximumBytes,
            reportedLimit: reportedLimit
        )
        try output.append(prefix)
        var index = value.startIndex
        var fieldStart = index
        var isQuoted = false

        while index <= value.endIndex {
            let isAtEnd = index == value.endIndex
            if !isAtEnd, value[index] == "\"" {
                isQuoted.toggle()
            }
            if isAtEnd || (!isQuoted && value[index] == ",") {
                let field = String(value[fieldStart..<index])
                let expandedField = try substituteAttributeField(
                    field,
                    variables: variables,
                    maximumBytes: output.remainingBytes,
                    reportedLimit: reportedLimit
                )
                try output.append(expandedField)
                if !isAtEnd {
                    try output.append(",")
                    index = value.index(after: index)
                    fieldStart = index
                    continue
                }
                break
            }
            index = value.index(after: index)
        }
        guard !isQuoted else {
            throw HLSDownloadError.invalidPlaylist
        }
        return output.value
    }

    private static func substituteAttributeField(
        _ field: String,
        variables: [String: String],
        maximumBytes: Int,
        reportedLimit: Int
    ) throws -> String {
        guard let equals = field.firstIndex(of: "=") else {
            return field
        }
        let name = field[...equals]
        let rawValue = String(field[field.index(after: equals)...])
        let trimmedValue = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let leadingWhitespaceCount = rawValue.prefix {
            $0.isWhitespace
        }.count
        let trailingWhitespaceCount = rawValue.reversed().prefix {
            $0.isWhitespace
        }.count
        let leadingWhitespace = String(
            rawValue.prefix(leadingWhitespaceCount)
        )
        let trailingWhitespace = String(
            rawValue.suffix(trailingWhitespaceCount)
        )

        if trimmedValue.first == "\"", trimmedValue.last == "\"",
            trimmedValue.count >= 2
        {
            let interior = String(trimmedValue.dropFirst().dropLast())
            var output = BoundedOutput(
                maximumBytes: maximumBytes,
                reportedLimit: reportedLimit
            )
            try output.append(name)
            try output.append(leadingWhitespace)
            try output.append("\"")
            try output.append(
                substituteReferences(
                    in: interior,
                    variables: variables,
                    maximumBytes: output.remainingBytes,
                    reportedLimit: reportedLimit
                )
            )
            try output.append("\"")
            try output.append(trailingWhitespace)
            return output.value
        }

        if trimmedValue.lowercased().hasPrefix("0x")
            || trimmedValue.contains("{$")
        {
            let expanded = try substituteReferences(
                in: trimmedValue,
                variables: variables,
                maximumBytes: maximumBytes,
                reportedLimit: reportedLimit
            )
            guard
                expanded.lowercased().hasPrefix("0x"),
                !expanded.dropFirst(2).isEmpty,
                expanded.dropFirst(2).allSatisfy(\.isHexDigit)
            else {
                throw HLSDownloadError.invalidPlaylist
            }
            var output = BoundedOutput(
                maximumBytes: maximumBytes,
                reportedLimit: reportedLimit
            )
            try output.append(name)
            try output.append(leadingWhitespace)
            try output.append(expanded)
            try output.append(trailingWhitespace)
            return output.value
        }
        return field
    }

    private static func substituteReferences(
        in value: String,
        variables: [String: String],
        maximumBytes: Int,
        reportedLimit: Int
    ) throws -> String {
        var output = BoundedOutput(
            maximumBytes: maximumBytes,
            reportedLimit: reportedLimit
        )
        var index = value.startIndex

        while index < value.endIndex {
            guard value[index...].hasPrefix("{$") else {
                try output.append(String(value[index]))
                index = value.index(after: index)
                continue
            }
            let nameStart = value.index(index, offsetBy: 2)
            guard
                let closingBrace = value[nameStart...].firstIndex(of: "}")
            else {
                throw HLSDownloadError.invalidPlaylist
            }
            let name = String(value[nameStart..<closingBrace])
            guard
                isValidVariableName(name),
                let replacement = variables[name]
            else {
                throw HLSDownloadError.invalidPlaylist
            }
            try output.append(replacement)
            index = value.index(after: closingBrace)
        }
        return output.value
    }

    private struct BoundedOutput {
        let maximumBytes: Int
        let reportedLimit: Int
        private(set) var value = ""
        private var byteCount = 0

        var remainingBytes: Int { maximumBytes - byteCount }

        mutating func append(_ text: some StringProtocol) throws {
            let count = text.utf8.count
            guard count <= remainingBytes else {
                throw HLSDownloadError.playlistTooLarge(limit: reportedLimit)
            }
            byteCount += count
            value.append(contentsOf: text)
        }
    }

    private static func isValidVariableName(_ value: String) -> Bool {
        !value.isEmpty
            && value.allSatisfy {
                $0.isASCII
                    && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
            }
    }

    private static func isValidQuotedString(_ value: String) -> Bool {
        !value.contains("\"")
            && !value.contains("\r")
            && !value.contains("\n")
    }
}
