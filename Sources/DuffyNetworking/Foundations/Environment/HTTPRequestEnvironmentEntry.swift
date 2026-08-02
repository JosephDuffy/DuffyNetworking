/// Creates an HTTP request environment value and its associated key.
///
/// Apply this macro to a property in an extension of ``HTTPRequestEnvironmentValues``:
///
/// ```swift
/// extension HTTPRequestEnvironmentValues {
///     @HTTPRequestEnvironmentEntry
///     public var retryLimit: Int = 3
/// }
/// ```
@attached(accessor)
@attached(peer, names: prefixed(__HTTPRequestEnvironmentEntry_))
public macro HTTPRequestEnvironmentEntry() = #externalMacro(
    module: "DuffyNetworkingMacros",
    type: "HTTPRequestEnvironmentEntryMacro",
)
