#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

public struct HeaderRequestModifier: HTTPRequestModifier {
    public enum Action: Sendable {
        case append
        case replace
    }

    private let name: HTTPField.Name
    private let value: String
    private let action: Action

    public init(name: HTTPField.Name, value: String, action: Action) {
        self.name = name
        self.value = value
        self.action = action
    }

    public func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues,
    ) {
        switch action {
        case .append:
            request.headerFields.append(HTTPField(name: name, value: value))
        case .replace:
            request.headerFields[name] = value
        }
    }
}

extension HTTPRequestConfiguration {
    public func header(
        name: HTTPField.Name,
        value: String,
        action: HeaderRequestModifier.Action,
    ) -> Self {
        requestModifier(
            HeaderRequestModifier(name: name, value: value, action: action),
        )
    }

    public func replaceHeader(
        name: HTTPField.Name,
        value: String,
    ) -> Self {
        requestModifier(
            HeaderRequestModifier(name: name, value: value, action: .replace),
        )
    }

    public func appendHeader(
        name: HTTPField.Name,
        value: String,
    ) -> Self {
        requestModifier(
            HeaderRequestModifier(name: name, value: value, action: .append),
        )
    }
}
