import Foundation

enum ShellError: Error {
    case nonZero(Int32, String)
}

struct Shell {
    static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw ShellError.nonZero(process.terminationStatus, stderr.isEmpty ? stdout : stderr)
        }
        return stdout
    }
}
