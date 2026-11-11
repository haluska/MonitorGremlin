import CoreGraphics
import Testing
@testable import Moniterrible

/// Keeps the tests away from the real monitors.
final class FakeDisplayService: DisplayControlling {
    var displays: [Display]
    var errorToThrow: Error?
    private(set) var calls: [(connected: Bool, displayID: CGDirectDisplayID)] = []

    init(displays: [Display]) {
        self.displays = displays
    }

    func currentDisplays() -> [Display] {
        displays
    }

    func setConnected(_ connected: Bool, displayID: CGDirectDisplayID) throws {
        calls.append((connected, displayID))
        if let errorToThrow { throw errorToThrow }
        displays = displays.map { display in
            display.id == displayID
                ? Display(id: display.id, name: display.name, isConnected: connected)
                : display
        }
    }
}

final class FakeLoginItem: LoginItemControlling {
    var isEnabled = false
    var errorToThrow: Error?

    func setEnabled(_ enabled: Bool) throws {
        if let errorToThrow { throw errorToThrow }
        isEnabled = enabled
    }
}

struct DisplayMenuViewModelTests {
    let builtIn = Display(id: 1, name: "Built-in Retina Display", isConnected: true)
    let dell = Display(id: 2, name: "DELL S3221QS", isConnected: true)

    @Test func loadsDisplaysFromService() {
        let viewModel = DisplayMenuViewModel(service: FakeDisplayService(displays: [builtIn, dell]))

        #expect(viewModel.displays == [builtIn, dell])
    }

    @Test func disconnectsAConnectedDisplay() {
        let service = FakeDisplayService(displays: [builtIn, dell])
        let viewModel = DisplayMenuViewModel(service: service)

        viewModel.toggle(dell)

        #expect(service.calls.count == 1)
        #expect(service.calls.first?.connected == false)
        #expect(service.calls.first?.displayID == dell.id)
        #expect(viewModel.displays.first { $0.id == dell.id }?.isConnected == false)
    }

    @Test func reconnectsADisconnectedDisplay() {
        let disconnectedDell = Display(id: 2, name: "DELL S3221QS", isConnected: false)
        let service = FakeDisplayService(displays: [builtIn, disconnectedDell])
        let viewModel = DisplayMenuViewModel(service: service)

        viewModel.toggle(disconnectedDell)

        #expect(service.calls.first?.connected == true)
    }

    @Test func refusesToDisconnectTheLastConnectedDisplay() {
        let disconnectedDell = Display(id: 2, name: "DELL S3221QS", isConnected: false)
        let service = FakeDisplayService(displays: [builtIn, disconnectedDell])
        let viewModel = DisplayMenuViewModel(service: service)

        #expect(viewModel.canToggle(builtIn) == false)
        viewModel.toggle(builtIn)
        #expect(service.calls.isEmpty)
    }

    @Test func showsAnErrorWhenTheChangeFails() {
        let service = FakeDisplayService(displays: [builtIn, dell])
        service.errorToThrow = DisplayError.unsupportedMacOSVersion
        let viewModel = DisplayMenuViewModel(service: service)

        viewModel.toggle(dell)

        #expect(viewModel.errorMessage == DisplayError.unsupportedMacOSVersion.errorDescription)
    }

    @Test func readsLaunchAtLoginFromTheLoginItem() {
        let loginItem = FakeLoginItem()
        loginItem.isEnabled = true
        let viewModel = DisplayMenuViewModel(
            service: FakeDisplayService(displays: [builtIn]),
            loginItem: loginItem
        )

        #expect(viewModel.launchesAtLogin)
    }

    @Test func turnsLaunchAtLoginOnAndOff() {
        let loginItem = FakeLoginItem()
        let viewModel = DisplayMenuViewModel(
            service: FakeDisplayService(displays: [builtIn]),
            loginItem: loginItem
        )

        viewModel.setLaunchesAtLogin(true)
        #expect(loginItem.isEnabled)
        #expect(viewModel.launchesAtLogin)

        viewModel.setLaunchesAtLogin(false)
        #expect(loginItem.isEnabled == false)
        #expect(viewModel.launchesAtLogin == false)
    }

    @Test func showsAnErrorWhenLaunchAtLoginFails() {
        let loginItem = FakeLoginItem()
        loginItem.errorToThrow = DisplayError.unsupportedMacOSVersion
        let viewModel = DisplayMenuViewModel(
            service: FakeDisplayService(displays: [builtIn]),
            loginItem: loginItem
        )

        viewModel.setLaunchesAtLogin(true)

        #expect(viewModel.launchesAtLogin == false)
        #expect(viewModel.errorMessage != nil)
    }
}
