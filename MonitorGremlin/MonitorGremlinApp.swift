import SwiftUI

/// Menu bar only: `LSUIElement` is YES in the build settings, so there's no
/// Dock icon or Cmd-Tab entry.
@main
struct MonitorGremlinApp: App {
    @State private var viewModel = DisplayMenuViewModel()

    var body: some Scene {
        MenuBarExtra("Monitor Gremlin", image: "MenuBarIcon") {
            DisplayMenu(viewModel: viewModel)
        }
        .menuBarExtraStyle(.menu)
    }
}
