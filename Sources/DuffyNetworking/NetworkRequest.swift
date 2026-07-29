#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes
import HTTPTypesFoundation

public protocol HTTPRequestDataProvider: Sendable {
    func data(
        for request: HTTPRequest,
        environment: HTTPRequestEnvironmentValues,
    ) async throws -> (data: Data, response: HTTPResponse)

    func upload(
        data: Data,
        for request: HTTPRequest,
        environment: HTTPRequestEnvironmentValues,
    ) async throws -> (data: Data, response: HTTPResponse)
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct URLSessionHTTPRequestDataProvider: HTTPRequestDataProvider, Sendable {
    private let urlSessionInvalidator: URLSessionInvalidator

    private var urlSession: URLSession {
        urlSessionInvalidator.urlSession
    }

    public init(urlSession: URLSession, invalidateOnDeinit: Bool = true) {
        urlSessionInvalidator = URLSessionInvalidator(
            urlSession: urlSession,
            invalidateOnDeinit: invalidateOnDeinit,
        )
    }

    public func data(
        for request: HTTPRequest,
        environment: HTTPRequestEnvironmentValues,
    ) async throws -> (data: Data, response: HTTPResponse) {
        guard var urlRequest = URLRequest(httpRequest: request) else {
            throw HTTPTypeConversionError.failedToConvertHTTPRequestToURLRequest
        }

        if let cachePolicy = environment[URLRequestCachePolicyKey.self] {
            urlRequest.cachePolicy = cachePolicy
        }

        let (data, urlResponse) = try await urlSession.data(for: urlRequest)

        guard let response = (urlResponse as? HTTPURLResponse)?.httpResponse else {
            throw HTTPTypeConversionError.failedToConvertURLResponseToHTTPResponse
        }

        return (data, response)
    }

    public func upload(
        data: Data,
        for request: HTTPRequest,
        environment: HTTPRequestEnvironmentValues,
    ) async throws -> (data: Data, response: HTTPResponse) {
        guard var urlRequest = URLRequest(httpRequest: request) else {
            throw HTTPTypeConversionError.failedToConvertHTTPRequestToURLRequest
        }

        if let cachePolicy = environment[URLRequestCachePolicyKey.self] {
            urlRequest.cachePolicy = cachePolicy
        }

        let (data, urlResponse) = try await urlSession.upload(for: urlRequest, from: data)

        guard let response = (urlResponse as? HTTPURLResponse)?.httpResponse else {
            throw HTTPTypeConversionError.failedToConvertURLResponseToHTTPResponse
        }

        return (data, response)
    }
}

private enum HTTPTypeConversionError: Error {
    case failedToConvertHTTPRequestToURLRequest
    case failedToConvertURLResponseToHTTPResponse
}

public enum CachePolicy: Codable, Hashable, Sendable {
    case useProtocolCachePolicy

    case reloadIgnoringLocalCacheData

    case reloadIgnoringLocalAndRemoteCacheData

    case reloadIgnoringCacheData

    case returnCacheDataElseLoad

    case returnCacheDataDontLoad

    case reloadRevalidatingCacheData
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension URLSessionHTTPRequestDataProvider {
    public static var shared: URLSessionHTTPRequestDataProvider {
        URLSessionHTTPRequestDataProvider(urlSession: .shared)
    }
}

private final class URLSessionInvalidator: @unchecked Sendable {
    let urlSession: URLSession

    private let invalidateOnDeinit: Bool

    init(urlSession: URLSession, invalidateOnDeinit: Bool) {
        self.urlSession = urlSession
        self.invalidateOnDeinit = invalidateOnDeinit
    }

    deinit {
        guard invalidateOnDeinit else { return }
        // When a session other than the `URLSession.shared` session is used we need to
        // invalidate it when this object is deallocated.
        urlSession.invalidateAndCancel()
    }
}

public struct HTTPRequestPerformerError<ResponseBody>: Error {
    public let underlyingError: Error

    public let requestConfiguration: HTTPRequestConfiguration<ResponseBody>

