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
