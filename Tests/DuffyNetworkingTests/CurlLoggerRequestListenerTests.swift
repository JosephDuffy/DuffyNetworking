import DuffyNetworking
import DuffyNetworkingTestSupport
import Foundation
import HTTPTypes
import Testing

@Suite
struct CurlLoggerRequestListenerTests {
    private let stubBaseURL = "https://example.com/"

    @Test
    func redactsSeparatelyStoredCookiesIndependently() async throws {
        let message = try await loggedCommand {
            $0
                .appendHeader(name: .cookie, value: "theme=dark")
                .appendHeader(name: .cookie, value: "session=secret")
                .environment(\.insensitiveCookieNames, ["theme"])
        }

        #expect(
            message == """
            curl --request "GET" --cookie "theme=dark" --cookie "session=<redacted>" "\(stubBaseURL)"
            """
        )
    }

    @Test
    func redactsCombinedCookiesIndependently() async throws {
        let message = try await loggedCommand {
            $0
                .appendHeader(name: .cookie, value: "theme=dark; session=secret")
                .environment(\.insensitiveCookieNames, ["theme"])
        }

        #expect(
            message == """
            curl --request "GET" --cookie "theme=dark; session=secret" "\(stubBaseURL)"
            """
        )
    }

    @Test
    func escapesQuotesAndKeepsHeaderInSingleArgument() async throws {
        let headerName = try #require(HTTPField.Name("X-Test"))
        let message = try await loggedCommand {
            $0.appendHeader(name: headerName, value: #"value with "quotes""#)
        }

        #expect(
            message == #"curl --request "GET" --header "X-Test: value with \"quotes\"" "\#(stubBaseURL)""#
        )
    }

    @Test
    func escapesShellExpansionCharactersInHeaderValues() async throws {
        let headerName = try #require(HTTPField.Name("X-Test"))
        let message = try await loggedCommand {
            $0.appendHeader(
                name: headerName,
                value: #"backslash \, variable $HOME, substitution $(whoami), backticks `whoami`, bang !, apostrophe '"#,
            )
        }

        #expect(
            message == #"curl --request "GET" --header "X-Test: backslash \\, variable \$HOME, substitution \$(whoami), backticks "'`'"whoami"'`'", bang "'!'", apostrophe '" "\#(stubBaseURL)""#
        )
    }

    @Test
    func redactsEveryOccurrenceOfSensitiveValueInBody() async throws {
        let redactedBody = Data("<redacted> and <redacted>".utf8).base64EncodedString()
        let message = try await loggedCommand {
            $0
                .requestModifier(SetBodyRequestModifier(body: Data("secret and secret".utf8)))
                .environment(\.sensitiveRequestValues, ["secret"])
        }

        #expect(message == "curl --data-binary @<(echo \"\(redactedBody)\" | base64 --decode) --request \"GET\" \"\(stubBaseURL)\"")
    }

    @Test
    func redactsEveryOccurrenceOfSensitiveValueInHeaders() async throws {
        let message = try await loggedCommand {
            $0
                .replaceHeader(name: HTTPField.Name("X-Secret")!, value: "secret-value")
                .replaceHeader(name: HTTPField.Name("X-Secret-2")!, value: "value-secret-2")
                .replaceHeader(name: HTTPField.Name("X-Public")!, value: "public-value")
                .environment(\.sensitiveRequestValues, ["secret"])
        }

        #expect(message == #"curl --request "GET" --header "X-Secret: <redacted>-value" --header "X-Secret-2: value-<redacted>-2" --header "X-Public: public-value" "\#(stubBaseURL)""#)
    }

    @Test
    func redactsExtraSensitiveHeaders() async throws {
        let message = try await loggedCommand {
            $0
                .replaceHeader(name: HTTPField.Name("X-Sensitive")!, value: "secret-value")
                .replaceHeader(name: HTTPField.Name("X-Public")!, value: "public-value")
                .environment(\.sensitiveRequestHeaders, [HTTPField.Name("X-Sensitive")!])
        }

        #expect(message == #"curl --request "GET" --header "X-Sensitive: <redacted>" --header "X-Public: public-value" "\#(stubBaseURL)""#)
    }

    private func loggedCommand<ResponseBody: Sendable>(
        modifyingBaseRequest: (_ baseRequestConfiguration: HTTPRequestConfiguration<Data>) -> HTTPRequestConfiguration<ResponseBody>,
    ) async throws -> String {
        let baseRequestConfiguration = HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(url: URL(string: "\(stubBaseURL)")!),
        )
        let requestConfiguration = modifyingBaseRequest(baseRequestConfiguration)
        return try await loggedCommand(from: requestConfiguration)
    }

    private func loggedCommand<ResponseBody: Sendable>(
        from requestConfiguration: HTTPRequestConfiguration<ResponseBody>,
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let recordingListener = CurlLoggerRequestListener() { message in
                continuation.resume(returning: message)
            }
            Task {
                let performer = HTTPRequestPerformer(dataProvider: StubHTTPRequestDataProvider())
                do {
                    let request = try await performer.build(requestConfiguration)
                    await recordingListener.handleRequest(request, configuration: requestConfiguration)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private struct SetBodyRequestModifier: HTTPRequestModifier {
    let body: Data

    func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues,
    ) {
        body = self.body
    }
}
