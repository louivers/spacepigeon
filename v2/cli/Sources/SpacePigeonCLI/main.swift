import Foundation
import SpacePigeonCore

struct CLI {
    static func run() -> Int32 {
        let args = CommandLine.arguments.dropFirst()
        guard let command = args.first else {
            printUsage()
            return 1
        }

        switch command {
        case "reset":
            return runReset(Array(args.dropFirst()))
        case "probe":
            let report = CapabilityProbe().run()
            printJSON(report)
            return 0
        default:
            printUsage()
            return 1
        }
    }

    private static func runReset(_ args: [String]) -> Int32 {
        var mainSpaces = 3
        var secondarySpaces = 0
        var closeAll = false
        var dryRun = false
        var keepAlive: [String] = []

        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--main-spaces":
                index += 1
                mainSpaces = Int(args[safe: index] ?? "") ?? mainSpaces
            case "--secondary-spaces":
                index += 1
                secondarySpaces = Int(args[safe: index] ?? "") ?? secondarySpaces
            case "--close-all":
                closeAll = true
            case "--dry-run":
                dryRun = true
            case "--keep-alive":
                index += 1
                keepAlive = (args[safe: index] ?? "")
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            default:
                break
            }
            index += 1
        }

        let request = ResetRequest(
            mainSpaces: max(1, mainSpaces),
            secondarySpaces: max(0, secondarySpaces),
            closeAll: closeAll,
            keepAliveApps: keepAlive,
            dryRun: dryRun
        )
        let result = ResetPipeline().run(request)
        printJSON(result)
        return result.verification.success ? 0 : 2
    }

    private static func printUsage() {
        print(
            """
            Usage:
              spacepigeon reset --main-spaces N --secondary-spaces M [--close-all] [--keep-alive App1,App2] [--dry-run]
              spacepigeon probe
            """
        )
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            print(text)
        } else {
            print("{\"error\":\"encoding_failed\"}")
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

exit(CLI.run())
