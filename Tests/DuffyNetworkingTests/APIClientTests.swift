import DuffyNetworking
import Foundation
import HTTPTypes
import Testing

@Suite
struct APIClientTests {
    @Test
    func generatedMethodCanUsePrivateRequirements() async throws {
        let expectedBody = Data("response".utf8)
        let client = TestAPIClient(
            dataProvider: APIClientDataProvider {
                HTTPResponseSnapshot(
                    body: expectedBody,
                    response: HTTPResponse(status: .ok),
                )
            }
        )

        let response = try await client.buildAndPerformRequest { baseRequest in
            baseRequest
        }

        #expect(response == expectedBody)
    }

    @Test
    func throwingBuilderErrorIsPreserved() async throws {
        let client = TestAPIClient(
            dataProvider: APIClientDataProvider {
                Issue.record("The request should not reach the data provider")
                return HTTPResponseSnapshot(
                    body: Data(),
                    response: HTTPResponse(status: .ok),
                )
            }
        )

        do {
            let _: Data = try await client.buildAndPerformRequest(
                requestBuilder: failingAPIClientBuilder,
            )
            Issue.record("Expected the builder to fail")
        } catch {
            switch error {
            case .buildError(let builderError):
                #expect(builderError == .missingCredentials)
            case .performError:
                Issue.record("Expected a build error")
            }
        }
    }

    @Test
    func performerErrorIsPreservedAfterThrowingBuilderSucceeds() async throws {
        let client = TestAPIClient(
            dataProvider: APIClientDataProvider {
                throw APIClientTransportError()
            }
        )

        do {
            let _: Data = try await client.buildAndPerformRequest(
                requestBuilder: successfulAPIClientBuilder,
            )
            Issue.record("Expected the performer to fail")
        } catch {
            switch error {
            case .buildError:
                Issue.record("Expected a performer error")
            case .performError(let performerError):
                #expect(performerError.underlyingError is APIClientTransportError)
            }
        }
    }
}

@APIClient
private struct TestAPIClient {
    private let httpRequestPerformer: HTTPRequestPerformer

    init(dataProvider: HTTPRequestDataProvider) {
        httpRequestPerformer = HTTPRequestPerformer(dataProvider: dataProvider)
    }

    private func makeBaseRequest() -> HTTPRequestConfiguration<Data> {
        HTTPRequestConfiguration(
            baseHTTPRequest: HTTPRequest(
                url: URL(string: "https://example.com")!,
            )
        )
    }
}

private struct APIClientDataProvider: HTTPRequestDataProvider {
    private let operation: @Sendable () async throws -> HTTPResponseSnapshot

    init(operation: @escaping @Sendable () async throws -> HTTPResponseSnapshot) {
        self.operation = operation
    }

    func data(
        for request: HTTPRequest,
        body: Data?,
        environment: HTTPRequestEnvironmentValues,
    ) async throws -> HTTPResponseSnapshot {
        try await operation()
    }
}

private enum APIClientBuilderError: Error, Equatable {
    case missingCredentials
}

private struct APIClientTransportError: Error {}

private func failingAPIClientBuilder(
    _ request: HTTPRequestConfiguration<Data>,
) async throws(APIClientBuilderError) -> HTTPRequestConfiguration<Data> {
    throw APIClientBuilderError.missingCredentials
}

private func successfulAPIClientBuilder(
    _ request: HTTPRequestConfiguration<Data>,
) async throws(APIClientBuilderError) -> HTTPRequestConfiguration<Data> {
    request
}
