import CoreGraphics
import Darwin

/// The only private API the app uses.
///
/// `CGSConfigureDisplayEnabled` is exported by macOS's graphics libraries but
/// isn't in the public headers, so it's looked up with `dlsym`. If a future
/// macOS removes it, the lookup returns nil and the app shows an error
/// instead of crashing.
enum PrivateDisplayAPI {
    /// `CGError CGSConfigureDisplayEnabled(CGDisplayConfigRef, CGDirectDisplayID, bool)`
    private typealias ConfigureDisplayEnabled =
        @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    private static let configureDisplayEnabled: ConfigureDisplayEnabled? = {
        // RTLD_DEFAULT is a C macro Swift doesn't import; its value is -2.
        let searchAllLoadedLibraries = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(searchAllLoadedLibraries, "CGSConfigureDisplayEnabled") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ConfigureDisplayEnabled.self)
    }()

    /// Returns nil if this version of macOS doesn't have the function.
    static func setDisplay(
        _ displayID: CGDirectDisplayID,
        enabled: Bool,
        in config: CGDisplayConfigRef?
    ) -> CGError? {
        configureDisplayEnabled?(config, displayID, enabled)
    }
}
