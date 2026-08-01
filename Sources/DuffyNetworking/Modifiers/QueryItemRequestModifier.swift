#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

public struct QueryItemRequestModifier: HTTPRequestModifier {
    private let name: String
    private let value: String?

    public init(name: String, value: String?) {
        self.name = name
        self.value = value
    }

    public func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues,
    ) throws {
        guard let url = request.url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw HTTPRequestURLMutationError.requestDoesNotHaveURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: name, value: value))
        components.queryItems = queryItems

        guard let updatedURL = components.url else {
            throw HTTPRequestURLMutationError.failedToCreateURL
        }

        request.url = updatedURL
    }
}

extension HTTPRequestConfiguration {
    /// Appends a percent-encoded query item while preserving existing query items.
    public func queryItem(name: String, value: String?) -> Self {
        requestModifier(QueryItemRequestModifier(name: name, value: value))
    }
}
