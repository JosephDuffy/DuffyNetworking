public protocol HTTPBodyModifier<Input, Output>: Sendable {
    associatedtype Input
    associatedtype Output

    func modifyBody(
        _ body: Input,
        environment: HTTPRequestEnvironmentValues,
        request: HTTPRequestSnapshot,
        response: HTTPResponseSnapshot,
    ) async throws -> Output
}
