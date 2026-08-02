import DuffyNetworking
import Testing

extension HTTPRequestEnvironmentValues {
    @HTTPRequestEnvironmentEntry
    fileprivate var macroTestValue: String = "default"
}

@Suite
struct HTTPRequestEnvironmentEntryTests {
    @Test
    func returnsDefaultAndStoresOverride() {
        var values = HTTPRequestEnvironmentValues()

        #expect(values.macroTestValue == "default")

        values.macroTestValue = "override"

        #expect(values.macroTestValue == "override")
    }
}
