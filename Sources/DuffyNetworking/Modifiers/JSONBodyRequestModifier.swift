#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

public struct JSONBodyRequestModifier<RequestBody: Encodable>: HTTPRequestModifier {
    public typealias EncoderConfigurator = @Sendable (JSONEncoder) -> Void

    private let body: @Sendable () -> RequestBody

    private let configureEncoder: EncoderConfigurator

    public init(
        body: @autoclosure @Sendable @escaping () -> RequestBody,
        configureDecoder: @escaping EncoderConfigurator = { _ in },
    ) {
        self.body = body
        self.configureEncoder = configureDecoder
    }

    public init(
        body: @Sendable @escaping () -> RequestBody,
        configureDecoder: @escaping EncoderConfigurator = { _ in },
    ) {
        self.body = body
        self.configureEncoder = configureDecoder
    }

    public func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues
    ) throws {
        let bodyValue = self.body()
        let encoder = JSONEncoder()
        if let dateEncodingStrategy = environment.jsonDateEncodingStrategy {
            encoder.dateEncodingStrategy = dateEncodingStrategy
        }
        configureEncoder(encoder)
        body = try encoder.encode(bodyValue)
        request.headerFields[.contentType] = "application/json"
    }
}

extension HTTPRequestConfiguration {
    public func encodingJSONBody<RequestBody: Encodable>(
        _ body: @autoclosure @Sendable @escaping () -> RequestBody,
        configureDecoder: @escaping JSONBodyRequestModifier<RequestBody>.EncoderConfigurator = { _ in },
    ) -> Self {
        requestModifier(
            JSONBodyRequestModifier<RequestBody>(body: body, configureDecoder: configureDecoder)
        )
    }
}

extension HTTPRequestEnvironmentValues {
    @HTTPRequestEnvironmentEntry
    public var jsonDateEncodingStrategy: JSONEncoder.DateEncodingStrategy? = nil
}

extension HTTPRequestConfiguration {
    public func jsonDateEncodingStrategy(
        _ dateEncodingStrategy: JSONEncoder.DateEncodingStrategy,
    ) -> Self {
        environment(\.jsonDateEncodingStrategy, dateEncodingStrategy)
    }
}
