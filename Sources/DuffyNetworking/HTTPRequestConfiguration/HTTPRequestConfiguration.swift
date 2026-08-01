#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

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
    public let responseBodyModifiers: HTTPBodyModifiers<ResponseBody>

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
    ) {
        self.baseHTTPRequest = baseHTTPRequest
        self.requestModifiers = requestModifiers
        self.responseListeners = responseListeners
        self.responseValidators = responseValidators
        self.responseBodyModifiers = HTTPBodyModifiers(modifier: responseBodyModifier)
        self.errorHandlers = errorHandlers
        self.environmentValues = HTTPRequestEnvironmentValues()
    }

    public init(
        baseHTTPRequest: HTTPRequest,
        requestModifiers: [HTTPRequestModifier] = [],
        responseListeners: [HTTPResponseListener] = [],
        responseValidators: [HTTPResponseValidator] = [],
        errorHandlers: [HTTPRequestPerformerErrorHandler] = [],
    ) where ResponseBody == Data {
        self.baseHTTPRequest = baseHTTPRequest
        self.requestModifiers = requestModifiers
        self.responseListeners = responseListeners
        self.responseValidators = responseValidators
        self.responseBodyModifiers = HTTPBodyModifiers()
        self.errorHandlers = errorHandlers
        self.environmentValues = HTTPRequestEnvironmentValues()
    }

    private init(
        baseHTTPRequest: HTTPRequest,
        requestModifiers: [HTTPRequestModifier],
        responseListeners: [HTTPResponseListener],
        responseValidators: [HTTPResponseValidator],
        responseBodyModifiers: HTTPBodyModifiers<ResponseBody>,
        errorHandlers: [HTTPRequestPerformerErrorHandler],
        environmentValues: HTTPRequestEnvironmentValues,
    ) {
        self.baseHTTPRequest = baseHTTPRequest
        self.requestModifiers = requestModifiers
        self.responseListeners = responseListeners
        self.responseValidators = responseValidators
        self.responseBodyModifiers = responseBodyModifiers
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
            responseBodyModifiers: responseBodyModifiers,
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
            responseBodyModifiers: responseBodyModifiers,
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
            responseBodyModifiers: responseBodyModifiers,
            errorHandlers: errorHandlers,
            environmentValues: environmentValues,
        )
    }

    public func responseBodyModifier<NewResponseBody>(
        _ responseBodyModifier: any HTTPBodyModifier<ResponseBody, NewResponseBody>
    ) -> HTTPRequestConfiguration<NewResponseBody> where NewResponseBody: Sendable {
        let newResponseBodyModifiers = responseBodyModifiers.appending(
            modifier: responseBodyModifier
        )
        return HTTPRequestConfiguration<NewResponseBody>(
            baseHTTPRequest: baseHTTPRequest,
            requestModifiers: requestModifiers,
            responseListeners: responseListeners,
            responseValidators: responseValidators,
            responseBodyModifiers: newResponseBodyModifiers,
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
            responseBodyModifiers: responseBodyModifiers,
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
            responseBodyModifiers: responseBodyModifiers,
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
            responseBodyModifiers: responseBodyModifiers,
            errorHandlers: errorHandlers,
            environmentValues: environmentValues,
        )
    }
}