    public let httpRequest: (Data?, HTTPRequest)?

    public let response: (Data?, HTTPResponse)?
}

private struct UnknownMappingError<ResponseBody>: LocalizedError {
    var errorDescription: String? {
        "Cannot map from Data to \(ResponseBody.self). Don't use a request returned by `HTTPRequestPerformer.buildAndPerformRequest(baseRequest:requestBuilder:)`."
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct HTTPRequestPerformer: Sendable {
    private let dataProvider: HTTPRequestDataProvider

    private let environment: HTTPRequestEnvironmentValues

    public init(dataProvider: HTTPRequestDataProvider) {
        self.dataProvider = dataProvider
        environment = HTTPRequestEnvironmentValues()
    }

    private init(dataProvider: HTTPRequestDataProvider, environment: HTTPRequestEnvironmentValues) {
        self.dataProvider = dataProvider
        self.environment = environment
    }

    public func buildAndPerformRequest<ResponseBody>(
        baseRequest: HTTPRequestConfiguration<Data>,
        requestBuilder: (_ baseRequest: HTTPRequestConfiguration<Data>) throws -> HTTPRequestConfiguration<ResponseBody>,
    ) async throws(HTTPRequestPerformerError<ResponseBody>) -> ResponseBody {
        do {
            let request = try requestBuilder(baseRequest)
            return try await performRequest(request: request)
        } catch let error as HTTPRequestPerformerError<ResponseBody> {
            throw error
        } catch {
            throw HTTPRequestPerformerError(
                underlyingError: error,
                requestConfiguration: baseRequest.mapResponseBody({ _, _, _ in
                    assertionFailure("Attempted to map the response of a request configuration that was created when a request builder threw an error.")
                    throw UnknownMappingError<ResponseBody>()
                }),
                httpRequest: nil,
                response: nil,
            )
        }
    }

    public func buildAndPerformRequest(
        baseRequest: HTTPRequestConfiguration<Data>,
        requestBuilder: (_ baseRequest: HTTPRequestConfiguration<Data>) throws -> HTTPRequestConfiguration<Data>,
    ) async throws(HTTPRequestPerformerError<Data>) -> Data {
        do {
            let request = try requestBuilder(baseRequest)
            return try await performRequest(request: request)
        } catch let error as HTTPRequestPerformerError<Data> {
            throw error
        } catch {
            throw HTTPRequestPerformerError(
                underlyingError: error,
                requestConfiguration: baseRequest,
                httpRequest: nil,
                response: nil,
            )
        }
    }

    public func performRequest<ResponseBody>(
        request: HTTPRequestConfiguration<ResponseBody>
    ) async throws(HTTPRequestPerformerError<ResponseBody>) -> ResponseBody {
        func notifyResponseListenersOfResponse(
            _ response: @autoclosure () -> HTTPRequestPerformResult<ResponseBody>,
        ) {
            guard !request.responseListeners.isEmpty else { return }

            let response = response()
            Task(priority: .low) { @concurrent [responseListeners = request.responseListeners] in
                for responseListener in responseListeners {
                    await responseListener.handleResponse(response)
                }
            }
        }

        func attemptRecovery(
            underlyingError: Error,
            httpRequest: (Data?, HTTPRequest)?,
            response: (Data, HTTPResponse)?
        ) async throws(HTTPRequestPerformerError<ResponseBody>) -> ResponseBody {
            let error = HTTPRequestPerformerError(
                underlyingError: underlyingError,
                requestConfiguration: request,
                httpRequest: httpRequest,
                response: response
            )

            for errorHandler in request.errorHandlers {
                if let recoveryAction = await errorHandler.attemptRecovery(from: error) {
                    notifyResponseListenersOfResponse(.failure(error, recoveryAction))

                    switch recoveryAction {
                    case .returnResponse(let responseBody):
                        return responseBody
                    case .replaceRequest(let newRequest):
                        return try await performRequest(request: newRequest)
                    }
                }
            }

            notifyResponseListenersOfResponse(.failure(error, nil))

            throw error
        }

        var httpRequest = request.baseHTTPRequest
        var requestBody: Data?

        do {
            for modifier in request.requestModifiers {
                try await modifier.modifyRequest(&httpRequest, body: &requestBody)
            }
        } catch {
            return try await attemptRecovery(
                underlyingError: error,
                httpRequest: nil,
                response: nil,
            )
        }

        let responseBody: Data
        let httpResponse: HTTPResponse

        do {
            (responseBody, httpResponse) = try await dataProvider.data(for: httpRequest, environment: environment)
        } catch {
            return try await attemptRecovery(
                underlyingError: error,
                httpRequest: (requestBody, httpRequest),
                response: nil
            )
        }

        do {
            for validator in request.responseValidators {
                try await validator.validateResponse((responseBody, httpResponse), to: (requestBody, httpRequest))
            }

            let modifiedResponseBody = try await request
                .responseBodyModifier
                .modifyBody(responseBody, request: httpRequest, response: httpResponse)

            notifyResponseListenersOfResponse(
                .success(
                    requestConfiguration: request,
                    responseBody: modifiedResponseBody,
                    httpRequest: (requestBody, httpRequest),
                    httpResponse: (responseBody, httpResponse),
                ),
            )

            return modifiedResponseBody
        } catch {
            return try await attemptRecovery(
                underlyingError: error,
                httpRequest: (requestBody, httpRequest),
                response: (responseBody, httpResponse),
            )
        }
    }

    public func environment<V>(
        _ keyPath: WritableKeyPath<HTTPRequestEnvironmentValues, V>,
        _ value: V
    ) -> HTTPRequestPerformer {
        var environment = environment
        environment[keyPath: keyPath] = value
        return HTTPRequestPerformer(dataProvider: dataProvider, environment: environment)
    }
}

public enum HTTPRequestPerformResult<ResponseBody> {
    case success(
        requestConfiguration: HTTPRequestConfiguration<ResponseBody>,
        responseBody: ResponseBody,
        httpRequest: (Data?, HTTPRequest),
        httpResponse: (Data, HTTPResponse),
    )

    case failure(
        HTTPRequestPerformerError<ResponseBody>,
        HTTPRequestErrorRecoveryAction<ResponseBody>?,
    )
}

/// A type that describes how to construct a HTTP request and how to handle the response.
public struct HTTPRequestConfiguration<ResponseBody>: Sendable {
    /// The base request the ``requestModifiers`` will modify.
    public let baseHTTPRequest: HTTPRequest

    /// An array of values that will modify the ``baseHTTPRequest`` to produce the final request.
    ///
    /// These modifiers will be applied in the order they are provided.
    public let requestModifiers: [HTTPRequestModifier]

    /// An array of values that will be notified of the network response, before validation or
    /// modification. These will always be notified of the response, even if the request fails.
    public let responseListeners: [HTTPResponseListener]

    /// An array of values that can validate the response. All validators will be run, but if any
    /// validator fails the request will be considered failed.
    public let responseValidators: [HTTPResponseValidator]

    /// A value that will modify the response's body.
    ///
    /// This can be a chain of modifiers, where the output of one modifier is the input of the next.
    /// The final output will be the ``ResponseBody`` type.
    public let responseBodyModifier: any HTTPBodyModifier<Data, ResponseBody>

    /// An array of values that will be notified of any errors that occur during the handling of the
    /// request. These values have the opportunity to recover from the error, either by returning a
    /// valid response or creating a new request to be performed.
    ///
    /// Error handlers are called in order; to support non-recovery checking of errors use a
    /// response listener.
    public let errorHandlers: [HTTPRequestPerformerErrorHandler]

    public init(
        baseHTTPRequest: HTTPRequest,
        requestModifiers: [HTTPRequestModifier] = [],
        responseListeners: [HTTPResponseListener] = [],
        responseValidators: [HTTPResponseValidator] = [],
        responseBodyModifier: any HTTPBodyModifier<Data, ResponseBody>,
        errorHandlers: [HTTPRequestPerformerErrorHandler] = [],
    ) {
        self.baseHTTPRequest = baseHTTPRequest
        self.requestModifiers = requestModifiers
        self.responseListeners = responseListeners
        self.responseValidators = responseValidators
        self.responseBodyModifier = responseBodyModifier
        self.errorHandlers = errorHandlers
    }

    public init(
        baseHTTPRequest: HTTPRequest,
        requestModifiers: [HTTPRequestModifier] = [],
        responseListeners: [HTTPResponseListener] = [],
        responseValidators: [HTTPResponseValidator] = [],
        responseBodyModifier: any HTTPBodyModifier<Data, ResponseBody> = MapHTTPResponseModifier(transform: { body, _, _ in body }),
        errorHandlers: [HTTPRequestPerformerErrorHandler] = [],
    ) where ResponseBody == Data {
        self.baseHTTPRequest = baseHTTPRequest
        self.requestModifiers = requestModifiers
        self.responseListeners = responseListeners
        self.responseValidators = responseValidators
        self.responseBodyModifier = responseBodyModifier
        self.errorHandlers = errorHandlers
    }

    public func requestModifier(
        _ requestModifier: HTTPRequestModifier,
    ) -> Self {
        var requestModifiers = requestModifiers
        requestModifiers.append(requestModifier)
        return HTTPRequestConfiguration<ResponseBody>(
            baseHTTPRequest: baseHTTPRequest,
            requestModifiers: requestModifiers,
            responseListeners: responseListeners,
            responseValidators: responseValidators,
            responseBodyModifier: responseBodyModifier,
            errorHandlers: errorHandlers,
        )
    }

    public func responseListener(
        _ responseListener: HTTPResponseListener,
    ) -> Self {
        var responseListeners = responseListeners
        responseListeners.append(responseListener)
        return HTTPRequestConfiguration<ResponseBody>(
            baseHTTPRequest: baseHTTPRequest,
            requestModifiers: requestModifiers,
            responseListeners: responseListeners,
            responseValidators: responseValidators,
            responseBodyModifier: responseBodyModifier,
            errorHandlers: errorHandlers,
        )
    }

    public func responseValidator(
        _ responseValidator: HTTPResponseValidator,
    ) -> Self {
        var responseValidators = responseValidators
        responseValidators.append(responseValidator)
        return HTTPRequestConfiguration<ResponseBody>(
            baseHTTPRequest: baseHTTPRequest,
            requestModifiers: requestModifiers,
            responseListeners: responseListeners,
            responseValidators: responseValidators,
            responseBodyModifier: responseBodyModifier,
            errorHandlers: errorHandlers,
        )
    }

    public func responseBodyModifier<NewResponseBody>(
        _ responseBodyModifier: any HTTPBodyModifier<ResponseBody, NewResponseBody>
    ) -> HTTPRequestConfiguration<NewResponseBody> {
        let newResponseBodyModifier = self.responseBodyModifier.then(responseBodyModifier)
        return HTTPRequestConfiguration<NewResponseBody>(
            baseHTTPRequest: baseHTTPRequest,
            requestModifiers: requestModifiers,
            responseListeners: responseListeners,
            responseValidators: responseValidators,
            responseBodyModifier: newResponseBodyModifier,
            errorHandlers: errorHandlers,
        )
    }

    public func errorHandler(
        _ errorHandler: HTTPRequestPerformerErrorHandler,
    ) -> Self {
        var errorHandlers = errorHandlers
        errorHandlers.append(errorHandler)
        return HTTPRequestConfiguration<ResponseBody>(
            baseHTTPRequest: baseHTTPRequest,
            requestModifiers: requestModifiers,
            responseListeners: responseListeners,
            responseValidators: responseValidators,
            responseBodyModifier: responseBodyModifier,
            errorHandlers: errorHandlers,
        )
    }
}

public struct HTTPRequestEnvironmentValues: Sendable {
    private var storage: [ObjectIdentifier: any Sendable]

    public init() {
        storage = [:]
    }

    public subscript<Key>(key: Key.Type) -> Key.Value where Key: HTTPRequestEnvironmentKey {
        get {
            let identifier = ObjectIdentifier(key)

            guard let value = storage[identifier] as? Key.Value else {
                return Key.defaultValue
            }

            return value
        }
        set {
            let value: any Sendable = newValue
            storage[ObjectIdentifier(key)] = value
        }
    }
}

public protocol HTTPRequestEnvironmentKey {
    associatedtype Value: Sendable

    static var defaultValue: Value { get }
}

private enum URLRequestCachePolicyKey: HTTPRequestEnvironmentKey {
    static let defaultValue: URLRequest.CachePolicy? = nil
}

public protocol HTTPRequestModifier: Sendable {
    func modifyRequest(_ request: inout HTTPRequest, body: inout Data?) async throws
}

public protocol HTTPResponseListener: Sendable {
    func handleResponse<ResponseBody>(
        _ response: HTTPRequestPerformResult<ResponseBody>,
    ) async
}

public protocol HTTPResponseValidator: Sendable {
    func validateResponse(_ response: (Data, HTTPResponse), to request: (Data?, HTTPRequest)) async throws
}

public struct HTTPStatusCodeValidator: HTTPResponseValidator {
    public init() {}

    public func validateResponse(_ response: (Data, HTTPResponse), to request: (Data?, HTTPRequest)) throws {
        switch response.1.status.kind {
        case .clientError, .serverError, .invalid:
            throw HTTPStatusError(statusCode: response.1.status)
        case .informational, .successful, .redirection:
            break
        }
    }
}

public struct HTTPStatusError: LocalizedError {
    public let errorDescription: String?
    public let failureReason: String?

    init(statusCode: HTTPResponse.Status) {
        errorDescription = "HTTP status code \(statusCode.code)"
        failureReason = statusCode.reasonPhrase
    }
}

public protocol HTTPRequestPerformerErrorHandler: Sendable {
    func attemptRecovery<ResponseBody>(
        from error: HTTPRequestPerformerError<ResponseBody>,
    ) async -> HTTPRequestErrorRecoveryAction<ResponseBody>?
}

public enum HTTPRequestErrorRecoveryAction<ResponseBody> {
    case replaceRequest(HTTPRequestConfiguration<ResponseBody>)
    case returnResponse(ResponseBody)
}

public protocol HTTPBodyModifier<Input, Output>: Sendable {
    associatedtype Input
    associatedtype Output

    func modifyBody(
        _ body: Input,
        request: HTTPRequest,
        response: HTTPResponse,
    ) async throws -> Output
}

extension HTTPBodyModifier {
    public func then<NewOutput>(_ newModifier: any HTTPBodyModifier<Output, NewOutput>) -> some HTTPBodyModifier<Input, NewOutput> {
        MapHTTPResponseModifier<Input, NewOutput>(transform: { [self] input, request, response in
            let intermediate = try await self.modifyBody(input, request: request, response: response)
            return try await newModifier.modifyBody(intermediate, request: request, response: response)
        })
    }
}

public struct MapHTTPResponseModifier<Input, Output>: HTTPBodyModifier {
    public typealias Transform = @Sendable (_ input: Input, _ request: HTTPRequest, _ response: HTTPResponse) async throws -> Output

    private let transform: Transform

    public init(transform: @escaping Transform) {
        self.transform = transform
    }

    public func modifyBody(_ body: Input, request: HTTPRequest, response: HTTPResponse) async throws -> Output {
        try await transform(body, request, response)
    }
}

extension HTTPRequestConfiguration {
    public func mapResponseBody<NewResponseBody>(
        _ transform: @escaping @Sendable (ResponseBody, HTTPRequest, HTTPResponse) async throws -> NewResponseBody
    ) -> HTTPRequestConfiguration<NewResponseBody> {
        let newModifier = MapHTTPResponseModifier<ResponseBody, NewResponseBody>(transform: transform)
        return responseBodyModifier(newModifier)
    }
}
