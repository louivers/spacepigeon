import Darwin
import Foundation

public final class PrivateCGSBridge {
    private var handle: UnsafeMutableRawPointer?

    public init() {}

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    @discardableResult
    public func loadSkyLight() -> Bool {
        if handle != nil {
            return true
        }
        handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        return handle != nil
    }

    public func hasSymbol(_ name: String) -> Bool {
        guard let handle else {
            return false
        }
        return dlsym(handle, name) != nil
    }
}
