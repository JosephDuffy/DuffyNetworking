public enum HTTPRequestURLMutationError: Error {
    case requestDoesNotHaveURL
    case failedToCreateURL
    case failedToEncodePathSegment(String)
}
