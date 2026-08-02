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
