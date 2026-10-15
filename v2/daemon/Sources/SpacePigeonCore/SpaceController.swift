import Foundation

public struct SpaceSnapshot {
    public let mainSpaces: Int?
    public let secondarySpaces: Int?
}

public final class SpaceController {
    private let probe: CapabilityProbe

    public init(probe: CapabilityProbe = CapabilityProbe()) {
        self.probe = probe
    }

    public func snapshot() -> SpaceSnapshot {
        guard let yabai = resolveYabaiPath(), let spaces = try? querySpaces(yabaiPath: yabai) else {
            return SpaceSnapshot(mainSpaces: nil, secondarySpaces: nil)
        }
        let grouped = Dictionary(grouping: spaces, by: { $0.display })
        return SpaceSnapshot(
            mainSpaces: grouped[1]?.count,
            secondarySpaces: grouped[2]?.count ?? 0
        )
    }

    public func reconcile(main targetMain: Int, secondary targetSecondary: Int, dryRun: Bool) -> [FailureEvent] {
        let report = probe.run()
        guard report.isVersionSupported else {
            return [FailureEvent(code: .unsupportedMacOS, message: "Unsupported macOS version \(report.macOSVersion)", operation: "reconcile_spaces")]
        }
        guard report.skylightLoaded else {
            return [FailureEvent(code: .symbolMissing, message: "Unable to load SkyLight private framework", operation: "reconcile_spaces")]
        }
        if report.symbols.values.contains(false) {
            return [FailureEvent(code: .symbolMissing, message: "Required private CGS symbol missing", operation: "reconcile_spaces")]
        }

        if dryRun {
            return []
        }

        guard let yabai = resolveYabaiPath() else {
            return [FailureEvent(code: .shellError, message: "yabai not found; install yabai for prototype reconciliation", operation: "reconcile_spaces")]
        }

        do {
            try reconcileDisplaySpaces(yabaiPath: yabai, display: 1, target: targetMain)
            if targetSecondary > 0 {
                try reconcileDisplaySpaces(yabaiPath: yabai, display: 2, target: targetSecondary)
            }
        } catch {
            return [FailureEvent(code: .shellError, message: "Space reconciliation failed: \(error)", operation: "reconcile_spaces")]
        }

        return []
    }

    public func recoverDockAndReconcile(main: Int, secondary: Int, dryRun: Bool) -> [FailureEvent] {
        if dryRun {
            return []
        }

        do {
            _ = try Shell.run("/usr/bin/killall", ["Dock"])
            Thread.sleep(forTimeInterval: 1.5)
            return reconcile(main: main, secondary: secondary, dryRun: false)
        } catch {
            return [FailureEvent(code: .dockDesync, message: "Dock restart failed: \(error)", operation: "dock_restart_and_reconcile")]
        }
    }

    private func resolveYabaiPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/yabai",
            "/usr/local/bin/yabai",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private struct YabaiSpace: Decodable {
        let index: Int
        let display: Int
    }

    private func querySpaces(yabaiPath: String) throws -> [YabaiSpace] {
        let output = try Shell.run(yabaiPath, ["-m", "query", "--spaces"])
        let data = Data(output.utf8)
        return try JSONDecoder().decode([YabaiSpace].self, from: data)
    }

    private func reconcileDisplaySpaces(yabaiPath: String, display: Int, target: Int) throws {
        let spaces = try querySpaces(yabaiPath: yabaiPath).filter { $0.display == display }
        if spaces.count == target {
            return
        }

        if spaces.count < target {
            for _ in spaces.count..<target {
                _ = try Shell.run(yabaiPath, ["-m", "display", "--focus", "\(display)"])
                _ = try Shell.run(yabaiPath, ["-m", "space", "--create"])
            }
        } else {
            // Destroy extra spaces from highest index down to reduce side effects.
            let sorted = spaces.sorted { $0.index > $1.index }
            for extra in sorted.prefix(spaces.count - target) {
                _ = try Shell.run(yabaiPath, ["-m", "space", "\(extra.index)", "--destroy"])
            }
        }
    }
}
