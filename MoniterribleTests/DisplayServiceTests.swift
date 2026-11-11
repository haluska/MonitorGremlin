import CoreGraphics
import Foundation
import Testing
@testable import Moniterrible

final class FakeDisplaySystem: DisplaySystem {
    /// Active monitors, ID to name.
    var active: [CGDirectDisplayID: String]
    var errorToThrow: Error?

    init(active: [CGDirectDisplayID: String]) {
        self.active = active
    }

    func activeDisplayIDs() -> [CGDirectDisplayID] {
        Array(active.keys)
    }

    func name(of displayID: CGDirectDisplayID) -> String? {
        active[displayID]
    }

    func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) throws {
        if let errorToThrow { throw errorToThrow }
        active[displayID] = enabled ? "Display \(displayID)" : nil
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
        system.active[2] = "DELL S3221QS"

        #expect(service.currentDisplays() == [
            Display(id: 1, name: "Built-in Retina Display", isConnected: true),
            Display(id: 2, name: "DELL S3221QS", isConnected: true),
        ])

        // Still gone from the remembered list after it drops out again.
        system.active[2] = nil
        #expect(service.currentDisplays().map(\.id) == [1])
    }

    @Test func forgetsADisplayThatFailsToReconnect() throws {
        try service.setConnected(false, displayID: 2)
        system.errorToThrow = DisplayError.failed(.illegalArgument)

        #expect(throws: DisplayError.self) {
            try service.setConnected(true, displayID: 2)
        }
        #expect(service.currentDisplays().map(\.id) == [1])
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
