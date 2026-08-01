#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

public struct HTTPRequestSnapshot: Hashable, Sendable {
    /// The body produced by the request modifiers.
    public let body: Data?

    /// The request produced by the request modifiers.
    public let request: HTTPRequest

    public init(body: Data?, request: HTTPRequest) {
        self.body = body
        self.request = request
    }
}
