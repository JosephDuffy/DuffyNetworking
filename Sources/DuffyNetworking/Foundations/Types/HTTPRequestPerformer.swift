#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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

    public func build<ResponseBody: Sendable>(
        _ requestConfiguration: HTTPRequestConfiguration<ResponseBody>,
    ) async throws(HTTPRequestPerformerError<ResponseBody>) -> HTTPRequestSnapshot {
        let effectiveEnvironment = environmentValues.merging(
            requestConfiguration.environmentValues,
        )
        let request = requestConfiguration.replacingEnvironmentValues(
            with: effectiveEnvironment,
        )

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
            throw HTTPRequestPerformerError(
                underlyingError: error,
                requestConfiguration: request,
                request: nil,
                response: nil,
            )
        }

        return HTTPRequestSnapshot(
            body: requestBody,
            request: httpRequest,
        )
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

        if !request.requestListeners.isEmpty {
            Task(priority: .background) { @concurrent in
                for requestListener in request.requestListeners {
                    await requestListener.handleRequest(requestSnapshot, configuration: request)
                }
            }
        }
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
                .responseBodyModifiers
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
