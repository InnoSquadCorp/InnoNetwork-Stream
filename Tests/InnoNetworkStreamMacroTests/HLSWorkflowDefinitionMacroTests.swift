import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import InnoNetworkStreamMacros

@Suite("Workflow definition expansion")
struct HLSWorkflowDefinitionMacroTests {
    @Test(arguments: ["HLSLiveDefinition", "HLSDVRDefinition", "HLSPlaybackDefinition", "HLSCatalogDefinition"])
    func defaultExpansion(_ name: String) {
        let live = name == "HLSLiveDefinition"
        let dvr = name == "HLSDVRDefinition"
        let catalog = name == "HLSCatalogDefinition"
        let module = catalog ? "InnoNetworkHLS" : live || dvr ? "InnoNetworkHLSLive" : "InnoNetworkHLSAVFoundation"
        let configuration =
            catalog
            ? "HLSMediaCatalogConfiguration"
            : live ? "HLSLiveConfiguration" : dvr ? "HLSLiveDVRConfiguration" : "HLSPlaybackConfiguration"
        let conformance =
            catalog ? "HLSCatalogDefining" : live ? "HLSLiveDefining" : dvr ? "HLSDVRDefining" : "HLSPlaybackDefining"
        let arguments =
            catalog
            ? "maximumEntries: 512, maximumSnapshotBytes: 1048576"
            : live
                ? "minimumPollingMilliseconds: 500, maximumPollingMilliseconds: 30000, requestTimeoutSeconds: 45"
                : dvr
                    ? "maximumDurationSeconds: 1800, maximumSegmentCount: 900, maximumMediaResourceBytes: 134217728, maximumTotalMediaBytes: 8589934592"
                    : "maximumPeakBitRate: 10000000, maximumWidth: 1920, maximumHeight: 1080"
        assertMacroExpansion(
            "@\(name)\npublic enum Workflow {}",
            expandedSource: """
                public enum Workflow {

                    public static func configuration() throws -> \(module).\(configuration) {
                        try \(module).\(configuration).validated(\(arguments))
                    }
                }

                extension Workflow: \(module).\(conformance) {
                }
                """, macros: [name: HLSWorkflowDefinitionMacro.self])
    }

    @Test("cross-field timing fails at compile time")
    func invalidTiming() {
        assertMacroExpansion(
            "@HLSLiveDefinition(minimumPollingMilliseconds: 1000, maximumPollingMilliseconds: 50)\nenum Workflow {}",
            expandedSource: "enum Workflow {}",
            diagnostics: [
                DiagnosticSpec(
                    message: "minimumPollingMilliseconds must not exceed maximumPollingMilliseconds.", line: 1,
                    column: 1)
            ], macros: ["HLSLiveDefinition": HLSWorkflowDefinitionMacro.self])
    }

    @Test("cross-field byte limits fail at compile time")
    func invalidBytes() {
        assertMacroExpansion(
            "@HLSDVRDefinition(maximumMediaResourceBytes: 2, maximumTotalMediaBytes: 1)\nenum Workflow {}",
            expandedSource: "enum Workflow {}",
            diagnostics: [
                DiagnosticSpec(
                    message: "maximumMediaResourceBytes must not exceed maximumTotalMediaBytes.", line: 1, column: 1)
            ], macros: ["HLSDVRDefinition": HLSWorkflowDefinitionMacro.self])
    }

    @Test("member collisions are rejected")
    func collision() {
        assertMacroExpansion(
            "@HLSPlaybackDefinition\nenum Workflow {\n    static let configuration = 1\n}",
            expandedSource: "enum Workflow {\n    static let configuration = 1\n}",
            diagnostics: [
                DiagnosticSpec(
                    message: "@HLSPlaybackDefinition owns configuration(); remove the conflicting member.", line: 1,
                    column: 1)
            ], macros: ["HLSPlaybackDefinition": HLSWorkflowDefinitionMacro.self])
    }
}
