import SwiftSyntax

/// Checks all conditional branches; a macro cannot evaluate build conditions.
enum ConfigurationMemberValidation {
    static func hasCollision(in members: MemberBlockItemListSyntax) -> Bool {
        for member in members {
            if let function = member.decl.as(FunctionDeclSyntax.self),
                identifier(function.name) == "configuration"
            {
                return true
            }
            if let variable = member.decl.as(VariableDeclSyntax.self),
                variable.bindings.contains(where: {
                    $0.pattern.as(IdentifierPatternSyntax.self).map { identifier($0.identifier) } == "configuration"
                })
            {
                return true
            }
            if let conditional = member.decl.as(IfConfigDeclSyntax.self) {
                for clause in conditional.clauses {
                    if let nested = clause.elements?.as(MemberBlockItemListSyntax.self), hasCollision(in: nested) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func identifier(_ token: TokenSyntax) -> String {
        let text = token.text
        return text.hasPrefix("`") && text.hasSuffix("`") ? String(text.dropFirst().dropLast()) : text
    }
}
