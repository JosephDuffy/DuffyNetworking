public protocol HTTPRequestPerformerErrorHandler: Sendable {
    /// Attempts to recover from a request failure. Throwing terminates recovery while preserving
    /// both this error and the original request error.
    func attemptRecovery<ResponseBody: Sendable>(
        from error: HTTPRequestPerformerError<ResponseBody>,
        requestPerformer: HTTPRequestPerformer,
    ) async throws -> HTTPRequestErrorRecoveryAction<ResponseBody>?
}
