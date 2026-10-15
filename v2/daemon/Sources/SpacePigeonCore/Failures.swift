import Foundation

public enum FailureCode: String, Codable {
    case permission
    case symbolMissing
    case dockDesync
    case timeout
    case verificationFailed
    case unsupportedMacOS
    case shellError
}

public struct FailureEvent: Codable {
    public let code: FailureCode
    public let message: String
    public let operation: String
    public let timestamp: Date

    public init(code: FailureCode, message: String, operation: String, timestamp: Date = Date()) {
        self.code = code
        self.message = message
        self.operation = operation
        self.timestamp = timestamp
    }
}
