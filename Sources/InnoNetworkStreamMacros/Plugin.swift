import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct InnoNetworkStreamPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [HLSDownloadDefinitionMacro.self, HLSWorkflowDefinitionMacro.self]
}
