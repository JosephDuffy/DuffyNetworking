public protocol HTTPRequestListener: Sendable {
    func handleRequest<ResponseBody: Sendable>(
        _ request: HTTPRequestSnapshot,
        configuration: HTTPRequestConfiguration<ResponseBody>,
    ) async
}
