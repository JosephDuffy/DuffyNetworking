import DuffyNetworking
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

public struct StubHTTPRequestDataProvider: HTTPRequestDataProvider {
    public init() {}

    public func data(
        for request: HTTPRequest,
        body: Data?,
        environment: HTTPRequestEnvironmentValues
    ) throws -> HTTPResponseSnapshot {
        throw NoDataError()
    }
}

public struct NoDataError: LocalizedError {
    public var errorDescription: String? {
        return "No data available."
    }

    public init() {}
}
