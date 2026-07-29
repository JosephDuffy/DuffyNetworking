#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes
import HTTPTypesFoundation

public protocol HTTPRequestDataProvider: Sendable {
    /// Performs a request using the supplied body and effective environment values.
    func data(
        for request: HTTPRequest,
        body: Data?,
        environment: HTTPRequestEnvironmentValues,
    ) async throws -> HTTPResponseSnapshot
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
        body: Data?,
        environment: HTTPRequestEnvironmentValues,
    ) async throws -> HTTPResponseSnapshot {
        guard var urlRequest = URLRequest(httpRequest: request) else {
            throw HTTPTypeConversionError.failedToConvertHTTPRequestToURLRequest
        }

        if let cachePolicy = environment.urlRequestCachePolicy {
            urlRequest.cachePolicy = cachePolicy
        }

        let (data, urlResponse) = if let body {
            try await urlSession.upload(for: urlRequest, from: body)
        } else {
            try await urlSession.data(for: urlRequest)
        }

        guard let response = (urlResponse as? HTTPURLResponse)?.httpResponse else {
            throw HTTPTypeConversionError.failedToConvertURLResponseToHTTPResponse
        }

        return HTTPResponseSnapshot(body: data, response: response)
    }
}

private enum HTTPTypeConversionError: Error {
    case failedToConvertHTTPRequestToURLRequest
    case failedToConvertURLResponseToHTTPResponse
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension URLSessionHTTPRequestDataProvider {
    public static var shared: URLSessionHTTPRequestDataProvider {
        URLSessionHTTPRequestDataProvider(
            urlSession: .shared,
            invalidateOnDeinit: false,
        )
    }
}

private final class URLSessionInvalidator: Sendable {
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

public struct HTTPRequestSnapshot: Hashable, Sendable {
    /// The body produced by the request modifiers.
    public let body: Data?

    /// The request produced by the request modifiers.
    public let request: HTTPRequest

    public init(body: Data?, request: HTTPRequest) {
        self.body = body
        self.request = request
    }
}

public struct HTTPResponseSnapshot: Hashable, Sendable {
    /// The raw response body.
    public let body: Data

    /// The HTTP response metadata.
    public let response: HTTPResponse

    public init(body: Data, response: HTTPResponse) {
        self.body = body
        self.response = response
    }
}

public struct HTTPRequestPerformerError<ResponseBody: Sendable>: Error {
    public let underlyingError: any Error

    public let requestConfiguration: HTTPRequestConfiguration<ResponseBody>

    public let request: HTTPRequestSnapshot?

    public let response: HTTPResponseSnapshot?
}

public struct HTTPRequestRecoveryError<ResponseBody: Sendable>: Error {
    public let requestError: HTTPRequestPerformerError<ResponseBody>

    public let underlyingError: any Error

