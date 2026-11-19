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

    /// Every monitor macOS knows about, including disconnected ones.
    func allDisplayIDs() -> [CGDirectDisplayID]

    /// The name shown in System Settings > Displays, or nil if macOS isn't
    /// using the monitor.
    func name(of displayID: CGDirectDisplayID) -> String?

    /// Nil if macOS doesn't know the ID.
    func identity(of displayID: CGDirectDisplayID) -> DisplayIdentity?

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

    func allDisplayIDs() -> [CGDirectDisplayID] {
        PrivateDisplayAPI.allDisplayIDs() ?? activeDisplayIDs()
    }

    func name(of displayID: CGDirectDisplayID) -> String? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value == displayID
        }
        return screen?.localizedName
    }

    func identity(of displayID: CGDirectDisplayID) -> DisplayIdentity? {
        let vendor = CGDisplayVendorNumber(displayID)
        // macOS answers 0xFFFFFFFF for an ID it doesn't know.
        guard vendor != .max else { return nil }
        return DisplayIdentity(
            vendor: vendor,
            model: CGDisplayModelNumber(displayID),
            serial: CGDisplaySerialNumber(displayID)
        )
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
    /// A monitor Monitor Gremlin disconnected. macOS stops reporting its name
    /// once it's disconnected, so the name is kept here.
    private struct RememberedDisplay: Equatable {
        var name: String
        var identity: DisplayIdentity?
    }

    private let system: DisplaySystem
    private let defaults: UserDefaults
    private let disconnectedKey = "disconnectedDisplays"

    init(system: DisplaySystem = SystemDisplays(), defaults: UserDefaults = .standard) {
        self.system = system
        self.defaults = defaults
    }

    // MARK: - DisplayControlling

    func currentDisplays() -> [Display] {
        let connectedIDs = system.activeDisplayIDs()
        let remembered = updatedRememberedDisplays(connectedIDs: connectedIDs)

        let connected = connectedIDs.map { id in
            Display(id: id, name: name(of: id), isConnected: true)
        }
        let disconnected = remembered.map { id, display in
            Display(id: id, name: display.name, isConnected: false)
        }
        // The ID breaks ties so two monitors of the same model keep their order.
        return (connected + disconnected).sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    func setConnected(_ connected: Bool, displayID: CGDirectDisplayID) throws {
        var remembered = rememberedDisplays()

        guard connected else {
            // macOS forgets the name and ID details once the monitor is disconnected.
            let display = RememberedDisplay(name: name(of: displayID), identity: system.identity(of: displayID))
            try system.setEnabled(false, displayID: displayID)
            remembered[displayID] = display
            saveRememberedDisplays(remembered)
            return
        }

        // The menu can be out of date if the ID changed since it was last refreshed.
        let allIDs = system.allDisplayIDs()
        let targetID = remembered[displayID].flatMap { display in
            currentID(
                of: displayID, display,
                allIDs: allIDs,
                connectedIDs: system.activeDisplayIDs(),
                taken: Set(remembered.keys)
            )
        } ?? displayID

        do {
            try system.setEnabled(true, displayID: targetID)
        } catch {
            // Keep listing a monitor macOS still knows about, so it can be tried
            // again. One macOS no longer knows has been unplugged.
            if !allIDs.contains(targetID), remembered.removeValue(forKey: displayID) != nil {
                saveRememberedDisplays(remembered)
            }
            throw error
        }

        remembered[displayID] = nil
        remembered[targetID] = nil
        saveRememberedDisplays(remembered)
    }

    // MARK: - Helpers

    private func name(of displayID: CGDirectDisplayID) -> String {
        system.name(of: displayID)
            ?? rememberedDisplays()[displayID]?.name
            ?? "Display \(displayID)"
    }

    /// The remembered monitors after dropping the ones that came back by
    /// themselves (after a logout or restart, or by being plugged in again)
    /// and following the ones whose ID changed.
    private func updatedRememberedDisplays(
        connectedIDs: [CGDirectDisplayID]
    ) -> [CGDirectDisplayID: RememberedDisplay] {
        let stored = rememberedDisplays()
        let allIDs = system.allDisplayIDs()
        var updated: [CGDirectDisplayID: RememberedDisplay] = [:]

        for (id, display) in stored.sorted(by: { $0.key < $1.key }) {
            if connectedIDs.contains(id) { continue }

            if let currentID = currentID(
                of: id, display,
                allIDs: allIDs,
                connectedIDs: connectedIDs,
                taken: Set(stored.keys).union(updated.keys)
            ) {
                updated[currentID] = display
            } else if let identity = display.identity,
                      connectedIDs.contains(where: { system.identity(of: $0) == identity }) {
                continue
            } else {
                updated[id] = display
            }
        }

        if updated != stored {
            saveRememberedDisplays(updated)
        }
        return updated
    }

    /// The ID a remembered monitor has now, or nil if macOS no longer knows it.
    /// macOS can give a disconnected monitor a new ID, so when the old one is
    /// gone this looks for an unclaimed disconnected monitor with the same hardware.
    private func currentID(
        of id: CGDirectDisplayID,
        _ display: RememberedDisplay,
        allIDs: [CGDirectDisplayID],
        connectedIDs: [CGDirectDisplayID],
        taken: Set<CGDirectDisplayID>
    ) -> CGDirectDisplayID? {
        if allIDs.contains(id) { return id }
        guard let identity = display.identity else { return nil }
        return allIDs.first { candidate in
            !connectedIDs.contains(candidate)
                && !taken.contains(candidate)
                && system.identity(of: candidate) == identity
        }
    }

    /// Stored as `["displayID": ["name": String, "vendor": UInt32, "model": UInt32, "serial": UInt32]]`.
    private func rememberedDisplays() -> [CGDirectDisplayID: RememberedDisplay] {
        let stored = defaults.dictionary(forKey: disconnectedKey) as? [String: [String: Any]] ?? [:]
        var result: [CGDirectDisplayID: RememberedDisplay] = [:]
        for (key, fields) in stored {
            guard let id = CGDirectDisplayID(key), let name = fields["name"] as? String else { continue }
            var identity: DisplayIdentity?
            if let vendor = (fields["vendor"] as? NSNumber)?.uint32Value,
               let model = (fields["model"] as? NSNumber)?.uint32Value,
               let serial = (fields["serial"] as? NSNumber)?.uint32Value {
                identity = DisplayIdentity(vendor: vendor, model: model, serial: serial)
            }
            result[id] = RememberedDisplay(name: name, identity: identity)
        }
        return result
    }

    private func saveRememberedDisplays(_ displays: [CGDirectDisplayID: RememberedDisplay]) {
        var stored: [String: [String: Any]] = [:]
        for (id, display) in displays {
            var fields: [String: Any] = ["name": display.name]
            if let identity = display.identity {
                fields["vendor"] = NSNumber(value: identity.vendor)
                fields["model"] = NSNumber(value: identity.model)
                fields["serial"] = NSNumber(value: identity.serial)
            }
            stored[String(id)] = fields
        }
        defaults.set(stored, forKey: disconnectedKey)
    }
}
