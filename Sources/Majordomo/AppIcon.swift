import AppKit

enum AppIcon {
    /// Status-bar glyph with an optional colored state dot in the lower-right
    /// corner. The dot is the always-present, glanceable signal of dictation
    /// state (recording/transcribing/error) even when the on-screen indicator
    /// is disabled.
    static func makeStatusBarImage(badge: NSColor? = nil) -> NSImage? {
        let base = makeImage(size: NSSize(width: 22, height: 22))
            ?? NSImage(systemSymbolName: "person.fill", accessibilityDescription: "Majordomo")
        guard let base, let badge else { return base }

        let badged = NSImage(size: base.size)
        badged.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size))
        let d: CGFloat = 8
        let rect = NSRect(x: base.size.width - d, y: 0, width: d, height: d)
        badge.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.black.withAlphaComponent(0.35).setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()
        badged.unlockFocus()
        badged.isTemplate = false
        return badged
    }

    static func makeAboutImage() -> NSImage? {
        makeImage(size: NSSize(width: 88, height: 88))
    }

    private static func makeImage(size: NSSize) -> NSImage? {
        let resourceURL = Bundle.appResourceURL(forResource: "majordomo", withExtension: "png")

        guard let resourceURL, let source = NSImage(contentsOf: resourceURL) else {
            return nil
        }

        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