    public init(
        requestError: HTTPRequestPerformerError<ResponseBody>,
        underlyingError: any Error,
    ) {
        self.requestError = requestError
        self.underlyingError = underlyingError
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct HTTPRequestPerformer: Sendable {
    private let dataProvider: HTTPRequestDataProvider

    private let environmentValues: HTTPRequestEnvironmentValues

    public init(
        dataProvider: HTTPRequestDataProvider,
        environmentValues: HTTPRequestEnvironmentValues = HTTPRequestEnvironmentValues(),
    ) {
        self.dataProvider = dataProvider
        self.environmentValues = environmentValues
    }

    /// Performs a request after merging the performer's environment defaults with the request's
    /// overrides. Request values take precedence, and the supplied configuration is not mutated.
    public func perform<ResponseBody: Sendable>(
        _ request: HTTPRequestConfiguration<ResponseBody>,
    ) async throws(HTTPRequestPerformerError<ResponseBody>) -> ResponseBody {
        let effectiveEnvironment = environmentValues.merging(
            request.environmentValues,
        )
        let request = request.replacingEnvironmentValues(
            with: effectiveEnvironment,
        )

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
            underlyingError: any Error,
            requestSnapshot: HTTPRequestSnapshot?,
            responseSnapshot: HTTPResponseSnapshot?,
        ) async throws(HTTPRequestPerformerError<ResponseBody>) -> ResponseBody {
            let requestError = HTTPRequestPerformerError(
                underlyingError: underlyingError,
                requestConfiguration: request,
                request: requestSnapshot,
                response: responseSnapshot,
            )

            guard !Task.isCancelled, !(underlyingError is CancellationError) else {
                notifyResponseListenersOfResponse(.failure(requestError, nil))
                throw requestError
            }

            for errorHandler in request.errorHandlers {
                do {
                    try Task.checkCancellation()
                } catch {
                    let cancellationError = HTTPRequestPerformerError(
                        underlyingError: error,
                        requestConfiguration: request,
                        request: requestSnapshot,
                        response: responseSnapshot,
                    )
                    notifyResponseListenersOfResponse(.failure(cancellationError, nil))
                    throw cancellationError
                }

                let recoveryAction: HTTPRequestErrorRecoveryAction<ResponseBody>?

                do {
                    recoveryAction = try await errorHandler.attemptRecovery(from: requestError)
                    try Task.checkCancellation()
                } catch let error as CancellationError {
                    let cancellationError = HTTPRequestPerformerError(
                        underlyingError: error,
                        requestConfiguration: request,
                        request: requestSnapshot,
                        response: responseSnapshot,
                    )
                    notifyResponseListenersOfResponse(.failure(cancellationError, nil))
                    throw cancellationError
                } catch let handlerError {
                    let recoveryError = HTTPRequestPerformerError(
                        underlyingError: HTTPRequestRecoveryError(
                            requestError: requestError,
                            underlyingError: handlerError,
                        ),
                        requestConfiguration: request,
                        request: requestSnapshot,
                        response: responseSnapshot,
                    )
                    notifyResponseListenersOfResponse(.failure(recoveryError, nil))
                    throw recoveryError
                }

                guard let recoveryAction else { continue }

                notifyResponseListenersOfResponse(.failure(requestError, recoveryAction))

                switch recoveryAction {
                case .returnResponse(let responseBody):
                    return responseBody
                case .replaceRequest(let newRequest):
                    let inheritedEnvironment = request.environmentValues.merging(
                        newRequest.environmentValues,
                    )
                    let inheritedRequest = newRequest.replacingEnvironmentValues(
                        with: inheritedEnvironment,
                    )
                    return try await perform(inheritedRequest)
                }
            }

            notifyResponseListenersOfResponse(.failure(requestError, nil))

            throw requestError
        }

        var httpRequest = request.baseHTTPRequest
        var requestBody: Data?

        do {
            for modifier in request.requestModifiers {
                try await modifier.modifyRequest(
                    &httpRequest,
                    body: &requestBody,
                    environment: effectiveEnvironment,
                )
                try Task.checkCancellation()
            }
        } catch {
            return try await attemptRecovery(
                underlyingError: error,
                requestSnapshot: HTTPRequestSnapshot(
                    body: requestBody,
                    request: httpRequest,
                ),
                responseSnapshot: nil,
            )
        }

        let requestSnapshot = HTTPRequestSnapshot(
            body: requestBody,
            request: httpRequest,
        )
        let responseSnapshot: HTTPResponseSnapshot

        do {
            responseSnapshot = try await dataProvider.data(
                for: httpRequest,
                body: requestBody,
                environment: effectiveEnvironment,
            )
            try Task.checkCancellation()
        } catch {
            return try await attemptRecovery(
                underlyingError: error,
                requestSnapshot: requestSnapshot,
                responseSnapshot: nil,
            )
        }

        do {
            var validationErrors: [any Error] = []

            for validator in request.responseValidators {
                do {
                    try Task.checkCancellation()
                    try await validator.validateResponse(
                        responseSnapshot,
                        to: requestSnapshot,
                        environment: effectiveEnvironment,
                    )
                } catch let error as CancellationError {
                    throw error
                } catch {
                    validationErrors.append(error)
                }
            }

            if !validationErrors.isEmpty {
                throw ResponseValidatorErrors(errors: validationErrors)
            }

            let modifiedResponseBody = try await request
                .responseBodyModifier
                .modifyBody(
                    responseSnapshot.body,
                    environment: effectiveEnvironment,
                    request: requestSnapshot,
                    response: responseSnapshot,
                )
            try Task.checkCancellation()

            notifyResponseListenersOfResponse(
                .success(
                    requestConfiguration: request,
                    responseBody: modifiedResponseBody,
                    request: requestSnapshot,
                    response: responseSnapshot,
                ),
            )

            return modifiedResponseBody
        } catch {
            return try await attemptRecovery(
                underlyingError: error,
                requestSnapshot: requestSnapshot,
                responseSnapshot: responseSnapshot,
            )
        }
    }

    public func environment<V>(
        _ keyPath: WritableKeyPath<HTTPRequestEnvironmentValues, V>,
        _ value: V,
    ) -> HTTPRequestPerformer {
        var environmentValues = environmentValues
        environmentValues[keyPath: keyPath] = value
        return HTTPRequestPerformer(
            dataProvider: dataProvider,
            environmentValues: environmentValues,
        )
    }
}

public enum HTTPRequestPerformResult<ResponseBody: Sendable>: Sendable {
    case success(
        requestConfiguration: HTTPRequestConfiguration<ResponseBody>,
        responseBody: ResponseBody,
        request: HTTPRequestSnapshot,
        response: HTTPResponseSnapshot,
    )

