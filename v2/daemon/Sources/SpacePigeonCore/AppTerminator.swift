import AppKit
import Foundation

public struct AppTerminationResult {
    public let closed: [String]
    public let forceKilled: [String]
    public let failures: [FailureEvent]

    public init(closed: [String], forceKilled: [String], failures: [FailureEvent]) {
        self.closed = closed
        self.forceKilled = forceKilled
        self.failures = failures
    }
}

public final class AppTerminator {
    public init() {}

    public func closeAllExcept(_ keepAlive: Set<String>, dryRun: Bool) -> AppTerminationResult {
        var closed: [String] = []
        var forceKilled: [String] = []
        var failures: [FailureEvent] = []

        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }

        for app in running {
            let name = app.localizedName ?? app.bundleIdentifier ?? "unknown"
            if keepAlive.contains(name) {
                continue
            }

            if dryRun {
                closed.append(name)
                continue
            }

            if app.terminate() {
                closed.append(name)
                continue
            }

            if app.forceTerminate() {
                forceKilled.append(name)
            } else {
                failures.append(FailureEvent(
                    code: .permission,
                    message: "Unable to terminate app \(name)",
                    operation: "close_all_apps"
                ))
            }
        }

        return AppTerminationResult(closed: closed, forceKilled: forceKilled, failures: failures)
    }
}
