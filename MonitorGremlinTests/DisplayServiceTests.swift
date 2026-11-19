import CoreGraphics
import Foundation
import Testing
@testable import MonitorGremlin

final class FakeDisplaySystem: DisplaySystem {
    /// Active monitors, ID to name.
    var active: [CGDirectDisplayID: String]
    /// Disconnected monitors macOS still knows about, ID to name.
    var hidden: [CGDirectDisplayID: String] = [:]
    /// Defaults to a different identity for every known ID.
    var identities: [CGDirectDisplayID: DisplayIdentity] = [:]
    var errorToThrow: Error?

    init(active: [CGDirectDisplayID: String]) {
        self.active = active
    }

    func activeDisplayIDs() -> [CGDirectDisplayID] {
        Array(active.keys)
    }

    func allDisplayIDs() -> [CGDirectDisplayID] {
        Array(active.keys) + Array(hidden.keys)
    }

    func name(of displayID: CGDirectDisplayID) -> String? {
        active[displayID]
    }

    func identity(of displayID: CGDirectDisplayID) -> DisplayIdentity? {
        guard allDisplayIDs().contains(displayID) else { return nil }
        return identities[displayID] ?? DisplayIdentity(vendor: 1, model: 1, serial: displayID)
    }

    func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) throws {
        if let errorToThrow { throw errorToThrow }
        if enabled {
            guard let name = hidden.removeValue(forKey: displayID) else {
                throw DisplayError.failed(.failure)
            }
            active[displayID] = name
        } else {
            hidden[displayID] = active.removeValue(forKey: displayID)
        }
    }

    /// What macOS does when it gives a disconnected monitor a new ID.
    func changeHiddenID(from oldID: CGDirectDisplayID, to newID: CGDirectDisplayID) {
        identities[newID] = identity(of: oldID)
        hidden[newID] = hidden.removeValue(forKey: oldID)
    }
}

/// Keeps values in memory so the tests leave no preference files behind,
/// and counts writes to check that reading the display list doesn't save.
nonisolated final class InMemoryDefaults: UserDefaults, @unchecked Sendable {
    nonisolated(unsafe) private var values: [String: Any] = [:]
    nonisolated(unsafe) private(set) var writeCount = 0

    override func set(_ value: Any?, forKey defaultName: String) {
        writeCount += 1
        values[defaultName] = value
    }

    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        values[defaultName] as? [String: Any]
    }
}

struct DisplayServiceTests {
    let defaults = InMemoryDefaults()
    let system = FakeDisplaySystem(active: [1: "Built-in Retina Display", 2: "DELL S3221QS"])
    let service: DisplayService

    init() {
        service = DisplayService(system: system, defaults: defaults)
    }

