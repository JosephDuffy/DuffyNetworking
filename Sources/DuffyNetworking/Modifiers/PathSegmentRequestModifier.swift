#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import HTTPTypes

public struct PathSegmentRequestModifier: HTTPRequestModifier {
    private let segment: String

    public init(segment: String) {
        self.segment = segment
    }

    public func modifyRequest(
        _ request: inout HTTPRequest,
        body: inout Data?,
        environment: HTTPRequestEnvironmentValues,
    ) throws {
        guard let url = request.url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw HTTPRequestURLMutationError.requestDoesNotHaveURL
        }

        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/?#%")

        guard let encodedSegment = segment.addingPercentEncoding(
            withAllowedCharacters: allowedCharacters,
        ) else {
            throw HTTPRequestURLMutationError.failedToEncodePathSegment(segment)
        }

        var path = components.percentEncodedPath
        if !path.hasSuffix("/") {
            path.append("/")
        }
        path.append(encodedSegment)
        components.percentEncodedPath = path

        guard let updatedURL = components.url else {
            throw HTTPRequestURLMutationError.failedToCreateURL
        }

        request.url = updatedURL
    }
}

extension HTTPRequestConfiguration {
    /// Appends and percent-encodes one path segment while preserving the existing query.
    public func pathSegment(_ segment: String) -> Self {
        requestModifier(PathSegmentRequestModifier(segment: segment))
    }

    /// Appends and percent-encodes path segments while preserving the existing query.
    public func pathSegments(_ segments: String...) -> Self {
        segments.reduce(self) { request, segment in
            request.pathSegment(segment)
        }
    }
}