    case failure(
        HTTPRequestPerformerError<ResponseBody>,
        HTTPRequestErrorRecoveryAction<ResponseBody>?,
    )
}

/// A type that describes how to construct a HTTP request and how to handle the response.
public struct HTTPRequestConfiguration<ResponseBody: Sendable>: Sendable {
    /// The base request the ``requestModifiers`` will modify.
    public let baseHTTPRequest: HTTPRequest

    /// An array of values that will modify the ``baseHTTPRequest`` to produce the final request.
    ///
    /// These modifiers will be applied in the order they are provided.
    public let requestModifiers: [HTTPRequestModifier]

    /// An array of values that will be notified of the final result of each performance attempt.
    ///
    /// Listeners for a result are called sequentially in a background task. Request completion does
    /// not wait for them, and ordering between results from different requests is not guaranteed.
    public let responseListeners: [HTTPResponseListener]

    /// An array of values that can validate the response. All validators will be run, but if any
    /// validator fails the request will be considered failed. Validators run sequentially in the
    /// configured order and their errors are collected in a ``ResponseValidatorErrors`` value.
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

    /// Values that override the performer's environment defaults for this request.
    ///
    /// Errors and listener results contain an execution-local configuration whose values have
    /// already been merged with the performer defaults.
    public let environmentValues: HTTPRequestEnvironmentValues

    public init(
        baseHTTPRequest: HTTPRequest,
        requestModifiers: [HTTPRequestModifier] = [],
        responseListeners: [HTTPResponseListener] = [],
        responseValidators: [HTTPResponseValidator] = [],
        responseBodyModifier: any HTTPBodyModifier<Data, ResponseBody>,
        errorHandlers: [HTTPRequestPerformerErrorHandler] = [],
        environmentValues: HTTPRequestEnvironmentValues = HTTPRequestEnvironmentValues(),
    ) {
        self.baseHTTPRequest = baseHTTPRequest
        self.requestModifiers = requestModifiers
        self.responseListeners = responseListeners
        self.responseValidators = responseValidators
        self.responseBodyModifier = responseBodyModifier
        self.errorHandlers = errorHandlers
        self.environmentValues = environmentValues
    }

    public init(
        baseHTTPRequest: HTTPRequest,
        requestModifiers: [HTTPRequestModifier] = [],
        responseListeners: [HTTPResponseListener] = [],
        responseValidators: [HTTPResponseValidator] = [],
        responseBodyModifier: any HTTPBodyModifier<Data, ResponseBody> = MapHTTPResponseModifier(transform: { body, _, _, _ in body }),
        errorHandlers: [HTTPRequestPerformerErrorHandler] = [],
        environmentValues: HTTPRequestEnvironmentValues = HTTPRequestEnvironmentValues(),
    ) where ResponseBody == Data {
        self.baseHTTPRequest = baseHTTPRequest
        self.requestModifiers = requestModifiers
        self.responseListeners = responseListeners
        self.responseValidators = responseValidators
        self.responseBodyModifier = responseBodyModifier
        self.errorHandlers = errorHandlers
        self.environmentValues = environmentValues
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
            environmentValues: environmentValues,
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
            environmentValues: environmentValues,
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
            environmentValues: environmentValues,
        )
    }

