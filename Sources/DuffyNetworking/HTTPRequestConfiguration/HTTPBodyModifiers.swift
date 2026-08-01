#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct HTTPBodyModifiers<ResponseBody: Sendable>: HTTPBodyModifier, Sendable {
    private let modifier: @Sendable (
        _ data: Data,
        _ environment: HTTPRequestEnvironmentValues,
        _ request: HTTPRequestSnapshot,
        _ response: HTTPResponseSnapshot,
    ) async throws -> ResponseBody

    private let modifiers: [any HTTPBodyModifier]

    init(modifier: some HTTPBodyModifier<Data, ResponseBody>) {
        self.modifier = modifier.modifyBody
        modifiers = [modifier]
    }

    init() where ResponseBody == Data {
        modifier = { data, _, _, _ in data }
        modifiers = []
    }

    private init(
        modifier: @escaping @Sendable (
            Data,
            HTTPRequestEnvironmentValues,
            HTTPRequestSnapshot,
            HTTPResponseSnapshot
        ) async throws -> ResponseBody,
        modifiers: [any HTTPBodyModifier],
    ) {
        self.modifier = modifier
        self.modifiers = modifiers
    }

    public func appending<NewResponseBody>(modifier: some HTTPBodyModifier<ResponseBody, NewResponseBody>) -> HTTPBodyModifiers<NewResponseBody> {
        var modifiers = modifiers
        modifiers.append(modifier)
        return HTTPBodyModifiers<NewResponseBody>(
            modifier: { [firstModifier = self.modifier] data, environment, request, response in
                let intermediate = try await firstModifier(data, environment, request, response)
                return try await modifier.modifyBody(intermediate, environment: environment, request: request, response: response)
            },
            modifiers: modifiers,
        )
    }

    public func modifyBody(
        _ body: Data,
        environment: HTTPRequestEnvironmentValues,
        request: HTTPRequestSnapshot,
        response: HTTPResponseSnapshot,
    ) async throws -> ResponseBody {
        try await modifier(body, environment, request, response)
    }
}
