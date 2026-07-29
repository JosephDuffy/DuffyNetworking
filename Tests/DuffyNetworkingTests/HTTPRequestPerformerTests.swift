import DuffyNetworking
import Foundation
import HTTPTypes
import Synchronization
import Testing

@Suite
struct HTTPRequestPerformerTests {
    @Test
    func effectiveEnvironmentReachesEveryPipelineStage() async throws {
        let recorder = StageRecorder()
        let (listenerValues, listenerContinuation) = AsyncStream.makeStream(of: String.self)
        let listenerValue = Task {
            var iterator = listenerValues.makeAsyncIterator()
            return await iterator.next()
        }
        let dataProvider = ClosureDataProvider { _, _, environment in
            await recorder.record(environment.testValue, for: "provider")
            return successfulResponse()
        }
        let performer = HTTPRequestPerformer(dataProvider: dataProvider)
            .environment(\.testValue, "performer")
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )
        .environment(\.testValue, "request")
        .requestModifier(EnvironmentRecordingModifier(recorder: recorder))
        .responseValidator(EnvironmentRecordingValidator(recorder: recorder))
        .mapResponseBody { body, environment, _, _ in
            await recorder.record(environment.testValue, for: "transformer")
            return body
        }
        .responseListener(EnvironmentRecordingListener(continuation: listenerContinuation))

        _ = try await performer.perform(request)

