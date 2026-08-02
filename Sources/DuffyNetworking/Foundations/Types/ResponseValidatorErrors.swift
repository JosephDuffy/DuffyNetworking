/// The errors produced by response validators, in validator execution order.
public struct ResponseValidatorErrors: Error {
    public let errors: [any Error]

    internal init(errors: [any Error]) {
        precondition(!errors.isEmpty)
        self.errors = errors
    }
}
