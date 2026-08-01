public enum HTTPRequestErrorRecoveryAction<ResponseBody: Sendable>: Sendable {
    /// Performs a replacement request after inheriting the failed request's effective environment.
    /// Values explicitly set on the replacement request take precedence.
    case replaceRequest(HTTPRequestConfiguration<ResponseBody>)

    case returnResponse(ResponseBody)
}
