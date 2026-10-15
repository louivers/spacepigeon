import Foundation

public struct TelemetryEvent: Codable {
    public let level: String
    public let operation: String
    public let message: String
    public let timestamp: Date

    public init(level: String, operation: String, message: String, timestamp: Date = Date()) {
        self.level = level
        self.operation = operation
        self.message = message
        self.timestamp = timestamp
    }
}

public final class TelemetryLogger {
    private let encoder = JSONEncoder()
    private let logDir: URL

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        logDir = home.appendingPathComponent(".spacepigeon/v2/logs", isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    public func log(_ event: TelemetryEvent) {
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: event.timestamp).replacingOccurrences(of: ":", with: "-")
        let path = logDir.appendingPathComponent("\(stamp)-\(event.operation).json")
        if let data = try? encoder.encode(event) {
            try? data.write(to: path)
        }
    }
}
