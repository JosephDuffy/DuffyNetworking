/// Adds request-building operations to an API client.
///
/// Apply this macro to a struct, class, or actor that declares an instance property named
/// `httpRequestPerformer` and a zero-argument instance method named `makeBaseRequest()`. The
/// declarations may be private. `makeBaseRequest()` must return an
/// `HTTPRequestConfiguration<Data>`.
@attached(member, names: named(buildAndPerformRequest))
public macro APIClient() = #externalMacro(
    module: "DuffyNetworkingMacros",
    type: "APIClientMacro",
)
