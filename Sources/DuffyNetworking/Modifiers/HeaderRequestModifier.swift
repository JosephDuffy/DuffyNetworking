#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

public struct HeaderRequestModifier: HTTPRequestModifier {
    private let name: HTTPField.Name
    private let value: String

    public init(name: HTTPField.Name, value: String) {
        self.name = name
        self.value = value
    }

    public func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues,
    ) {
        request.headerFields[name] = value
    }
}

extension HTTPRequestConfiguration {
    public func header(
        name: HTTPField.Name,
        value: String,
    ) -> Self {
        requestModifier(
            HeaderRequestModifier(name: name, value: value),
        )
    }
}
