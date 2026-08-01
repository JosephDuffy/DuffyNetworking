public struct HTTPRequestEnvironmentValues: Sendable {
    private var storage: [ObjectIdentifier: any Sendable]

    public init() {
        storage = [:]
    }

    public subscript<Key>(key: Key.Type) -> Key.Value where Key: HTTPRequestEnvironmentKey {
        get {
            let identifier = ObjectIdentifier(key)

            guard let value = storage[identifier] as? Key.Value else {
                return Key.defaultValue
            }

            return value
        }
        set {
            let value: any Sendable = newValue
            storage[ObjectIdentifier(key)] = value
        }
    }

    /// Returns a copy containing these values overlaid with explicitly stored values from
    /// `overrides`. Values from `overrides` take precedence.
    internal func merging(_ overrides: HTTPRequestEnvironmentValues) -> HTTPRequestEnvironmentValues {
        var values = self
        values.storage.merge(overrides.storage) { _, override in override }
        return values
    }
}
