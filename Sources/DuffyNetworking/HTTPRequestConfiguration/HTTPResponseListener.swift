public protocol HTTPResponseListener: Sendable {
    func handleResponse<ResponseBody: Sendable>(
        _ response: HTTPRequestPerformResult<ResponseBody>,
    ) async
}
