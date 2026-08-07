#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

public struct HTTPMethodRequestModifier: HTTPRequestModifier {
    private let method: HTTPRequest.Method

    public init(method: HTTPRequest.Method) {
        self.method = method
    }

    public func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues,
    ) throws {
        request.method = method
    }
}

extension HTTPRequestConfiguration {
    public func method(_ method: HTTPRequest.Method) -> Self {
        requestModifier(HTTPMethodRequestModifier(method: method))
    }
}