    public func responseBodyModifier<NewResponseBody>(
        _ responseBodyModifier: any HTTPBodyModifier<ResponseBody, NewResponseBody>
    ) -> HTTPRequestConfiguration<NewResponseBody> where NewResponseBody: Sendable {
        let newResponseBodyModifier = self.responseBodyModifier.then(responseBodyModifier)
        return HTTPRequestConfiguration<NewResponseBody>(
            baseHTTPRequest: baseHTTPRequest,
            requestModifiers: requestModifiers,
            responseListeners: responseListeners,
            responseValidators: responseValidators,
            responseBodyModifier: newResponseBodyModifier,
            errorHandlers: errorHandlers,
            environmentValues: environmentValues,
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
            environmentValues: environmentValues,
        )
    }

    public func environment<V>(
        _ keyPath: WritableKeyPath<HTTPRequestEnvironmentValues, V>,
        _ value: V,
    ) -> Self {
        var environmentValues = environmentValues
        environmentValues[keyPath: keyPath] = value
        return HTTPRequestConfiguration<ResponseBody>(
            baseHTTPRequest: baseHTTPRequest,
            requestModifiers: requestModifiers,
            responseListeners: responseListeners,
            responseValidators: responseValidators,
            responseBodyModifier: responseBodyModifier,
            errorHandlers: errorHandlers,
            environmentValues: environmentValues,
        )
    }

    internal func replacingEnvironmentValues(
        with environmentValues: HTTPRequestEnvironmentValues,
    ) -> Self {
        HTTPRequestConfiguration<ResponseBody>(
            baseHTTPRequest: baseHTTPRequest,
            requestModifiers: requestModifiers,
            responseListeners: responseListeners,
            responseValidators: responseValidators,
            responseBodyModifier: responseBodyModifier,
            errorHandlers: errorHandlers,
            environmentValues: environmentValues,
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

    /// Returns a copy containing these values overlaid with explicitly stored values from
    /// `overrides`. Values from `overrides` take precedence.
    internal func merging(_ overrides: HTTPRequestEnvironmentValues) -> HTTPRequestEnvironmentValues {
        var values = self
        values.storage.merge(overrides.storage) { _, override in override }
        return values
    }
}

public protocol HTTPRequestEnvironmentKey {
    associatedtype Value: Sendable

    static var defaultValue: Value { get }
}

private enum URLRequestCachePolicyKey: HTTPRequestEnvironmentKey {
    static let defaultValue: URLRequest.CachePolicy? = nil
}

extension HTTPRequestEnvironmentValues {
    public var urlRequestCachePolicy: URLRequest.CachePolicy? {
        get { self[URLRequestCachePolicyKey.self] }
        set { self[URLRequestCachePolicyKey.self] = newValue }
    }
}

public protocol HTTPRequestModifier: Sendable {
    func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues,
    ) async throws
}

public protocol HTTPResponseListener: Sendable {
    func handleResponse<ResponseBody: Sendable>(
        _ response: HTTPRequestPerformResult<ResponseBody>,
    ) async
}

public protocol HTTPResponseValidator: Sendable {
    func validateResponse(
        _ response: HTTPResponseSnapshot,
        to request: HTTPRequestSnapshot,
        environment: HTTPRequestEnvironmentValues,
    ) async throws
}

/// The errors produced by response validators, in validator execution order.
public struct ResponseValidatorErrors: Error {
    public let errors: [any Error]

    internal init(errors: [any Error]) {
        precondition(!errors.isEmpty)
        self.errors = errors
    }
}

public struct HTTPStatusCodeValidator: HTTPResponseValidator {
    public init() {}

    public func validateResponse(
        _ response: HTTPResponseSnapshot,
        to request: HTTPRequestSnapshot,
        environment: HTTPRequestEnvironmentValues,
    ) throws {
        switch response.response.status.kind {
        case .clientError, .serverError, .invalid:
            throw HTTPStatusError(status: response.response.status)
        case .informational, .successful, .redirection:
            break
        }
    }
}

public struct HTTPStatusError: LocalizedError {
    public let status: HTTPResponse.Status