    @Test func listsActiveDisplaysSortedByName() {
        #expect(service.currentDisplays() == [
            Display(id: 1, name: "Built-in Retina Display", isConnected: true),
            Display(id: 2, name: "DELL S3221QS", isConnected: true),
        ])
    }

    @Test func remembersADisconnectedDisplayByName() throws {
        try service.setConnected(false, displayID: 2)

        #expect(service.currentDisplays() == [
            Display(id: 1, name: "Built-in Retina Display", isConnected: true),
            Display(id: 2, name: "DELL S3221QS", isConnected: false),
        ])
    }

    @Test func rememberedDisplaysSurviveANewServiceInstance() throws {
        try service.setConnected(false, displayID: 2)

        let relaunched = DisplayService(system: system, defaults: defaults)

        #expect(relaunched.currentDisplays().contains(
            Display(id: 2, name: "DELL S3221QS", isConnected: false)
        ))
    }

    @Test func forgetsADisplayOnceReconnected() throws {
        try service.setConnected(false, displayID: 2)
        try service.setConnected(true, displayID: 2)

        #expect(service.currentDisplays().map(\.isConnected) == [true, true])
    }

    @Test func forgetsADisplayThatCameBackByItself() throws {
        try service.setConnected(false, displayID: 2)
        system.active[2] = system.hidden.removeValue(forKey: 2)

        #expect(service.currentDisplays() == [
            Display(id: 1, name: "Built-in Retina Display", isConnected: true),
            Display(id: 2, name: "DELL S3221QS", isConnected: true),
        ])

        // Still gone from the remembered list after it's unplugged.
        system.active[2] = nil
        #expect(service.currentDisplays().map(\.id) == [1])
    }

    @Test func keepsADisplayThatFailsToReconnectWhileStillPluggedIn() throws {
        try service.setConnected(false, displayID: 2)
        system.errorToThrow = DisplayError.failed(.failure)

        #expect(throws: DisplayError.self) {
            try service.setConnected(true, displayID: 2)
        }
        #expect(service.currentDisplays().contains(
            Display(id: 2, name: "DELL S3221QS", isConnected: false)
        ))
    }

    @Test func forgetsAnUnpluggedDisplayThatFailsToReconnect() throws {
        try service.setConnected(false, displayID: 2)
        system.hidden[2] = nil

        #expect(throws: DisplayError.self) {
            try service.setConnected(true, displayID: 2)
        }
        #expect(service.currentDisplays().map(\.id) == [1])
    }

    @Test func followsADisplayWhoseIDChangedWhileDisconnected() throws {
        try service.setConnected(false, displayID: 2)
        system.changeHiddenID(from: 2, to: 3)

        #expect(service.currentDisplays() == [
            Display(id: 1, name: "Built-in Retina Display", isConnected: true),
            Display(id: 3, name: "DELL S3221QS", isConnected: false),
        ])

        try service.setConnected(true, displayID: 3)
        #expect(service.currentDisplays() == [
            Display(id: 1, name: "Built-in Retina Display", isConnected: true),
            Display(id: 3, name: "DELL S3221QS", isConnected: true),
        ])
    }

    @Test func reconnectsUnderTheNewIDWhenTheMenuIsOutOfDate() throws {
        try service.setConnected(false, displayID: 2)
        system.changeHiddenID(from: 2, to: 3)

        try service.setConnected(true, displayID: 2)

        #expect(system.active[3] == "DELL S3221QS")
        #expect(service.currentDisplays().map(\.isConnected) == [true, true])
    }

    @Test func forgetsADisplayThatCameBackWithANewID() throws {
        try service.setConnected(false, displayID: 2)
        system.changeHiddenID(from: 2, to: 3)
        system.active[3] = system.hidden.removeValue(forKey: 3)

        #expect(service.currentDisplays() == [
            Display(id: 1, name: "Built-in Retina Display", isConnected: true),
            Display(id: 3, name: "DELL S3221QS", isConnected: true),
        ])
    }

    @Test func ignoresHiddenDisplaysOfOtherModels() throws {
        // Like the Touch Bar, which macOS lists as a hidden display.
        system.hidden[3] = "Touch Bar"
        try service.setConnected(false, displayID: 2)
        system.hidden[2] = nil

        #expect(service.currentDisplays().contains(
            Display(id: 2, name: "DELL S3221QS", isConnected: false)
        ))
        #expect(throws: DisplayError.self) {
            try service.setConnected(true, displayID: 2)
        }
        #expect(system.active[3] == nil)
    }

    @Test func aFailedDisconnectRemembersNothing() {
        system.errorToThrow = DisplayError.failed(.illegalArgument)

        #expect(throws: DisplayError.self) {
            try service.setConnected(false, displayID: 2)
        }
        #expect(service.currentDisplays().map(\.isConnected) == [true, true])
    }

    @Test func identicallyNamedDisplaysKeepAStableOrder() throws {
        system.active = [1: "Built-in Retina Display", 7: "DELL S3221QS", 5: "DELL S3221QS", 9: "DELL S3221QS"]
        try service.setConnected(false, displayID: 7)
        try service.setConnected(false, displayID: 9)

        for _ in 0..<20 {
            #expect(service.currentDisplays().map(\.id) == [1, 5, 7, 9])
        }
    }

    @Test func listingDisplaysDoesNotWriteWhenNothingChanged() throws {
        try service.setConnected(false, displayID: 2)
        let writesBefore = defaults.writeCount

        _ = service.currentDisplays()
        _ = service.currentDisplays()

        #expect(defaults.writeCount == writesBefore)
    }
}
