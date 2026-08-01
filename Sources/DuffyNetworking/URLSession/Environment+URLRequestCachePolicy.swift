#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

private enum URLRequestCachePolicyKey: HTTPRequestEnvironmentKey {
    static let defaultValue: URLRequest.CachePolicy? = nil
}

extension HTTPRequestEnvironmentValues {
    public var urlRequestCachePolicy: URLRequest.CachePolicy? {
        get { self[URLRequestCachePolicyKey.self] }
        set { self[URLRequestCachePolicyKey.self] = newValue }
    }
}
