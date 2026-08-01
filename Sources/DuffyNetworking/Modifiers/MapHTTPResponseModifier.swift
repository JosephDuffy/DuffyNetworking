
public struct MapHTTPResponseModifier<Input, Output>: HTTPBodyModifier {
    public typealias Transform = @Sendable (
        _ input: Input,
        _ environment: HTTPRequestEnvironmentValues,
        _ request: HTTPRequestSnapshot,
        _ response: HTTPResponseSnapshot,
    ) async throws -> Output

    private let transform: Transform

    public init(transform: @escaping Transform) {
        self.transform = transform
    }

    public func modifyBody(
        _ body: Input,
        environment: HTTPRequestEnvironmentValues,
        request: HTTPRequestSnapshot,
        response: HTTPResponseSnapshot,
    ) async throws -> Output {
        try await transform(body, environment, request, response)
    }
}

extension HTTPRequestConfiguration {
    public func mapResponseBody<NewResponseBody: Sendable>(
        _ transform: @escaping MapHTTPResponseModifier<ResponseBody, NewResponseBody>.Transform,
    ) -> HTTPRequestConfiguration<NewResponseBody> {
        let newModifier = MapHTTPResponseModifier<ResponseBody, NewResponseBody>(transform: transform)
        return responseBodyModifier(newModifier)
    }
}
