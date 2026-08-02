import DuffyNetworking
import Foundation
import HTTPTypes

/// An example use of an API client built on top of DuffyNetworking. This is not part of the
/// DuffyNetworking library itself but this can be treated as a check that the API remains the same.
@APIClient
struct GitHubAPI: Sendable {
    private let httpRequestPerformer: HTTPRequestPerformer

    init(dataProvider: HTTPRequestDataProvider = URLSessionHTTPRequestDataProvider.shared) {
        httpRequestPerformer = HTTPRequestPerformer(dataProvider: dataProvider)
    }

    private func makeBaseRequest() -> HTTPRequestConfiguration<Data> {
        HTTPRequestConfiguration<Data>(
            baseHTTPRequest: HTTPRequest(
                url: URL(string: "https://api.github.com")!,
            )
        )
        .replaceHeader(name: .accept, value: "application/vnd.github.v3+json")
        .replaceHeader(name: .gitHubAPIVersion, value: "2026-03-10")
        .jsonDateDecodingStrategy(.iso8601)
        .validatingStatusCode()
        .debugOnly { $0.logCurlRequestToStdout() }
    }
}

extension HTTPField.Name {
    /// X-GitHub-Api-Version
    static let gitHubAPIVersion = HTTPField.Name("X-GitHub-Api-Version")!
}

extension GitHubAPI {
    func getUserRepos(username: String) async throws -> [GitHubRepoDTO] {
        try await buildAndPerformRequest { baseRequest in
            baseRequest
                .pathSegments("users", username, "repos")
                .decodingJSONBody()
        }
    }
}

struct GitHubRepoDTO: Decodable, Sendable {
    let id: Int
    let name: String
}