        #expect(await recorder.values == [
            "modifier": "request",
            "provider": "request",
            "transformer": "request",
            "validator": "request",
        ])
        #expect(await listenerValue.value == "request")
        #expect(request.environmentValues.testValue == "request")
    }

    @Test
    func environmentUsesDefaultsOverridesAndExplicitNil() async throws {
        let recorder = EnvironmentRecorder()
        let dataProvider = ClosureDataProvider { _, _, environment in
            await recorder.record(environment)
            return successfulResponse()
        }
        let performer = HTTPRequestPerformer(dataProvider: dataProvider)
            .environment(\.testValue, "performer")
            .environment(\.optionalTestValue, "performer optional")

        let inheritedRequest = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )
        _ = try await performer.perform(inheritedRequest)

        let overriddenRequest = inheritedRequest
            .environment(\.testValue, "request")
            .environment(\.optionalTestValue, Optional<String>.none)
        _ = try await performer.perform(overriddenRequest)

        let environments = await recorder.environments
        #expect(environments.count == 2)
        #expect(environments[0].testValue == "performer")
        #expect(environments[0].optionalTestValue == "performer optional")
        #expect(environments[1].testValue == "request")
        #expect(environments[1].optionalTestValue == nil)

        let defaultPerformer = HTTPRequestPerformer(dataProvider: dataProvider)
        _ = try await defaultPerformer.perform(inheritedRequest)
        #expect((await recorder.environments.last)?.testValue == "key default")
    }

    @Test
    func failuresExposeTheEffectiveEnvironmentToHandlersAndListeners() async throws {
        let errorHandler = EnvironmentRecordingErrorHandler()
        let (listenerValues, listenerContinuation) = AsyncStream.makeStream(of: String.self)
        let listenerValue = Task {
            var iterator = listenerValues.makeAsyncIterator()
            return await iterator.next()
        }
        let performer = HTTPRequestPerformer(
            dataProvider: ClosureDataProvider { _, _, _ in throw TestFailure.transport },
        )
        .environment(\.testValue, "performer")
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )
        .environment(\.testValue, "request")
        .errorHandler(errorHandler)
        .responseListener(EnvironmentRecordingListener(continuation: listenerContinuation))

        do {
            _ = try await performer.perform(request)
            Issue.record("Expected the transport to fail")
        } catch {
            #expect(error.requestConfiguration.environmentValues.testValue == "request")
        }

        #expect(await errorHandler.value == "request")
        #expect(await listenerValue.value == "request")
    }

    @Test
    func requestBodiesReachTheTransportIncludingEmptyAndAbsentBodies() async throws {
        let recorder = BodyRecorder()
        let dataProvider = ClosureDataProvider { _, body, _ in
            await recorder.record(body)
            return successfulResponse()
        }
        let performer = HTTPRequestPerformer(dataProvider: dataProvider)
        let baseRequest = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )

        _ = try await performer.perform(baseRequest)
        _ = try await performer.perform(
            baseRequest.requestModifier(BodyRequestModifier(body: Data())),
        )
        _ = try await performer.perform(
            baseRequest.requestModifier(BodyRequestModifier(body: Data("body".utf8))),
        )

        let bodies = await recorder.bodies
        #expect(bodies.count == 3)
        #expect(bodies[0] == nil)
        #expect(bodies[1] == Data())
        #expect(bodies[2] == Data("body".utf8))
    }

    @Test
    func validatorsRunSequentiallyAndAggregateErrorsInOrder() async throws {
        let recorder = ValidatorRecorder()
        let performer = HTTPRequestPerformer(
            dataProvider: ClosureDataProvider { _, _, _ in successfulResponse() },
        )
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )
        .responseValidator(RecordingValidator(id: 1, error: .first, recorder: recorder))
        .responseValidator(RecordingValidator(id: 2, error: nil, recorder: recorder))
        .responseValidator(RecordingValidator(id: 3, error: .second, recorder: recorder))

        do {
            _ = try await performer.perform(request)
            Issue.record("Expected response validation to fail")
        } catch {
            let validationErrors = try #require(error.underlyingError as? ResponseValidatorErrors)
            #expect(validationErrors.errors.compactMap { $0 as? TestFailure } == [.first, .second])
        }

        #expect(await recorder.ids == [1, 2, 3])
    }

    @Test
    func cancellationStopsValidationAndBypassesRecovery() async throws {
        let recorder = ValidatorRecorder()
        let errorHandler = CountingErrorHandler()
        let performer = HTTPRequestPerformer(
            dataProvider: ClosureDataProvider { _, _, _ in successfulResponse() },
        )
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )
        .responseValidator(CancellingValidator(recorder: recorder))
        .responseValidator(RecordingValidator(id: 2, error: nil, recorder: recorder))
        .errorHandler(errorHandler)

        do {
            _ = try await performer.perform(request)
            Issue.record("Expected cancellation to fail the request")
        } catch {
            #expect(error.underlyingError is CancellationError)
        }

        #expect(await recorder.ids == [1])
        #expect(await errorHandler.count == 0)
    }

    @Test
    func errorHandlerOwnsRetryStateThroughTheEnvironment() async throws {
        let dataProvider = RetryingDataProvider(succeedingAttempt: 2)
        let performer = HTTPRequestPerformer(dataProvider: dataProvider)
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )
        .errorHandler(EnvironmentRetryHandler(maximumAttempts: 2))

        let response = try await performer.perform(request)

        #expect(response == Data("success".utf8))
        #expect(await dataProvider.attempts == [0, 1, 2])
    }

    @Test
    func freshReplacementConfigurationInheritsTheFailedRequestEnvironment() async throws {
        let dataProvider = RetryingDataProvider(succeedingAttempt: 1)
        let performer = HTTPRequestPerformer(dataProvider: dataProvider)
            .environment(\.testValue, "performer")
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )
        .environment(\.testValue, "request")
        .errorHandler(FreshConfigurationRetryHandler(testValueOverride: nil))

        _ = try await performer.perform(request)

        #expect(await dataProvider.testValues == ["request", "request"])
    }

    @Test
    func freshReplacementConfigurationOverridesInheritedEnvironmentValues() async throws {
        let dataProvider = RetryingDataProvider(succeedingAttempt: 1)
        let performer = HTTPRequestPerformer(dataProvider: dataProvider)
            .environment(\.testValue, "performer")
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )
        .environment(\.testValue, "request")
        .errorHandler(FreshConfigurationRetryHandler(testValueOverride: "replacement"))

        _ = try await performer.perform(request)

        #expect(await dataProvider.testValues == ["request", "replacement"])
    }

    @Test
    func retryHandlerCanStopRecovery() async throws {
        let dataProvider = RetryingDataProvider(succeedingAttempt: 3)
        let performer = HTTPRequestPerformer(dataProvider: dataProvider)
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )
        .errorHandler(EnvironmentRetryHandler(maximumAttempts: 1))

        do {
            _ = try await performer.perform(request)
            Issue.record("Expected transport failure after the retry limit")
        } catch {
            #expect(error.requestConfiguration.environmentValues.retryAttempt == 1)
        }

        #expect(await dataProvider.attempts == [0, 1])
    }

    @Test
    func recoveryFailurePreservesTheOriginalError() async throws {
        let performer = HTTPRequestPerformer(
            dataProvider: ClosureDataProvider { _, _, _ in throw TestFailure.transport },
        )
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )
        .errorHandler(ThrowingErrorHandler())

        do {
            _ = try await performer.perform(request)
            Issue.record("Expected recovery to fail")
        } catch {
            let recoveryError = try #require(
                error.underlyingError as? HTTPRequestRecoveryError<Data>,
            )
            #expect(recoveryError.requestError.underlyingError as? TestFailure == .transport)
            #expect(recoveryError.underlyingError as? TestFailure == .recovery)
        }
    }

    @Test
    func listenerReceivesEffectiveEnvironmentAsynchronously() async throws {
        let (values, continuation) = AsyncStream.makeStream(of: String.self)
        let listenerValue = Task {
            var iterator = values.makeAsyncIterator()
            return await iterator.next()
        }
        let performer = HTTPRequestPerformer(
            dataProvider: ClosureDataProvider { _, _, _ in successfulResponse() },
        )
        .environment(\.testValue, "effective")
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )
        .responseListener(EnvironmentRecordingListener(continuation: continuation))

        _ = try await performer.perform(request)

        #expect(await listenerValue.value == "effective")
    }

    @Test
    func jsonDateStrategySupportsPerformerDefaultsAndRequestOverrides() async throws {
        let iso8601Body = Data(#"{"date":"2020-01-02T03:04:05Z"}"#.utf8)
        let iso8601Performer = HTTPRequestPerformer(
            dataProvider: ClosureDataProvider { _, _, _ in successfulResponse(body: iso8601Body) },
        )
        .environment(\.jsonDateDecodingStrategy, .iso8601)
        let baseRequest = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )

        let iso8601DTO: DateDTO = try await iso8601Performer.perform(
            baseRequest.decodingJSONBody(),
        )
        #expect(iso8601DTO.date.timeIntervalSince1970 == 1_577_934_245)

        let secondsBody = Data(#"{"date":123}"#.utf8)
        let secondsPerformer = HTTPRequestPerformer(
            dataProvider: ClosureDataProvider { _, _, _ in successfulResponse(body: secondsBody) },
        )
        .environment(\.jsonDateDecodingStrategy, .iso8601)
        let secondsRequest = baseRequest
            .jsonDateDecodingStrategy(.secondsSince1970)
            .decodingJSONBody(ofType: DateDTO.self)

        let secondsDTO = try await secondsPerformer.perform(secondsRequest)
        #expect(secondsDTO.date.timeIntervalSince1970 == 123)
    }

    @Test
    func pathSegmentsAndQueryItemsAreSafelyEncoded() async throws {
        let recorder = RequestRecorder()
        let dataProvider = ClosureDataProvider { request, _, _ in
            await recorder.record(request)
            return successfulResponse()
        }
        let performer = HTTPRequestPerformer(dataProvider: dataProvider)
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(
                url: try testURL("https://example.com/api?existing=1"),
            ),
        )
        .pathSegments("users", "a/b ?")
        .queryItem(name: "search", value: "a&b")

        _ = try await performer.perform(request)

        let performedRequest = try #require(await recorder.requests.first)
        let url = try #require(performedRequest.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.percentEncodedPath == "/api/users/a%2Fb%20%3F")
        #expect(components.queryItems == [
            URLQueryItem(name: "existing", value: "1"),
            URLQueryItem(name: "search", value: "a&b"),
        ])
    }

    @Test
    func statusValidationExposesTheHTTPStatus() async throws {
        let performer = HTTPRequestPerformer(
            dataProvider: ClosureDataProvider { _, _, _ in
                HTTPResponseSnapshot(
                    body: Data(),
                    response: HTTPResponse(status: .unauthorized),
                )
            },
        )
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )
        .validatingStatusCode()

        do {
            _ = try await performer.perform(request)
            Issue.record("Expected status validation to fail")
        } catch {
            let validationErrors = try #require(error.underlyingError as? ResponseValidatorErrors)
            let statusError = try #require(validationErrors.errors.first as? HTTPStatusError)
            #expect(statusError.status == .unauthorized)
        }
    }

    @Test
    func cachePolicyReachesTheTransport() async throws {
        let recorder = EnvironmentRecorder()
        let performer = HTTPRequestPerformer(
            dataProvider: ClosureDataProvider { _, _, environment in
                await recorder.record(environment)
                return successfulResponse()
            },
        )
        .environment(\.urlRequestCachePolicy, .reloadIgnoringLocalCacheData)
        let request = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: try testURL()),
        )

        _ = try await performer.perform(request)

        #expect((await recorder.environments.first)?.urlRequestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test
    @available(macOS 15.0, *)
    func urlSessionProviderHandlesBodiesAndAppliesCachePolicy() async throws {
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let provider = URLSessionHTTPRequestDataProvider(urlSession: session)
        var environment = HTTPRequestEnvironmentValues()
        environment.urlRequestCachePolicy = .reloadIgnoringLocalCacheData
        let request = HTTPRequest(method: .post, url: try testURL())

        let response = try await provider.data(
            for: request,
            body: Data("request body".utf8),
            environment: environment,
        )

        #expect(response.body == Data("response body".utf8))
        let urlRequest = try #require(StubURLProtocol.recordedRequests.first)
        #expect(urlRequest.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(urlRequest.httpMethod == "POST")
    }
}

