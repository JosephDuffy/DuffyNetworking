#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The errors produced by response validators, in validator execution order.
public struct ResponseValidatorErrors: LocalizedError {
    public let errors: [any Error]

    public var errorDescription: String? {
        let descriptions = errors
            .compactMap { error in
                if let error = error as? LocalizedError {
                    return error.errorDescription
                } else {
                    return error.localizedDescription
                }
            }

        if descriptions.isEmpty {
            return nil
        } else {
            return descriptions.joined(separator: "\n")
        }
    }

    internal init(errors: [any Error]) {
        precondition(!errors.isEmpty)
        self.errors = errors
    }
}
