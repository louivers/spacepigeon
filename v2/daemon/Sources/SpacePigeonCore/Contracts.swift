import Foundation

public struct ResetRequest: Codable {
    public let mainSpaces: Int
    public let secondarySpaces: Int
    public let closeAll: Bool
    public let keepAliveApps: [String]
    public let dryRun: Bool

    public init(mainSpaces: Int, secondarySpaces: Int, closeAll: Bool, keepAliveApps: [String], dryRun: Bool) {
        self.mainSpaces = mainSpaces
        self.secondarySpaces = secondarySpaces
        self.closeAll = closeAll
        self.keepAliveApps = keepAliveApps
        self.dryRun = dryRun
    }
}

public struct ResetResult: Codable {
    public let request: ResetRequest
    public let startedAt: Date
    public let endedAt: Date
    public let capabilityReport: CapabilityReport
    public let closedApps: [String]
    public let forcedKilledApps: [String]
    public let verification: VerificationReport
    public let recoveryActions: [String]
    public let failures: [FailureEvent]

    public init(
        request: ResetRequest,
        startedAt: Date,
        endedAt: Date,
        capabilityReport: CapabilityReport,
        closedApps: [String],
        forcedKilledApps: [String],
        verification: VerificationReport,
        recoveryActions: [String],
        failures: [FailureEvent]
    ) {
        self.request = request
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.capabilityReport = capabilityReport
        self.closedApps = closedApps
        self.forcedKilledApps = forcedKilledApps
        self.verification = verification
        self.recoveryActions = recoveryActions
        self.failures = failures
    }
}

public struct VerificationReport: Codable {
    public let targetMainSpaces: Int
    public let targetSecondarySpaces: Int
    public let observedMainSpaces: Int?
    public let observedSecondarySpaces: Int?
    public let success: Bool

    public init(targetMainSpaces: Int, targetSecondarySpaces: Int, observedMainSpaces: Int?, observedSecondarySpaces: Int?, success: Bool) {
        self.targetMainSpaces = targetMainSpaces
        self.targetSecondarySpaces = targetSecondarySpaces
        self.observedMainSpaces = observedMainSpaces
        self.observedSecondarySpaces = observedSecondarySpaces
        self.success = success
    }
}
