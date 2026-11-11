# Moniterrible

A macOS menu bar app that connects and disconnects monitors without unplugging any cables.

<img src="Design/Screenshot.png" alt="The Moniterrible menu listing two connected monitors" width="313">

Click the gremlin icon to see your monitors. A checkmark means the monitor is connected; click a monitor to flip it. Disconnecting a monitor makes macOS act as if it was unplugged, so windows move to your other screens.

A disconnected monitor stays in the menu so you can connect it again, including after quitting and reopening the app. If a monitor can't be reconnected (for example because it has since been unplugged), the menu shows the error and stops listing it.

The menu also has a shortcut to Display Settings and a **Launch at Login** option.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 26 or later

## Build and run

1. Open `Moniterrible.xcodeproj` in Xcode.
2. Press **Cmd-R** to run. The gremlin appears in the menu bar (there is no window or dock icon).
3. Press **Cmd-U** to run the unit tests.

To stop the app, choose **Quit Moniterrible** from its menu.

## How the code is organized

The app uses MVVM (Model–View–ViewModel).

| File | Role |
| --- | --- |
| `Moniterrible/MoniterribleApp.swift` | Entry point; creates the menu bar icon |
| `Moniterrible/Models/Display.swift` | One monitor (ID, name, connected or not) |
| `Moniterrible/Services/DisplayService.swift` | Lists monitors, connects and disconnects them, and remembers the disconnected ones. The macOS calls sit behind the `DisplaySystem` protocol |
| `Moniterrible/Services/PrivateDisplayAPI.swift` | The single private macOS function call |
| `Moniterrible/Services/LoginItem.swift` | Registers the app to launch at login |
| `Moniterrible/ViewModels/DisplayMenuViewModel.swift` | Menu state and actions |
| `Moniterrible/Views/DisplayMenu.swift` | The menu's contents |
| `Moniterrible/Views/AboutPanel.swift` | The About window |
| `MoniterribleTests/` | Unit tests for the view model and the service, using fakes in place of the real monitors |

## How disconnecting works

macOS has no public API for disconnecting a monitor. Moniterrible calls the undocumented `CGSConfigureDisplayEnabled` function, looked up at runtime in `PrivateDisplayAPI.swift`.

Safety items:

- **You can't disconnect your last monitor.** That menu item is disabled.
- **Changes last only until you log out or restart.** If anything goes wrong, a restart brings all connected monitors back.

## License

MIT. See [LICENSE](LICENSE).

<img src="Design/AppIcon.svg" alt="The Moniterrible menu listing two connected monitors" width="313">