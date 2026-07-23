import AppKit

/// A native template image for the MenuBarExtra label. AppKit owns the menu-bar
/// tint and contrast, while the three panels preserve FocusTrace's brand shape.
@MainActor
public enum FocusTraceMenuBarIcon {
    private static let idle = makeImage(isFocusing: false)
    private static let focusing = makeImage(isFocusing: true)

    public static func image(isFocusing: Bool) -> NSImage {
        isFocusing ? focusing : idle
    }

    private static func makeImage(isFocusing: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            drawPanel(
                NSRect(x: 1.25, y: 4, width: 4.25, height: 8),
                alpha: isFocusing ? 0.76 : 0.54
            )
            drawPanel(
                NSRect(x: 6.875, y: 1.5, width: 4.25, height: 13),
                alpha: 1
            )
            drawPanel(
                NSRect(x: 12.5, y: 4, width: 4.25, height: 8),
                alpha: isFocusing ? 0.76 : 0.54
            )
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = isFocusing
            ? "FocusTrace 正在专注"
            : "FocusTrace"
        return image
    }

    private static func drawPanel(_ rect: NSRect, alpha: CGFloat) {
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(
            roundedRect: rect,
            xRadius: 1.35,
            yRadius: 1.35
        ).fill()
    }
}
