#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

public struct HTTPResponseSnapshot: Hashable, Sendable {
    /// The raw response body.
    public let body: Data

    /// The HTTP response metadata.
    public let response: HTTPResponse

    public init(body: Data, response: HTTPResponse) {
        self.body = body
        self.response = response
    }
}
