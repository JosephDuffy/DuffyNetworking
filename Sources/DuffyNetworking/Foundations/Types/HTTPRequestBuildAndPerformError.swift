public enum HTTPRequestBuildAndPerformError<BuilderError: Error, ResponseBody: Sendable>: Error {
    case buildError(BuilderError)
    case performError(HTTPRequestPerformerError<ResponseBody>)
}
