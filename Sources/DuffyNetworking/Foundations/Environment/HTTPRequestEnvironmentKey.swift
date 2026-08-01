public protocol HTTPRequestEnvironmentKey {
    associatedtype Value: Sendable

    static var defaultValue: Value { get }
}
