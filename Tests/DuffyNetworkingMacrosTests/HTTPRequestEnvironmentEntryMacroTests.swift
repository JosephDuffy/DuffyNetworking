import MacroTesting
import Testing

@testable import DuffyNetworkingMacros

@Suite(.serialized)
struct HTTPRequestEnvironmentEntryMacroTests {
    @Test
    func addsEnvironmentKeyAndAccessors() {
        assertMacro(["HTTPRequestEnvironmentEntry": HTTPRequestEnvironmentEntryMacro.self]) {
            """
            extension HTTPRequestEnvironmentValues {
                @HTTPRequestEnvironmentEntry
                public var retryLimit: Int = 3
            }
            """
        } expansion: {
            """
            extension HTTPRequestEnvironmentValues {
                public var retryLimit: Int {
                    get {
                        self[__HTTPRequestEnvironmentEntry_retryLimit.self]
                    }
                    set {
                        self[__HTTPRequestEnvironmentEntry_retryLimit.self] = newValue
                    }
                }

                private enum __HTTPRequestEnvironmentEntry_retryLimit: HTTPRequestEnvironmentKey {
                    static let defaultValue: Int = 3
                }
            }
            """
        }
    }

    @Test
    func supportsOptionalDefaults() {
        assertMacro(["HTTPRequestEnvironmentEntry": HTTPRequestEnvironmentEntryMacro.self]) {
            """
            extension HTTPRequestEnvironmentValues {
                @HTTPRequestEnvironmentEntry
                var label: String? = nil
            }
            """
        } expansion: {
            """
            extension HTTPRequestEnvironmentValues {
                var label: String? {
                    get {
                        self[__HTTPRequestEnvironmentEntry_label.self]
                    }
                    set {
                        self[__HTTPRequestEnvironmentEntry_label.self] = newValue
                    }
                }

                private enum __HTTPRequestEnvironmentEntry_label: HTTPRequestEnvironmentKey {
                    static let defaultValue: String? = nil
                }
            }
            """
        }
    }

    @Test
    func diagnosesDeclarationsWithoutTypeOrDefaultValue() {
        assertMacro(["HTTPRequestEnvironmentEntry": HTTPRequestEnvironmentEntryMacro.self]) {
            """
            extension HTTPRequestEnvironmentValues {
                @HTTPRequestEnvironmentEntry
                var retryLimit = 3
            }
            """
        } diagnostics: {
            """
            extension HTTPRequestEnvironmentValues {
                @HTTPRequestEnvironmentEntry
                ┬───────────────────────────
                ╰─ 🛑 '@HTTPRequestEnvironmentEntry' requires a single 'var' declaration with a type annotation and default value
                var retryLimit = 3
            }
            """
        }
    }
}
