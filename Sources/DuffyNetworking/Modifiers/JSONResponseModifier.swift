#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct JSONResponseModifier<ResponseBody: Decodable & Sendable>: HTTPBodyModifier {
    public typealias DecoderConfigurator = @Sendable (JSONDecoder) -> Void

    private let configureDecoder: DecoderConfigurator

    public init(configureDecoder: @escaping DecoderConfigurator = { _ in }) {
        self.configureDecoder = configureDecoder
    }

    public func modifyBody(
        _ body: Data,
        environment: HTTPRequestEnvironmentValues,
        request: HTTPRequestSnapshot,
        response: HTTPResponseSnapshot,
    ) throws -> ResponseBody {
        let decoder = JSONDecoder()
        if let dateDecodingStrategy = environment.jsonDateDecodingStrategy {
            decoder.dateDecodingStrategy = dateDecodingStrategy
        }
        configureDecoder(decoder)
        return try decoder.decode(ResponseBody.self, from: body)
    }
}

extension HTTPRequestConfiguration<Data> {
    public func decodingJSONBody<NewResponseBody: Decodable & Sendable>(
        ofType responseType: NewResponseBody.Type = NewResponseBody.self,
        configureDecoder: @escaping JSONResponseModifier<NewResponseBody>.DecoderConfigurator = { _ in },
    ) -> HTTPRequestConfiguration<NewResponseBody> {
        responseBodyModifier(
            JSONResponseModifier(configureDecoder: configureDecoder),
        )
    }

    public func decodingJSONBody<NewResponseBody: Decodable & Sendable>(
        ofType responseType: NewResponseBody.Type = NewResponseBody.self,
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy,
        configureDecoder: @escaping JSONResponseModifier<NewResponseBody>.DecoderConfigurator = { _ in },
    ) -> HTTPRequestConfiguration<NewResponseBody> {
        responseBodyModifier(
            JSONResponseModifier(configureDecoder: { decoder in
                decoder.dateDecodingStrategy = dateDecodingStrategy
                configureDecoder(decoder)
            }),
        )
    }
}

private enum JSONDateDecodingStrategyKey: HTTPRequestEnvironmentKey {
    static let defaultValue: JSONDecoder.DateDecodingStrategy? = nil
}

extension HTTPRequestEnvironmentValues {
    public var jsonDateDecodingStrategy: JSONDecoder.DateDecodingStrategy? {
        get { self[JSONDateDecodingStrategyKey.self] }
        set { self[JSONDateDecodingStrategyKey.self] = newValue }
    }
}

extension HTTPRequestConfiguration {
    public func jsonDateDecodingStrategy(
        _ dateDecodingStrategy: JSONDecoder.DateDecodingStrategy,
    ) -> Self {
        environment(\.jsonDateDecodingStrategy, dateDecodingStrategy)
    }
}
