import CoreGraphics

/// A monitor in the menu: connected, or disconnected by Monitor Gremlin.
struct Display: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let isConnected: Bool
}

/// The hardware details macOS still reports for a disconnected monitor. Used
/// to find the monitor again if macOS gives it a new ID while it's disconnected.
struct DisplayIdentity: Hashable {
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
}
