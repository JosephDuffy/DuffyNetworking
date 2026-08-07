#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct HTTPRequestPerformerError<ResponseBody: Sendable>: LocalizedError {
    public let underlyingError: any Error

    public let requestConfiguration: HTTPRequestConfiguration<ResponseBody>

    public let request: HTTPRequestSnapshot?

    public let response: HTTPResponseSnapshot?

    public var errorDescription: String? {
        if let underlyingError = underlyingError as? LocalizedError {
            return underlyingError.errorDescription
        } else {
            return underlyingError.localizedDescription
        }
    }
}
