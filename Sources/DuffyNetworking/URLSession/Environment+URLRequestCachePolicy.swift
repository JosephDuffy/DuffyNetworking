#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension HTTPRequestEnvironmentValues {
    @HTTPRequestEnvironmentEntry
    public var urlRequestCachePolicy: URLRequest.CachePolicy? = nil
}
