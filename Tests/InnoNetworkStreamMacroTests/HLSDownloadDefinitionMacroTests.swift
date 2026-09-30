import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import InnoNetworkStreamMacros

@Suite("Stream download definition expansion")
struct HLSDownloadDefinitionMacroTests {
    private let macros: [String: Macro.Type] = ["HLSDownloadDefinition": HLSDownloadDefinitionMacro.self]

    @Test("public declarations produce validated runtime configuration and conformance")
    func publicExpansion() {
        assertMacroExpansion(
            """
            @HLSDownloadDefinition(maximumMediaResourceBytes: 1_024, maximumTotalDownloadBytes: 4_096, maximumConcurrentResourceTransfers: 2)
            public enum MovieDownload {}
            """,
            expandedSource: """
                public enum MovieDownload {

                    public static func configuration() throws -> InnoNetworkHLS.HLSDownloadConfiguration {
                        try InnoNetworkHLS.HLSDownloadConfiguration.validated(
                            maximumMediaResourceBytes: 1024,
                            maximumTotalDownloadBytes: 4096,
                            maximumConcurrentResourceTransfers: 2
                        )
                    }
                }

                extension MovieDownload: InnoNetworkHLS.HLSDownloadDefining {
                }
                """,
            macros: macros
        )
    }

    @Test("default definitions retain the same runtime limits in every configuration")
    func defaultExpansion() {
        assertMacroExpansion(
            """
            @HLSDownloadDefinition
            struct Download {}
            """,
            expandedSource: """
                struct Download {

                    static func configuration() throws -> InnoNetworkHLS.HLSDownloadConfiguration {
                        try InnoNetworkHLS.HLSDownloadConfiguration.validated(
                            maximumMediaResourceBytes: 134217728,
                            maximumTotalDownloadBytes: 8589934592,
                            maximumConcurrentResourceTransfers: 3
                        )
                    }
                }

                extension Download: InnoNetworkHLS.HLSDownloadDefining {
                }
                """,
            macros: macros
        )
    }

    @Test(
        "invalid constant limits diagnose once",
        arguments: [
            ("maximumConcurrentResourceTransfers: 9", "maximumConcurrentResourceTransfers must be in 1...8."),
            ("maximumTotalDownloadBytes: 1", "maximumMediaResourceBytes must not exceed maximumTotalDownloadBytes."),
            (
                "maximumMediaResourceBytes: 0",
                "@HLSDownloadDefinition limits must be positive decimal integer literals; use validated() for dynamic settings."
            ),
            (
                "maximumMediaResourceBytes: dynamicLimit",
                "@HLSDownloadDefinition limits must be positive decimal integer literals; use validated() for dynamic settings."
            ),
            (
                "maximumMediaResourceBytes: 9223372036854775808",
                "@HLSDownloadDefinition limits must be positive decimal integer literals; use validated() for dynamic settings."
            ),
            (
                "maximumMediaResourceBytes: 2147483648",
                "maximumMediaResourceBytes must fit a signed 32-bit Int on every supported platform."
            ),
            ("unknown: 3", "@HLSDownloadDefinition accepts each supported limit label once."),
        ])
    func invalidLimit(argument: String, message: String) {
        assertMacroExpansion(
            "@HLSDownloadDefinition(\(argument))\nenum Download {}",
            expandedSource: "enum Download {}",
            diagnostics: [DiagnosticSpec(message: message, line: 1, column: 1)],
            macros: macros
        )
    }

    @Test("invalid declaration and conflicting generated member are diagnosed")
    func invalidDeclaration() {
        assertMacroExpansion(
            "@HLSDownloadDefinition\nstruct Download: HLSDownloadDefining {}",
            expandedSource: "struct Download: HLSDownloadDefining {}",
            diagnostics: [
                DiagnosticSpec(
                    message: "@HLSDownloadDefinition adds HLSDownloadDefining; remove the explicit conformance.",
                    line: 1, column: 1
                )
            ],
            macros: macros
        )
        assertMacroExpansion(
            "@HLSDownloadDefinition\nclass Download {}",
            expandedSource: "class Download {}",
            diagnostics: [
                DiagnosticSpec(
                    message: "@HLSDownloadDefinition requires a struct or enum declaration.", line: 1, column: 1)
            ],
            macros: macros
        )
        assertMacroExpansion(
            "@HLSDownloadDefinition\nstruct Download {\n    static func configuration() {}\n}",
            expandedSource: "struct Download {\n    static func configuration() {}\n}",
            diagnostics: [
                DiagnosticSpec(
                    message: "@HLSDownloadDefinition owns configuration(); remove the conflicting member.", line: 1,
                    column: 1)
            ],
            macros: macros
        )
    }
}
