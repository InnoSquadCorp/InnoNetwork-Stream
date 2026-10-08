import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Validates declarative limits and delegates generated work to the runtime.
public struct HLSDownloadDefinitionMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let values = try validate(node, declaration: declaration)
        let access =
            declaration.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
            ? "public "
            : declaration.modifiers.contains { $0.name.tokenKind == .keyword(.package) }
                ? "package " : ""
        return [
            """
            \(raw: access)nonisolated static func configuration() throws -> InnoNetworkHLS.HLSDownloadConfiguration {
                try InnoNetworkHLS.HLSDownloadConfiguration.validated(
                    maximumMediaResourceBytes: \(raw: String(values.resource)),
                    maximumTotalDownloadBytes: \(raw: String(values.output)),
                    maximumConcurrentResourceTransfers: \(raw: String(values.concurrency))
                )
            }
            """
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // The member role owns diagnostics; do not report each failure twice.
        guard (try? validate(node, declaration: declaration)) != nil else { return [] }
        return [
            try ExtensionDeclSyntax(
                "extension \(type): InnoNetworkHLS.HLSDownloadDefining {}"
            )
        ]
    }

    private struct Limits {
        var resource: Int64 = 134_217_728
        var output: Int64 = 8_589_934_592
        var concurrency: Int64 = 3
    }

    private static func validate(_ node: AttributeSyntax, declaration: some DeclGroupSyntax) throws -> Limits {
        guard declaration.is(StructDeclSyntax.self) || declaration.is(EnumDeclSyntax.self) else {
            throw Failure("@HLSDownloadDefinition requires a struct or enum declaration.")
        }
        if ConfigurationMemberValidation.hasCollision(in: declaration.memberBlock.members) {
            throw Failure("@HLSDownloadDefinition owns configuration(); remove the conflicting member.")
        }
        if declaration.inheritanceClause?.inheritedTypes.contains(where: {
            ["HLSDownloadDefining", "InnoNetworkHLS.HLSDownloadDefining"].contains($0.type.trimmedDescription)
        }) == true {
            throw Failure("@HLSDownloadDefinition adds HLSDownloadDefining; remove the explicit conformance.")
        }
        var limits = Limits()
        var seen: Set<String> = []
        if let arguments = node.arguments {
            guard let arguments = arguments.as(LabeledExprListSyntax.self) else {
                throw Failure("@HLSDownloadDefinition expects labeled integer limits.")
            }
            for argument in arguments {
                guard let label = argument.label?.text,
                    ["maximumMediaResourceBytes", "maximumTotalDownloadBytes", "maximumConcurrentResourceTransfers"]
                        .contains(label),
                    seen.insert(label).inserted
                else {
                    throw Failure("@HLSDownloadDefinition accepts each supported limit label once.")
                }
                guard let literal = argument.expression.as(IntegerLiteralExprSyntax.self),
                    let value = Int64(literal.literal.text.filter { $0 != "_" }),
                    value > 0
                else {
                    throw Failure(
                        "@HLSDownloadDefinition limits must be positive decimal integer literals; use validated() for dynamic settings."
                    )
                }
                switch label {
                case "maximumMediaResourceBytes": limits.resource = value
                case "maximumTotalDownloadBytes": limits.output = value
                default: limits.concurrency = value
                }
            }
        }
        guard limits.resource <= limits.output else {
            throw Failure("maximumMediaResourceBytes must not exceed maximumTotalDownloadBytes.")
        }
        guard limits.resource <= Int32.max else {
            throw Failure("maximumMediaResourceBytes must fit a signed 32-bit Int on every supported platform.")
        }
        guard (1...8).contains(limits.concurrency) else {
            throw Failure("maximumConcurrentResourceTransfers must be in 1...8.")
        }
        return limits
    }

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
