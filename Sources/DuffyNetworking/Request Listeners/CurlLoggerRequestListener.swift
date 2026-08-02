#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

extension HTTPRequestEnvironmentValues {
    @HTTPRequestEnvironmentEntry
    public var sensitiveRequestValues: Set<String> = []
}

private enum SensitiveHTTPRequestHeadersKey: HTTPRequestEnvironmentKey {
    static let defaultValue: Set<HTTPField.Name> = [
        .authorization,
        .wwwAuthenticate,
        .cookie,
        .proxyAuthorization,
    ]
}

extension HTTPRequestEnvironmentValues {
    @HTTPRequestEnvironmentEntry
    public var sensitiveRequestHeaders: Set<HTTPField.Name> = [
        .authorization,
        .wwwAuthenticate,
        .cookie,
        .proxyAuthorization,
    ]
}

extension HTTPRequestEnvironmentValues {
    @HTTPRequestEnvironmentEntry
    public var insensitiveCookieNames: Set<String> = []
}

public struct CurlLoggerRequestListener: HTTPRequestListener {
    public static func logToStdout(
        prefix: String = "",
        additionalSensitiveHeaders: Set<HTTPField.Name> = [],
        additionalInsensitiveCookieNames: Set<String> = [],
    ) -> Self {
        CurlLoggerRequestListener(
            prefix: prefix,
            additionalSensitiveHeaders: additionalSensitiveHeaders,
            additionalInsensitiveCookieNames: additionalInsensitiveCookieNames,
        ) { message in
            print(message)
        }
    }

    private let prefix: String

    private let logMessage: @Sendable (String) -> Void

    private let additionalSensitiveHeaders: Set<HTTPField.Name>

    private let additionalInsensitiveCookieNames: Set<String>

    public init(
        prefix: String = "",
        additionalSensitiveHeaders: Set<HTTPField.Name> = [],
        additionalInsensitiveCookieNames: Set<String> = [],
        logMessage: @Sendable @escaping (String) -> Void,
    ) {
        self.prefix = prefix
        self.additionalSensitiveHeaders = additionalSensitiveHeaders
        self.additionalInsensitiveCookieNames = additionalInsensitiveCookieNames
        self.logMessage = logMessage
    }

    public func handleRequest(
        _ request: HTTPRequestSnapshot,
        configuration: HTTPRequestConfiguration<some Sendable>
    ) async {
        guard let url = request.request.url else { return }
        let sensitiveRequestValues = configuration.environmentValues.sensitiveRequestValues
        let sensitiveHeaders = configuration.environmentValues.sensitiveRequestHeaders.union(additionalSensitiveHeaders)
        let insensitiveCookieNames = configuration.environmentValues.insensitiveCookieNames.union(additionalInsensitiveCookieNames)

        var curlCommand = prefix + "curl"

        if var body = request.body {
            for sensitiveRequestValue in sensitiveRequestValues {
                let sensitiveRequestValueData = Data(sensitiveRequestValue.utf8)
                while let range = body.range(of: sensitiveRequestValueData) {
                    body.replaceSubrange(range, with: Data("<redacted>".utf8))
                }
            }

            let base64 = body.base64EncodedString()
            curlCommand += " --data-binary @<(echo \"\(base64)\" | base64 --decode)"
        }

        curlCommand += " --request \(shellEscape(request.request.method.rawValue))"

        for field in request.request.headerFields {
            func redactedValue(_ value: String, ignoreSensitiveHeaders: Bool = false) -> String {
                if !ignoreSensitiveHeaders, sensitiveHeaders.contains(field.name) {
                    return "<redacted>"
                } else {
                    var value = value
                    for sensitiveRequestValue in sensitiveRequestValues {
                        value = value.replacingOccurrences(of: sensitiveRequestValue, with: "<redacted>")
                    }
                    return value
                }
            }

            if field.name == .cookie {
                let split = field.value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if split.count == 2 {
                    let cookieName = split[0].trimmingCharacters(in: .whitespaces)
                    let cookieValue = split[1].trimmingCharacters(in: .whitespaces)

                    let cookieIsInsensitive = insensitiveCookieNames.contains(cookieName)

                    curlCommand += " --cookie \(shellEscape(cookieName + "=" + redactedValue(cookieValue, ignoreSensitiveHeaders: cookieIsInsensitive)))"
                } else {
                    curlCommand += " --cookie \(shellEscape(redactedValue(field.value)))"
                }
            } else {
                curlCommand += " --header \(shellEscape(field.name.rawName + ": " + redactedValue(field.value)))"
            }
        }


        var absoluteURLString = url.absoluteString
        for sensitiveRequestValue in sensitiveRequestValues {
            absoluteURLString = absoluteURLString.replacingOccurrences(of: sensitiveRequestValue, with: "<redacted>")
        }
        curlCommand += " \(shellEscape(absoluteURLString))"
        logMessage(curlCommand)
    }

    private func shellEscape(_ string: String) -> String {
        var escapedString = ""
        escapedString.reserveCapacity(string.count)

        for character in string {
            switch character {
            case "\\", "\"", "$":
                escapedString.append("\\")
                escapedString.append(character)
            case "`", "!":
                // zsh and bash need ` escaping but fish does not. There's no harm in escaping it
                // this way so we include it here. There may be more shells but this covers enough
                // for now.
                escapedString.append(contentsOf: "\"'\(character)'\"")
            default:
                escapedString.append(character)
            }
        }

        return "\"\(escapedString)\""
    }
}

extension HTTPRequestConfiguration {
    public func logCurlRequestToStdout(
        prefix: String = "",
        additionalSensitiveHeaders: Set<HTTPField.Name> = [],
        additionalInsensitiveCookieNames: Set<String> = [],
    ) -> Self {
        requestListener(
            CurlLoggerRequestListener.logToStdout(
                prefix: prefix,
                additionalSensitiveHeaders: additionalSensitiveHeaders,
                additionalInsensitiveCookieNames: additionalInsensitiveCookieNames,
            )
        )
    }
}
