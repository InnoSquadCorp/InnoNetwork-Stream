import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Shared compile-time scalar validation; each workflow keeps its own runtime.
public struct HLSWorkflowDefinitionMacro: MemberMacro, ExtensionMacro {
    private struct Field {
        let name: String
        let value: Int64
        let range: ClosedRange<Int64>
    }
    private struct Spec {
        let module: String
        let configuration: String
        let conformance: String
        var fields: [Field]
    }
    private static func validate(_ node: AttributeSyntax, _ declaration: some DeclGroupSyntax) throws -> Spec {
        let name = String(node.attributeName.trimmedDescription.split(separator: ".").last ?? "")
        var spec: Spec
        switch name {
        case "HLSCatalogDefinition":
            spec = Spec(
                module: "InnoNetworkHLS", configuration: "HLSMediaCatalogConfiguration",
                conformance: "HLSCatalogDefining",
                fields: [
                    Field(name: "maximumEntries", value: 512, range: 1...512),
                    Field(name: "maximumSnapshotBytes", value: 1_048_576, range: 1024...1_048_576),
                ])
        case "HLSLiveDefinition":
            spec = Spec(
                module: "InnoNetworkHLSLive", configuration: "HLSLiveConfiguration", conformance: "HLSLiveDefining",
                fields: [
                    Field(name: "minimumPollingMilliseconds", value: 500, range: 50...3_600_000),
                    Field(name: "maximumPollingMilliseconds", value: 30_000, range: 50...3_600_000),
                    Field(name: "requestTimeoutSeconds", value: 45, range: 1...300),
                ])
        case "HLSDVRDefinition":
            spec = Spec(
                module: "InnoNetworkHLSLive", configuration: "HLSLiveDVRConfiguration", conformance: "HLSDVRDefining",
                fields: [
                    Field(name: "maximumDurationSeconds", value: 1800, range: 1...86_400),
                    Field(name: "maximumSegmentCount", value: 900, range: 1...10_000),
                    Field(name: "maximumMediaResourceBytes", value: 134_217_728, range: 1...1_073_741_824),
                    Field(name: "maximumTotalMediaBytes", value: 8_589_934_592, range: 1...68_719_476_736),
                ])
        case "HLSPlaybackDefinition":
            spec = Spec(
                module: "InnoNetworkHLSAVFoundation", configuration: "HLSPlaybackConfiguration",
                conformance: "HLSPlaybackDefining",
                fields: [
                    Field(name: "maximumPeakBitRate", value: 10_000_000, range: 1...2_147_483_647),
                    Field(name: "maximumWidth", value: 1920, range: 1...2_147_483_647),
                    Field(name: "maximumHeight", value: 1080, range: 1...2_147_483_647),
                ])
        default: throw Failure("Unsupported workflow definition.")
        }
        guard declaration.is(StructDeclSyntax.self) || declaration.is(EnumDeclSyntax.self) else {
            throw Failure("@\(name) requires a struct or enum declaration.")
        }
        if ConfigurationMemberValidation.hasCollision(in: declaration.memberBlock.members) {
            throw Failure("@\(name) owns configuration(); remove the conflicting member.")
        }
        if declaration.inheritanceClause?.inheritedTypes.contains(where: {
            [spec.conformance, "\(spec.module).\(spec.conformance)"].contains($0.type.trimmedDescription)
        }) == true {
            throw Failure("@\(name) adds \(spec.conformance); remove the explicit conformance.")
        }
        var seen: Set<String> = []
        if let arguments = node.arguments {
            guard let arguments = arguments.as(LabeledExprListSyntax.self) else {
                throw Failure("Expected labeled limits.")
            }
            for argument in arguments {
                guard let label = argument.label?.text, let index = spec.fields.firstIndex(where: { $0.name == label }),
                    seen.insert(label).inserted
                else {
                    throw Failure("@\(name) accepts each supported limit label once.")
                }
                guard let literal = argument.expression.as(IntegerLiteralExprSyntax.self),
                    let value = Int64(literal.literal.text.filter { $0 != "_" }),
                    spec.fields[index].range.contains(value)
                else {
                    throw Failure(
                        "\(label) must be a decimal integer literal in \(spec.fields[index].range). Use validated() for dynamic values."
                    )
                }
                spec.fields[index] = Field(name: label, value: value, range: spec.fields[index].range)
            }
        }
        if name == "HLSLiveDefinition", spec.fields[0].value > spec.fields[1].value {
            throw Failure("minimumPollingMilliseconds must not exceed maximumPollingMilliseconds.")
        }
        if name == "HLSDVRDefinition", spec.fields[2].value > spec.fields[3].value {
            throw Failure("maximumMediaResourceBytes must not exceed maximumTotalMediaBytes.")
        }
        return spec
    }

    public static func expansion(
        of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let spec = try validate(node, declaration)
        let access =
            declaration.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
            ? "public "
            : declaration.modifiers.contains { $0.name.tokenKind == .keyword(.package) } ? "package " : ""
        let arguments = spec.fields.map { "\($0.name): \($0.value)" }.joined(separator: ", ")
        return [
            """
            \(raw: access)nonisolated static func configuration() throws -> \(raw: spec.module).\(raw: spec.configuration) {
                try \(raw: spec.module).\(raw: spec.configuration).validated(\(raw: arguments))
            }
            """
        ]
    }

    public static func expansion(
        of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let spec = try? validate(node, declaration) else { return [] }
        return [try ExtensionDeclSyntax("extension \(type): \(raw: spec.module).\(raw: spec.conformance) {}")]
    }
    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
