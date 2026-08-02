import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct APIClientMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self)
                || declaration.is(ClassDeclSyntax.self)
                || declaration.is(ActorDeclSyntax.self)
        else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: APIClientDiagnostic(
                        id: "invalid-declaration",
                        message: "'@APIClient' can only be applied to a struct, class, or actor",
                    ),
                )
            )
            return []
        }

        let members = declaration.memberBlock.members
        let hasPerformer = members.contains { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.contains(where: \.name.isTypeMemberModifier)
            else {
                return false
            }

            return variable.bindings.contains { binding in
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                    == "httpRequestPerformer"
            }
        }
        let hasBaseRequestFactory = members.contains { member in
            guard let function = member.decl.as(FunctionDeclSyntax.self),
                  function.name.text == "makeBaseRequest",
                  !function.modifiers.contains(where: \.name.isTypeMemberModifier)
            else {
                return false
            }

            return function.signature.parameterClause.parameters.isEmpty
        }
        let hasConflictingMethod = members.contains { member in
            member.decl.as(FunctionDeclSyntax.self)?.name.text == "buildAndPerformRequest"
        }

        var hasError = false

        if !hasPerformer {
            hasError = true
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: APIClientDiagnostic(
                        id: "missing-performer",
                        message: "'@APIClient' requires an instance property named 'httpRequestPerformer'",
                    ),
                )
            )
        }

        if !hasBaseRequestFactory {
            hasError = true
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: APIClientDiagnostic(
                        id: "missing-base-request-factory",
                        message: "'@APIClient' requires a zero-argument instance method named 'makeBaseRequest'",
                    ),
                )
            )
        }

        if hasConflictingMethod {
            hasError = true
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: APIClientDiagnostic(
                        id: "conflicting-method",
                        message: "'@APIClient' cannot add 'buildAndPerformRequest' because the type already declares it",
                    ),
                )
            )
        }

        guard !hasError else { return [] }

        let accessModifier = declaration.modifiers
            .first { modifier in
                modifier.name.tokenKind == .keyword(.public)
                    || modifier.name.tokenKind == .keyword(.open)
                    || modifier.name.tokenKind == .keyword(.package)
            }
            .map { modifier in
                modifier.name.tokenKind == .keyword(.open) ? "public " : "\(modifier.name.text) "
            } ?? ""

        let nonThrowingBuilder: DeclSyntax = """
            \(raw: accessModifier)func buildAndPerformRequest<ResponseBody: Sendable>(
                requestBuilder: (_ baseRequest: HTTPRequestConfiguration<Data>) -> HTTPRequestConfiguration<ResponseBody>,
            ) async throws(HTTPRequestPerformerError<ResponseBody>) -> ResponseBody {
                try await httpRequestPerformer.perform(requestBuilder(makeBaseRequest()))
            }
            """
        let throwingBuilder: DeclSyntax = """
            \(raw: accessModifier)func buildAndPerformRequest<ResponseBody: Sendable, BuilderError: Error>(
                requestBuilder: (_ baseRequest: HTTPRequestConfiguration<Data>) async throws(BuilderError) -> HTTPRequestConfiguration<ResponseBody>,
            ) async throws(HTTPRequestBuildAndPerformError<BuilderError, ResponseBody>) -> ResponseBody {
                let finalRequest: HTTPRequestConfiguration<ResponseBody>

                do {
                    finalRequest = try await requestBuilder(makeBaseRequest())
                } catch {
                    throw HTTPRequestBuildAndPerformError.buildError(error)
                }

                do {
                    return try await httpRequestPerformer.perform(finalRequest)
                } catch {
                    throw HTTPRequestBuildAndPerformError.performError(error)
                }
            }
            """

        return [nonThrowingBuilder, throwingBuilder]
    }
}

private struct APIClientDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity = DiagnosticSeverity.error

    init(id: String, message: String) {
        self.message = message
        diagnosticID = MessageID(domain: "DuffyNetworking.APIClient", id: id)
    }
}

private extension TokenSyntax {
    var isTypeMemberModifier: Bool {
        tokenKind == .keyword(.static) || tokenKind == .keyword(.class)
    }
}