private enum TestFailure: Error, Equatable {
    case first
    case second
    case transport
    case recovery
}

private enum TestValueKey: HTTPRequestEnvironmentKey {
    static let defaultValue = "key default"
}

private enum OptionalTestValueKey: HTTPRequestEnvironmentKey {
    static let defaultValue: String? = nil
}

private enum RetryAttemptKey: HTTPRequestEnvironmentKey {
    static let defaultValue = 0
}

extension HTTPRequestEnvironmentValues {
    fileprivate var testValue: String {
        get { self[TestValueKey.self] }
        set { self[TestValueKey.self] = newValue }
    }

    fileprivate var optionalTestValue: String? {
        get { self[OptionalTestValueKey.self] }
        set { self[OptionalTestValueKey.self] = newValue }
    }

    fileprivate var retryAttempt: Int {
        get { self[RetryAttemptKey.self] }
        set { self[RetryAttemptKey.self] = newValue }
    }
}

private struct ClosureDataProvider: HTTPRequestDataProvider {
    typealias Operation = @Sendable (
        HTTPRequest,
        Data?,
        HTTPRequestEnvironmentValues,
    ) async throws -> HTTPResponseSnapshot

    private let operation: Operation

    init(operation: @escaping Operation) {
        self.operation = operation
    }

