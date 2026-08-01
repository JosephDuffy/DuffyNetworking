#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

public struct RawPathRequestModifier: HTTPRequestModifier {
    public enum Action: Sendable {
        case replace
        case append
        case infer
    }

    private let path: String
    private let action: Action

    public init(path: String, action: Action = .infer) {
        self.path = path
        self.action = action
    }

    public func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues,
    ) {
        switch action {
        case .replace:
            request.path = path
        case .append:
            request.path = "\(request.path ?? "")\(path)"
        case .infer:
            if path.hasPrefix("/") {
                request.path = path
            } else {
                request.path = "\(request.path ?? "")\(path)"
            }
        }
    }
}

extension HTTPRequestConfiguration {
    /// Sets a raw, already percent-encoded request path.
    public func rawPath(
        _ path: String,
        action: RawPathRequestModifier.Action = .infer,
    ) -> Self {
        requestModifier(
            RawPathRequestModifier(path: path, action: action),
        )
    }
}
