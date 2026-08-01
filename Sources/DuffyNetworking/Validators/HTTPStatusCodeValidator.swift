#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

public struct HTTPStatusCodeValidator: HTTPResponseValidator {
    public init() {}

    public func validateResponse(
        _ response: HTTPResponseSnapshot,
        to request: HTTPRequestSnapshot,
        environment: HTTPRequestEnvironmentValues,
    ) throws(HTTPStatusError) {
        switch response.response.status.kind {
        case .clientError, .serverError, .invalid:
            throw HTTPStatusError(status: response.response.status)
        case .informational, .successful, .redirection:
            break
        }
    }
}

extension HTTPRequestConfiguration {
    public func validatingStatusCode() -> Self {
        responseValidator(HTTPStatusCodeValidator())
    }
}

public struct HTTPStatusError: LocalizedError {
    public let status: HTTPResponse.Status

    public let errorDescription: String?

    public let failureReason: String?

    public init(status: HTTPResponse.Status) {
        self.status = status
        errorDescription = "HTTP status code \(status.code)"
        failureReason = status.reasonPhrase
    }
}
