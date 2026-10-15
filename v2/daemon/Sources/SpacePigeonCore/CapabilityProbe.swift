import Foundation

public struct CapabilityReport: Codable {
    public let macOSVersion: String
    public let isVersionSupported: Bool
    public let skylightLoaded: Bool
    public let symbols: [String: Bool]

    public init(macOSVersion: String, isVersionSupported: Bool, skylightLoaded: Bool, symbols: [String: Bool]) {
        self.macOSVersion = macOSVersion
        self.isVersionSupported = isVersionSupported
        self.skylightLoaded = skylightLoaded
        self.symbols = symbols
    }
}

public struct CapabilityProbe {
    private static let requiredSymbols = [
        "CGSCopyManagedDisplaySpaces",
        "CGSGetActiveSpace",
        "CGSManagedDisplaySetCurrentSpace",
    ]

    public init() {}

    public func run() -> CapabilityReport {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let supported = os.majorVersion >= 14

        let bridge = PrivateCGSBridge()
        let loaded = bridge.loadSkyLight()
        var symbolMap: [String: Bool] = [:]
        for symbol in Self.requiredSymbols {
            symbolMap[symbol] = bridge.hasSymbol(symbol)
        }

        return CapabilityReport(
            macOSVersion: version,
            isVersionSupported: supported,
            skylightLoaded: loaded,
            symbols: symbolMap
        )
    }
}
