import AppKit

/// The standard About window. The icon, name, version (MARKETING_VERSION) and
/// copyright (INFOPLIST_KEY_NSHumanReadableCopyright) come from the build
/// settings; only the credits text is set here.
enum AboutPanel {
    static func show() {
        // A menu bar app is never frontmost, so without this the window can
        // open behind other windows.
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private static var credits: NSAttributedString {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center

        return NSAttributedString(
            string: "Connect and disconnect your monitors from the menu bar.",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: centered,
            ]
        )
    }
}
