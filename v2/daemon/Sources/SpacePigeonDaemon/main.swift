import Foundation
import SpacePigeonCore

struct DaemonEnvelope: Codable {
    let command: String
    let payload: ResetRequest?
}

@main
struct SpacePigeonDaemonMain {
    static func main() {
        // Prototype daemon: read one JSON command from stdin, return one JSON response.
        // This keeps interfaces stable while transport evolves to XPC.
        let inputData = FileHandle.standardInput.readDataToEndOfFile()
        guard
            let envelope = try? JSONDecoder().decode(DaemonEnvelope.self, from: inputData),
            envelope.command == "reset",
            let request = envelope.payload
        else {
            print("{\"error\":\"invalid_command\"}")
            return
        }

        let result = ResetPipeline().run(request)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let output = try? encoder.encode(result), let text = String(data: output, encoding: .utf8) else {
            print("{\"error\":\"encoding_failed\"}")
            return
        }
        print(text)
    }
}
