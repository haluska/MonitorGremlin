import AppKit
import CoreGraphics

/// Display control behind a protocol so the tests can use a fake.
protocol DisplayControlling {
    /// Every monitor to show in the menu, connected or not.
    func currentDisplays() -> [Display]

    func setConnected(_ connected: Bool, displayID: CGDirectDisplayID) throws
}

/// Errors shown to the user when connecting or disconnecting fails.
enum DisplayError: LocalizedError {
    case unsupportedMacOSVersion
    case failed(CGError)

    var errorDescription: String? {
        switch self {
        case .unsupportedMacOSVersion:
            "This version of macOS doesn't support disconnecting monitors."
        case .failed(let error):
            "macOS refused the change (error \(error.rawValue))."
        }
    }
}

/// The macOS calls `DisplayService` makes, behind a protocol so the tests
/// can use a fake.
protocol DisplaySystem {
    func activeDisplayIDs() -> [CGDirectDisplayID]

    /// The name shown in System Settings > Displays, or nil if macOS isn't
    /// using the monitor.
    func name(of displayID: CGDirectDisplayID) -> String?

    func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) throws
}

struct SystemDisplays: DisplaySystem {
    func activeDisplayIDs() -> [CGDirectDisplayID] {
        let maxDisplays: UInt32 = 32
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(maxDisplays, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    func name(of displayID: CGDirectDisplayID) -> String? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value == displayID
        }
        return screen?.localizedName
    }

    func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) throws {
        var config: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&config)
        guard beginResult == .success else { throw DisplayError.failed(beginResult) }

        guard let result = PrivateDisplayAPI.setDisplay(displayID, enabled: enabled, in: config) else {
            CGCancelDisplayConfiguration(config)
            throw DisplayError.unsupportedMacOSVersion
        }
        guard result == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayError.failed(result)
        }

        // .forSession is undone at logout or restart, so a restart always
        // brings every monitor back.
        let completeResult = CGCompleteDisplayConfiguration(config, .forSession)
        guard completeResult == .success else { throw DisplayError.failed(completeResult) }
    }
}

final class DisplayService: DisplayControlling {
    private let system: DisplaySystem

    /// macOS stops listing a monitor once it's disconnected, so its ID and
    /// name are kept here.
    private let defaults: UserDefaults
    private let disconnectedKey = "disconnectedDisplays"

    init(system: DisplaySystem = SystemDisplays(), defaults: UserDefaults = .standard) {
        self.system = system
        self.defaults = defaults
    }

    // MARK: - DisplayControlling

    func currentDisplays() -> [Display] {
        let connectedIDs = system.activeDisplayIDs()
        var remembered = disconnectedDisplays()

        // A disconnected monitor comes back by itself after a logout or restart.
        let returned = connectedIDs.filter { remembered[$0] != nil }
        if !returned.isEmpty {
            for id in returned {
                remembered[id] = nil
            }
            saveDisconnectedDisplays(remembered)
        }

        let connected = connectedIDs.map { id in
            Display(id: id, name: name(of: id), isConnected: true)
        }
        let disconnected = remembered.map { id, name in
            Display(id: id, name: name, isConnected: false)
        }
        // The ID breaks ties so two monitors of the same model keep their order.
        return (connected + disconnected).sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    func setConnected(_ connected: Bool, displayID: CGDirectDisplayID) throws {
        // macOS forgets the name once the monitor is disconnected.
        let displayName = name(of: displayID)
        var remembered = disconnectedDisplays()

        do {
            try system.setEnabled(connected, displayID: displayID)
        } catch {
            // A remembered monitor that won't reconnect has been unplugged or
            // given a new ID, so stop listing it.
            if connected, remembered.removeValue(forKey: displayID) != nil {
                saveDisconnectedDisplays(remembered)
            }
            throw error
        }

        remembered[displayID] = connected ? nil : displayName
        saveDisconnectedDisplays(remembered)
    }

    // MARK: - Helpers

    private func name(of displayID: CGDirectDisplayID) -> String {
        system.name(of: displayID)
            ?? disconnectedDisplays()[displayID]
            ?? "Display \(displayID)"
    }

    /// Stored as `["displayID": "name"]`.
    private func disconnectedDisplays() -> [CGDirectDisplayID: String] {
        let stored = defaults.dictionary(forKey: disconnectedKey) as? [String: String] ?? [:]
        var result: [CGDirectDisplayID: String] = [:]
        for (key, name) in stored {
            if let id = CGDirectDisplayID(key) {
                result[id] = name
            }
        }
        return result
    }

    private func saveDisconnectedDisplays(_ displays: [CGDirectDisplayID: String]) {
        var stored: [String: String] = [:]
        for (id, name) in displays {
            stored[String(id)] = name
        }
        defaults.set(stored, forKey: disconnectedKey)
    }
}
