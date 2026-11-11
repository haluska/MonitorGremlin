import CoreGraphics

/// A monitor in the menu: connected, or disconnected by Moniterrible.
struct Display: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let isConnected: Bool
}
