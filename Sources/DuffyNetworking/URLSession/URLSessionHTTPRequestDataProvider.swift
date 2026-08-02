#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes
import HTTPTypesFoundation

public struct URLSessionHTTPRequestDataProvider: HTTPRequestDataProvider, Sendable {
    public static var shared: URLSessionHTTPRequestDataProvider {
        URLSessionHTTPRequestDataProvider(
            urlSession: .shared,
            invalidateOnDeinit: false,
        )
    }

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
