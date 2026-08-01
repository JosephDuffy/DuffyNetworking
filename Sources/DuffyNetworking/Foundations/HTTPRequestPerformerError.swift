public struct HTTPRequestPerformerError<ResponseBody: Sendable>: Error {
    public let underlyingError: any Error

    public let requestConfiguration: HTTPRequestConfiguration<ResponseBody>

    public let request: HTTPRequestSnapshot?

    public let response: HTTPResponseSnapshot?
}
