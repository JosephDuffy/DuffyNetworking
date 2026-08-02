import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct HTTPRequestEnvironmentEntryMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext,
    ) throws -> [AccessorDeclSyntax] {
        guard let entry = entry(
            from: declaration,
            attributedNode: node,
            in: context,
            diagnosesErrors: false,
        ) else {
            return []
        }

        return [
            "get { self[\(raw: entry.keyName).self] }",
            "set { self[\(raw: entry.keyName).self] = newValue }",
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        guard let entry = entry(
            from: declaration,
            attributedNode: node,
            in: context,
            diagnosesErrors: true,
        ) else {
            return []
        }

        let key: DeclSyntax = """
            private enum \(raw: entry.keyName): HTTPRequestEnvironmentKey {
                static let defaultValue: \(entry.type) = \(entry.defaultValue)
            }
            """
        return [key]
    }
}

private extension HTTPRequestEnvironmentEntryMacro {
    struct Entry {
        let defaultValue: ExprSyntax
        let keyName: String
        let type: TypeSyntax
    }

    static func entry(
        from declaration: some DeclSyntaxProtocol,
        attributedNode: AttributeSyntax,
        in context: some MacroExpansionContext,
        diagnosesErrors: Bool,
    ) -> Entry? {
        guard let variable = declaration.as(VariableDeclSyntax.self),
              variable.bindingSpecifier.tokenKind == .keyword(.var),
              variable.bindings.count == 1,
              let binding = variable.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let type = binding.typeAnnotation?.type,
              let defaultValue = binding.initializer?.value
        else {
            if diagnosesErrors {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(attributedNode),
                        message: HTTPRequestEnvironmentEntryDiagnostic(
                            id: "invalid-declaration",
                            message: "'@HTTPRequestEnvironmentEntry' requires a single 'var' declaration with a type annotation and default value",
                        ),
                    )
                )
            }
            return nil
        }

        guard !variable.modifiers.contains(where: \.name.isTypeMemberModifier) else {
            if diagnosesErrors {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(attributedNode),
                        message: HTTPRequestEnvironmentEntryDiagnostic(
                            id: "static-declaration",
                            message: "'@HTTPRequestEnvironmentEntry' cannot be applied to a static property",
                        ),
                    )
                )
            }
            return nil
        }

        return Entry(
            defaultValue: ExprSyntax(defaultValue.trimmed),
            keyName: "__HTTPRequestEnvironmentEntry_\(identifier.identifier.text)",
            type: TypeSyntax(type.trimmed),
        )
    }
}

private struct HTTPRequestEnvironmentEntryDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity = DiagnosticSeverity.error

    init(id: String, message: String) {
        self.message = message
        diagnosticID = MessageID(
            domain: "DuffyNetworking.HTTPRequestEnvironmentEntry",
            id: id,
        )
    }
}

private extension TokenSyntax {
    var isTypeMemberModifier: Bool {
        tokenKind == .keyword(.static) || tokenKind == .keyword(.class)
    }
}
