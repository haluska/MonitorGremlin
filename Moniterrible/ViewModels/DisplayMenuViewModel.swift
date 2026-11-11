import AppKit
import Observation

@Observable
final class DisplayMenuViewModel {
    private(set) var displays: [Display] = []

    /// Shown at the bottom of the menu.
    private(set) var errorMessage: String?

    private(set) var launchesAtLogin: Bool

    private let service: DisplayControlling
    private let loginItem: LoginItemControlling

    init(
        service: DisplayControlling = DisplayService(),
        loginItem: LoginItemControlling = LoginItem()
    ) {
        self.service = service
        self.loginItem = loginItem
        launchesAtLogin = loginItem.isEnabled
        refresh()
        watchForScreenChanges()
    }

    func refresh() {
        displays = service.currentDisplays()
    }

    /// `false` for the last connected monitor, so there's always a screen left.
    func canToggle(_ display: Display) -> Bool {
        let connectedCount = displays.filter(\.isConnected).count
        return !(display.isConnected && connectedCount <= 1)
    }

    func toggle(_ display: Display) {
        guard canToggle(display) else { return }
        do {
            try service.setConnected(!display.isConnected, displayID: display.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        launchesAtLogin = loginItem.isEnabled
    }

    /// Refreshes the list when monitors are plugged in, unplugged or rearranged.
    private func watchForScreenChanges() {
        let changes = NotificationCenter.default.notifications(
            named: NSApplication.didChangeScreenParametersNotification
        )
        Task { [weak self] in
            for await _ in changes {
                self?.refresh()
            }
        }
    }
}