    public let errorDescription: String?

    public let failureReason: String?

    public init(status: HTTPResponse.Status) {
        self.status = status
        errorDescription = "HTTP status code \(status.code)"
        failureReason = status.reasonPhrase
    }
}

public protocol HTTPRequestPerformerErrorHandler: Sendable {
    /// Attempts to recover from a request failure. Throwing terminates recovery while preserving
    /// both this error and the original request error.
    func attemptRecovery<ResponseBody: Sendable>(
        from error: HTTPRequestPerformerError<ResponseBody>,
    ) async throws -> HTTPRequestErrorRecoveryAction<ResponseBody>?
}

public enum HTTPRequestErrorRecoveryAction<ResponseBody: Sendable>: Sendable {
    /// Performs a replacement request after inheriting the failed request's effective environment.
    /// Values explicitly set on the replacement request take precedence.
    case replaceRequest(HTTPRequestConfiguration<ResponseBody>)

    case returnResponse(ResponseBody)
}

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

extension HTTPBodyModifier {
    public func then<NewOutput>(
        _ newModifier: any HTTPBodyModifier<Output, NewOutput>,
    ) -> some HTTPBodyModifier<Input, NewOutput> {
        MapHTTPResponseModifier<Input, NewOutput>(transform: { [self] input, environment, request, response in
            let intermediate = try await self.modifyBody(
                input,
                environment: environment,
                request: request,
                response: response,
            )
            return try await newModifier.modifyBody(
                intermediate,
                environment: environment,
                request: request,
                response: response,
            )
        })
    }
}

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

public enum HTTPRequestURLMutationError: Error {
    case requestDoesNotHaveURL
    case failedToCreateURL
    case failedToEncodePathSegment(String)
}

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

public struct PathSegmentRequestModifier: HTTPRequestModifier {
    private let segment: String

    public init(segment: String) {
        self.segment = segment
    }

    public func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues,
    ) throws {
        guard let url = request.url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw HTTPRequestURLMutationError.requestDoesNotHaveURL
        }

        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/?#%")

        guard let encodedSegment = segment.addingPercentEncoding(
            withAllowedCharacters: allowedCharacters,
        ) else {
            throw HTTPRequestURLMutationError.failedToEncodePathSegment(segment)
        }

        var path = components.percentEncodedPath
        if !path.hasSuffix("/") {
            path.append("/")
        }
        path.append(encodedSegment)
        components.percentEncodedPath = path

        guard let updatedURL = components.url else {
            throw HTTPRequestURLMutationError.failedToCreateURL
        }

        request.url = updatedURL
    }
}

public struct QueryItemRequestModifier: HTTPRequestModifier {
    private let name: String
    private let value: String?

    public init(name: String, value: String?) {
        self.name = name
        self.value = value
    }

    public func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues,
    ) throws {
        guard let url = request.url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw HTTPRequestURLMutationError.requestDoesNotHaveURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: name, value: value))
        components.queryItems = queryItems

        guard let updatedURL = components.url else {
            throw HTTPRequestURLMutationError.failedToCreateURL
        }

        request.url = updatedURL
    }
}

extension HTTPRequestConfiguration {
    /// Appends and percent-encodes one path segment while preserving the existing query.
    public func pathSegment(_ segment: String) -> Self {
        requestModifier(PathSegmentRequestModifier(segment: segment))
    }

    /// Appends and percent-encodes path segments while preserving the existing query.
    public func pathSegments(_ segments: String...) -> Self {
        segments.reduce(self) { request, segment in
            request.pathSegment(segment)
        }
    }

    /// Appends a percent-encoded query item while preserving existing query items.
    public func queryItem(name: String, value: String?) -> Self {
        requestModifier(QueryItemRequestModifier(name: name, value: value))
    }
}

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

extension HTTPRequestConfiguration {
    public func validatingStatusCode() -> Self {
        responseValidator(HTTPStatusCodeValidator())
    }
}

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