    func data(
        for request: HTTPRequest,
        body: Data?,
        environment: HTTPRequestEnvironmentValues,
    ) async throws -> HTTPResponseSnapshot {
        try await operation(request, body, environment)
    }
}

private struct BodyRequestModifier: HTTPRequestModifier {
    let body: Data?

    func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues,
    ) {
        body = self.body
    }
}

private struct EnvironmentRecordingModifier: HTTPRequestModifier {
    let recorder: StageRecorder

    func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues,
    ) async {
        await recorder.record(environment.testValue, for: "modifier")
    }
}

private struct EnvironmentRecordingValidator: HTTPResponseValidator {
    let recorder: StageRecorder

    func validateResponse(
        _ response: HTTPResponseSnapshot,
        to request: HTTPRequestSnapshot,
        environment: HTTPRequestEnvironmentValues,
    ) async {
        await recorder.record(environment.testValue, for: "validator")
    }
}

private struct EnvironmentRecordingListener: HTTPResponseListener {
    let continuation: AsyncStream<String>.Continuation

    func handleResponse<ResponseBody: Sendable>(
        _ response: HTTPRequestPerformResult<ResponseBody>,
    ) {
        switch response {
        case .success(let configuration, _, _, _):
            continuation.yield(configuration.environmentValues.testValue)
        case .failure(let error, _):
            continuation.yield(error.requestConfiguration.environmentValues.testValue)
        }
    }
}

private struct RecordingValidator: HTTPResponseValidator {
    let id: Int
    let error: TestFailure?
    let recorder: ValidatorRecorder

    func validateResponse(
        _ response: HTTPResponseSnapshot,
        to request: HTTPRequestSnapshot,
        environment: HTTPRequestEnvironmentValues,
    ) async throws {
        await recorder.record(id)
        if let error {
            throw error
        }
    }
}

private struct CancellingValidator: HTTPResponseValidator {
    let recorder: ValidatorRecorder

    func validateResponse(
        _ response: HTTPResponseSnapshot,
        to request: HTTPRequestSnapshot,
        environment: HTTPRequestEnvironmentValues,
    ) async throws {
        await recorder.record(1)
        throw CancellationError()
    }
}

private actor CountingErrorHandler: HTTPRequestPerformerErrorHandler {
    private(set) var count = 0

    func attemptRecovery<ResponseBody: Sendable>(
        from error: HTTPRequestPerformerError<ResponseBody>,
    ) -> HTTPRequestErrorRecoveryAction<ResponseBody>? {
        count += 1
        return nil
    }
}

