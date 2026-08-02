import MacroTesting
import Testing

@testable import DuffyNetworkingMacros

@Suite(.serialized)
struct APIClientMacroTests {
    @Test
    func addsPublicBuildAndPerformMethods() {
        assertMacro(["APIClient": APIClientMacro.self]) {
            """
            @APIClient
            public struct GitHubAPI {
                private let httpRequestPerformer: HTTPRequestPerformer

                private func makeBaseRequest() -> HTTPRequestConfiguration<Data> {
                    fatalError()
                }
            }
            """
        } expansion: {
            """
            public struct GitHubAPI {
                private let httpRequestPerformer: HTTPRequestPerformer

                private func makeBaseRequest() -> HTTPRequestConfiguration<Data> {
                    fatalError()
                }

                public func buildAndPerformRequest<ResponseBody: Sendable>(
                    requestBuilder: (_ baseRequest: HTTPRequestConfiguration<Data>) -> HTTPRequestConfiguration<ResponseBody>,
                ) async throws(HTTPRequestPerformerError<ResponseBody>) -> ResponseBody {
                    try await httpRequestPerformer.perform(requestBuilder(makeBaseRequest()))
                }

                public func buildAndPerformRequest<ResponseBody: Sendable, BuilderError: Error>(
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
            }
            """
        }
    }

    @Test
    func diagnosesMissingRequirements() {
        assertMacro(["APIClient": APIClientMacro.self]) {
            """
            @APIClient
            struct InvalidClient {}
            """
        } diagnostics: {
            """
            @APIClient
            ┬─────────
            ├─ 🛑 '@APIClient' requires an instance property named 'httpRequestPerformer'
            ╰─ 🛑 '@APIClient' requires a zero-argument instance method named 'makeBaseRequest'
            struct InvalidClient {}
            """
        }
    }

    @Test
    func diagnosesExistingBuildAndPerformMethod() {
        assertMacro(["APIClient": APIClientMacro.self]) {
            """
            @APIClient
            struct ConflictingClient {
                let httpRequestPerformer: HTTPRequestPerformer

                func makeBaseRequest() -> HTTPRequestConfiguration<Data> {
                    fatalError()
                }

                func buildAndPerformRequest() {}
            }
            """
        } diagnostics: {
            """
            @APIClient
            ┬─────────
            ╰─ 🛑 '@APIClient' cannot add 'buildAndPerformRequest' because the type already declares it
            struct ConflictingClient {
                let httpRequestPerformer: HTTPRequestPerformer

                func makeBaseRequest() -> HTTPRequestConfiguration<Data> {
                    fatalError()
                }

                func buildAndPerformRequest() {}
            }
            """
        }
    }
}
