import CoreGraphics
import Darwin

/// The private APIs the app uses.
///
/// These functions are exported by macOS's graphics libraries but aren't in
/// the public headers, so they're looked up with `dlsym`. If a future macOS
/// removes one, the lookup returns nil and the app falls back or shows an
/// error instead of crashing.
enum PrivateDisplayAPI {
    /// `CGError CGSConfigureDisplayEnabled(CGDisplayConfigRef, CGDirectDisplayID, bool)`
    private typealias ConfigureDisplayEnabled =
        @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    /// `CGError CGSGetDisplayList(uint32_t, CGDirectDisplayID *, uint32_t *)`
    private typealias GetDisplayList =
        @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError

    private static let configureDisplayEnabled: ConfigureDisplayEnabled? =
        lookUp("CGSConfigureDisplayEnabled")

    private static let getDisplayList: GetDisplayList? = lookUp("CGSGetDisplayList")

    /// Returns nil if this version of macOS doesn't have the function.
    static func setDisplay(
        _ displayID: CGDirectDisplayID,
        enabled: Bool,
        in config: CGDisplayConfigRef?
    ) -> CGError? {
        configureDisplayEnabled?(config, displayID, enabled)
    }

    /// Every display macOS knows about, including ones disabled with
    /// `setDisplay`, which the public display lists leave out. Returns nil if
    /// this version of macOS doesn't have the function.
    static func allDisplayIDs() -> [CGDirectDisplayID]? {
        guard let getDisplayList else { return nil }
        let maxDisplays: UInt32 = 32
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        guard getDisplayList(maxDisplays, &ids, &count) == .success else { return nil }
        return Array(ids.prefix(Int(count)))
    }

    private static func lookUp<Function>(_ name: String) -> Function? {
        // RTLD_DEFAULT is a C macro Swift doesn't import; its value is -2.
        let searchAllLoadedLibraries = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(searchAllLoadedLibraries, name) else { return nil }
        return unsafeBitCast(symbol, to: Function.self)
    }
}