private actor EnvironmentRecordingErrorHandler: HTTPRequestPerformerErrorHandler {
    private(set) var value: String?

    func attemptRecovery<ResponseBody: Sendable>(
        from error: HTTPRequestPerformerError<ResponseBody>,
    ) -> HTTPRequestErrorRecoveryAction<ResponseBody>? {
        value = error.requestConfiguration.environmentValues.testValue
        return nil
    }
}

private struct EnvironmentRetryHandler: HTTPRequestPerformerErrorHandler {
    let maximumAttempts: Int

    func attemptRecovery<ResponseBody: Sendable>(
        from error: HTTPRequestPerformerError<ResponseBody>,
    ) -> HTTPRequestErrorRecoveryAction<ResponseBody>? {
        let attempt = error.requestConfiguration.environmentValues.retryAttempt
        guard attempt < maximumAttempts else { return nil }

        return .replaceRequest(
            error.requestConfiguration.environment(\.retryAttempt, attempt + 1),
        )
    }
}

private struct FreshConfigurationRetryHandler: HTTPRequestPerformerErrorHandler {
    let testValueOverride: String?

    func attemptRecovery<ResponseBody: Sendable>(
        from error: HTTPRequestPerformerError<ResponseBody>,
    ) -> HTTPRequestErrorRecoveryAction<ResponseBody>? {
        let attempt = error.requestConfiguration.environmentValues.retryAttempt
        guard attempt == 0 else { return nil }

        var replacement = HTTPRequestConfiguration<ResponseBody>(
            baseHTTPRequest: error.requestConfiguration.baseHTTPRequest,
            responseBodyModifier: error.requestConfiguration.responseBodyModifier,
        )
        .environment(\.retryAttempt, attempt + 1)

        if let testValueOverride {
            replacement = replacement.environment(\.testValue, testValueOverride)
        }

        return .replaceRequest(replacement)
    }
}

private struct ThrowingErrorHandler: HTTPRequestPerformerErrorHandler {
    func attemptRecovery<ResponseBody: Sendable>(
        from error: HTTPRequestPerformerError<ResponseBody>,
    ) throws -> HTTPRequestErrorRecoveryAction<ResponseBody>? {
        throw TestFailure.recovery
    }
}

private actor RetryingDataProvider: HTTPRequestDataProvider {
    private let succeedingAttempt: Int
    private(set) var attempts: [Int] = []
    private(set) var testValues: [String] = []

    init(succeedingAttempt: Int) {
        self.succeedingAttempt = succeedingAttempt
    }

    func data(
        for request: HTTPRequest,
        body: Data?,
        environment: HTTPRequestEnvironmentValues,
    ) throws -> HTTPResponseSnapshot {
        let attempt = environment.retryAttempt
        attempts.append(attempt)
        testValues.append(environment.testValue)
        guard attempt >= succeedingAttempt else {
            throw TestFailure.transport
        }
        return successfulResponse(body: Data("success".utf8))
    }
}

private actor StageRecorder {
    private(set) var values: [String: String] = [:]

    func record(_ value: String, for stage: String) {
        values[stage] = value
    }
}

private actor EnvironmentRecorder {
    private(set) var environments: [HTTPRequestEnvironmentValues] = []

    func record(_ environment: HTTPRequestEnvironmentValues) {
        environments.append(environment)
    }
}

private actor BodyRecorder {
    private(set) var bodies: [Data?] = []

    func record(_ body: Data?) {
        bodies.append(body)
    }
}

private actor ValidatorRecorder {
    private(set) var ids: [Int] = []

    func record(_ id: Int) {
        ids.append(id)
    }
}

private actor RequestRecorder {
    private(set) var requests: [HTTPRequest] = []

    func record(_ request: HTTPRequest) {
        requests.append(request)
    }
}

private struct DateDTO: Decodable, Sendable {
    let date: Date
}

private func successfulResponse(body: Data = Data()) -> HTTPResponseSnapshot {
    HTTPResponseSnapshot(
        body: body,
        response: HTTPResponse(status: .ok),
    )
}

private func testURL(_ string: String = "https://example.com") throws -> URL {
    guard let url = URL(string: string) else {
        throw HTTPRequestURLMutationError.failedToCreateURL
    }
    return url
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
private final class StubURLProtocol: URLProtocol {
    private static let requests = Mutex<[URLRequest]>([])

    static var recordedRequests: [URLRequest] {
        requests.withLock { $0 }
    }

    static func reset() {
        requests.withLock { $0.removeAll() }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.withLock { $0.append(request) }

        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil,
            )
        else {
            client?.urlProtocol(self, didFailWithError: TestFailure.transport)
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("response body".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
