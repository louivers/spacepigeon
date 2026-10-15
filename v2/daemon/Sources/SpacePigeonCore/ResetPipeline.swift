import Foundation

public final class ResetPipeline {
    private let probe: CapabilityProbe
    private let appTerminator: AppTerminator
    private let spaceController: SpaceController
    private let telemetry: TelemetryLogger

    public init(
        probe: CapabilityProbe = CapabilityProbe(),
        appTerminator: AppTerminator = AppTerminator(),
        spaceController: SpaceController = SpaceController(),
        telemetry: TelemetryLogger = TelemetryLogger()
    ) {
        self.probe = probe
        self.appTerminator = appTerminator
        self.spaceController = spaceController
        self.telemetry = telemetry
    }

    public func run(_ request: ResetRequest) -> ResetResult {
        let start = Date()
        var failures: [FailureEvent] = []
        var recoveryActions: [String] = []
        telemetry.log(TelemetryEvent(level: "info", operation: "reset_start", message: "Starting reset pipeline"))

        let capability = probe.run()
        if !capability.isVersionSupported {
            failures.append(FailureEvent(
                code: .unsupportedMacOS,
                message: "macOS \(capability.macOSVersion) is outside supported range for v2 prototype",
                operation: "capability_probe"
            ))
        }

        var closeResult = AppTerminationResult(closed: [], forceKilled: [], failures: [])
        if request.closeAll {
            closeResult = appTerminator.closeAllExcept(Set(request.keepAliveApps), dryRun: request.dryRun)
            failures.append(contentsOf: closeResult.failures)
        }

        let reconcileFailures = spaceController.reconcile(
            main: request.mainSpaces,
            secondary: request.secondarySpaces,
            dryRun: request.dryRun
        )
        failures.append(contentsOf: reconcileFailures)

        if reconcileFailures.contains(where: { $0.code == .dockDesync || $0.code == .symbolMissing }) {
            recoveryActions.append("dock_restart_and_reconcile")
            let recoveryFailures = spaceController.recoverDockAndReconcile(
                main: request.mainSpaces,
                secondary: request.secondarySpaces,
                dryRun: request.dryRun
            )
            failures.append(contentsOf: recoveryFailures)
        }

        let snapshot = spaceController.snapshot()
        let verificationSuccess: Bool = {
            if request.dryRun {
                return true
            }
            guard let main = snapshot.mainSpaces else { return false }
            guard let secondary = snapshot.secondarySpaces else { return false }
            return main == request.mainSpaces && secondary == request.secondarySpaces
        }()

        if !verificationSuccess {
            failures.append(FailureEvent(
                code: .verificationFailed,
                message: "Target state not verified",
                operation: "verify_postconditions"
            ))
        }

        let verification = VerificationReport(
            targetMainSpaces: request.mainSpaces,
            targetSecondarySpaces: request.secondarySpaces,
            observedMainSpaces: snapshot.mainSpaces,
            observedSecondarySpaces: snapshot.secondarySpaces,
            success: verificationSuccess
        )
        let end = Date()
        telemetry.log(TelemetryEvent(level: "info", operation: "reset_end", message: "Completed reset pipeline; success=\(verification.success)"))

        return ResetResult(
            request: request,
            startedAt: start,
            endedAt: end,
            capabilityReport: capability,
            closedApps: closeResult.closed,
            forcedKilledApps: closeResult.forceKilled,
            verification: verification,
            recoveryActions: recoveryActions,
            failures: failures
        )
    }
}
