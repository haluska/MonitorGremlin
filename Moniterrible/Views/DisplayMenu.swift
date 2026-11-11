import SwiftUI

/// With `.menuBarExtraStyle(.menu)` each control renders as a menu item, so
/// a `Toggle` is an item with a checkmark.
struct DisplayMenu: View {
    let viewModel: DisplayMenuViewModel

    private static let displaySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!

    var body: some View {
        Section("Monitors") {
            ForEach(viewModel.displays) { display in
                Toggle(display.name, isOn: Binding(
                    get: { display.isConnected },
                    set: { _ in viewModel.toggle(display) }
                ))
                .disabled(!viewModel.canToggle(display))
            }
        }

        if let errorMessage = viewModel.errorMessage {
            Divider()
            Text(errorMessage)
        }

        Divider()

        Button("Display Settings…") {
            NSWorkspace.shared.open(Self.displaySettingsURL)
        }

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { viewModel.launchesAtLogin },
            set: { viewModel.setLaunchesAtLogin($0) }
        ))

        Button("About Moniterrible") {
            AboutPanel.show()
        }

        Button("Quit Moniterrible") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
