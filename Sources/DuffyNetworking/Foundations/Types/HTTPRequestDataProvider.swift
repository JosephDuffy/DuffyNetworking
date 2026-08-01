#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

public protocol HTTPRequestDataProvider: Sendable {
    /// Performs a request using the supplied body and effective environment values.
    func data(
        for request: HTTPRequest,
        body: Data?,
        environment: HTTPRequestEnvironmentValues,
    ) async throws -> HTTPResponseSnapshot
}
