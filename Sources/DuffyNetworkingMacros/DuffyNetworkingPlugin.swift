import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct DuffyNetworkingPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        APIClientMacro.self,
        HTTPRequestEnvironmentEntryMacro.self,
    ]
}
